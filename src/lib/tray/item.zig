const dbus = @import("dbus");
const Allocator = std.mem.Allocator;
const c = @cImport({
    @cInclude("webp/encode.h");
});

fn pixmapToWebp(
    allocator: std.mem.Allocator,
    width: i32,
    height: i32,
    argb: []const u8,
) ![]u8 {
    var rgba = try allocator.alloc(u8, argb.len);
    defer allocator.free(rgba);

    var i: usize = 0;
    while (i < argb.len) : (i += 4) {
        const a = argb[i + 0];
        const r = argb[i + 1];
        const g = argb[i + 2];
        const b = argb[i + 3];

        rgba[i + 0] = r;
        rgba[i + 1] = g;
        rgba[i + 2] = b;
        rgba[i + 3] = a;
    }

    var output_ptr: [*c]u8 = undefined;
    const size = c.WebPEncodeRGBA(
        rgba.ptr,
        @intCast(width),
        @intCast(height),
        @intCast(width * 4),
        100.0,
        &output_ptr,
    );

    if (size == 0 or output_ptr == null) {
        return error.WebPEncodingFailed;
    }
    defer c.WebPFree(output_ptr);
    return try allocator.dupe(u8, output_ptr[0..size]);
}
const DBusPixmap = dbus.Array(dbus.Struct(.{
    dbus.Int32,
    dbus.Int32,
    dbus.Array(dbus.Byte),
}));
pub const Item = struct {
    const Self = @This();
    pub const Data = struct {
        service: []const u8,
        attention: Attention,
        category: []const u8,
        icon: Icon,
        id: []const u8,
        ItemIsMenu: bool,
        menu: []const u8,
        overlay: Overlay,
        status: []const u8,
        title: []const u8,
        tooltip: Tooltip,
    };
    pub const Pixmap = struct {
        width: i32,
        height: i32,
        webp: []const u8,
    };
    pub const Attention = struct {
        iconName: []const u8,
        iconPixmap: []const Pixmap,
        movieName: []const u8,
    };
    pub const Icon = struct {
        name: []const u8,
        themePath: []const u8,
        pixmap: []const Pixmap,
    };
    pub const Overlay = struct {
        iconName: []const u8,
        iconPixmap: []const Pixmap,
    };
    pub const Tooltip = struct {
        iconName: []const u8,
        iconPixmap: []const Pixmap,
        title: []const u8,
        text: []const u8,
    };
    const Listener = struct {
        func: *const fn (item: *Item, data: ?*anyopaque) void,
        data: ?*anyopaque,
    };
    _allocator: Allocator,
    _arena: Allocator,
    _object: *dbus.Object,
    _listeners: std.ArrayList(Listener),
    owner: []const u8,
    data: Data,

    // windowId: i32, // X11 only, not supported.
    pub fn init(allocator: Allocator, bus: *dbus.Bus, service: []const u8) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);
        const arena = try allocator.create(std.heap.ArenaAllocator);
        errdefer allocator.destroy(arena);
        arena.* = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        const arenaAllocator = arena.allocator();
        self._listeners = std.ArrayList(Listener).init(allocator);
        errdefer self._listeners.deinit();
        const split = std.mem.indexOf(u8, service, "/");
        if (split == null) return error.InvalidTarget;
        const name = try allocator.dupe(u8, service[0..split.?]);
        self.owner = name;
        const path = try allocator.dupe(u8, service[split.?..]);
        defer allocator.free(path);
        const item = bus.proxy(name, path, "org.kde.StatusNotifierItem") catch {
            bus.err.reset();
            return error.CannotConnectToItem;
        };
        self._allocator = allocator;
        self._arena = arena.allocator();
        self._object = item;
        self.data.service = try self._arena.dupe(u8, service);

        // id
        blk: {
            const id = item.get("Id", dbus.String) catch {
                item.err.reset();
                self.data.id = "";
                break :blk;
            };
            defer id.deinit();
            self.data.id = try arenaAllocator.dupe(u8, id.value);
        }
        // category
        blk: {
            const category = item.get("Category", dbus.String) catch {
                item.err.reset();
                self.data.category = "";
                break :blk;
            };
            defer category.deinit();
            self.data.category = try arenaAllocator.dupe(u8, category.value);
        }
        // isMenu
        blk: {
            const isMenu = item.get("ItemIsMenu", dbus.Boolean) catch {
                item.err.reset();
                self.data.ItemIsMenu = false;
                break :blk;
            };
            defer isMenu.deinit();
            self.data.ItemIsMenu = isMenu.value;
        }
        // menu
        blk: {
            const menu = item.get("Menu", dbus.ObjectPath) catch {
                item.err.reset();
                self.data.menu = "";
                break :blk;
            };
            defer menu.deinit();
            self.data.menu = try arenaAllocator.dupe(u8, menu.value);
        }
        // title, status 等可能会变化的值, 需要及时响应释放或者重新分配新的内存
        // title
        self.data.title = "";
        self.loadTitle();
        try item.connect("NewTitle", struct {
            fn f(_: dbus.Event, data: ?*anyopaque) void {
                const self_: *Self = @ptrCast(@alignCast(data.?));
                self_.loadTitle();
                self_.triggerListener();
            }
        }.f, self);
        // status
        self.data.status = "";
        self.loadStatus();
        try item.connect("NewStatus", struct {
            fn f(_: dbus.Event, data: ?*anyopaque) void {
                const self_: *Self = @ptrCast(@alignCast(data.?));
                self_.loadStatus();
                self_.triggerListener();
            }
        }.f, self);

        // attention
        self.data.attention.iconName = "";
        self.data.attention.movieName = "";
        self.data.attention.iconPixmap = &.{};
        self.loadAttention();
        try item.connect("NewAttentionIcon", struct {
            fn f(_: dbus.Event, data: ?*anyopaque) void {
                const self_: *Self = @ptrCast(@alignCast(data.?));
                self_.loadAttention();
                self_.triggerListener();
            }
        }.f, self);

        // icon
        self.data.icon.name = "";
        self.data.icon.themePath = "";
        self.data.icon.pixmap = &.{};
        self.loadIcon();
        try item.connect("NewIcon", struct {
            fn f(_: dbus.Event, data: ?*anyopaque) void {
                const self_: *Self = @ptrCast(@alignCast(data.?));
                self_.loadIcon();
                self_.triggerListener();
            }
        }.f, self);

        // overlay
        self.data.overlay.iconName = "";
        self.data.overlay.iconPixmap = &.{};
        self.loadOverlay();
        try item.connect("NewOverlayIcon", struct {
            fn f(_: dbus.Event, data: ?*anyopaque) void {
                const self_: *Self = @ptrCast(@alignCast(data.?));
                self_.loadOverlay();
                self_.triggerListener();
            }
        }.f, self);

        // tooltip
        self.data.tooltip.iconName = "";
        self.data.tooltip.title = "";
        self.data.tooltip.text = "";
        self.data.tooltip.iconPixmap = &.{};
        self.loadTooltip();
        try item.connect("NewToolTip", struct {
            fn f(_: dbus.Event, data: ?*anyopaque) void {
                const self_: *Self = @ptrCast(@alignCast(data.?));
                self_.loadTooltip();
                self_.triggerListener();
            }
        }.f, self);

        return self;
    }
    fn triggerListener(self: *Self) void {
        for (self._listeners.items) |listener| {
            listener.func(self, listener.data);
        }
    }
    pub fn addListener(self: *Self, func: *const fn (item: *Item, data: ?*anyopaque) void, data: ?*anyopaque) !void {
        try self._listeners.append(Listener{
            .func = func,
            .data = data,
        });
    }
    pub fn removeListener(self: *Self, func: *const fn (item: *Item, data: ?*anyopaque) void, data: ?*anyopaque) void {
        for (self._listeners.items, 0..) |listener, i| {
            if (listener.func == func and listener.data == data) {
                _ = self._listeners.swapRemove(i);
                return;
            }
        }
    }
    pub fn activate(self: *Self, x: i32, y: i32) void {
        self._object.callN(
            "Activate",
            .{ dbus.Int32, dbus.Int32 },
            .{ x, y },
        ) catch {
            self._object.err.reset();
        };
    }
    pub fn secondaryActivate(self: *Self, x: i32, y: i32) void {
        self._object.callN(
            "SecondaryActivate",
            .{ dbus.Int32, dbus.Int32 },
            .{ x, y },
        ) catch self._object.err.reset();
    }
    pub fn scrool(self: *Self, delta: i32, orientation: enum { vertical, horizontal }) void {
        self._object.callN(
            "Scroll",
            .{ dbus.Int32, dbus.String },
            .{ delta, @tagName(orientation) },
        ) catch self._object.err.reset();
    }
    pub fn contextMenu(self: *Self, x: i32, y: i32) void {
        self._object.callN(
            "ContextMenu",
            .{ dbus.Int32, dbus.Int32 },
            .{ x, y },
        ) catch self._object.err.reset();
    }
    pub fn provideXdgActivationToken(self: *Self, token: []const u8) void {
        self._object.callN(
            "ProvideXdgActivationToken",
            .{dbus.String},
            .{token},
        ) catch self._object.err.reset();
    }
    fn loadTitle(self: *Self) void {
        self._allocator.free(self.data.title);
        const title = self._object.get("Title", dbus.String) catch {
            self._object.err.reset();
            self.data.title = self._allocator.dupe(u8, "") catch unreachable;
            return;
        };
        defer title.deinit();
        self.data.title = self._allocator.dupe(u8, title.value) catch unreachable;
    }
    fn loadStatus(self: *Self) void {
        self._allocator.free(self.data.status);
        const status = self._object.get("Status", dbus.String) catch {
            self._object.err.reset();
            self.data.status = self._allocator.dupe(u8, "") catch unreachable;
            return;
        };
        defer status.deinit();
        self.data.status = self._allocator.dupe(u8, status.value) catch unreachable;
    }
    fn loadAttention(self: *Self) void {
        const item = self._object;
        const allocator = self._allocator;
        allocator.free(self.data.attention.iconName);
        allocator.free(self.data.attention.movieName);
        for (self.data.attention.iconPixmap) |*pixmap| {
            allocator.free(pixmap.webp);
        }
        allocator.free(self.data.attention.iconPixmap);
        self.data.attention.iconName = "";
        self.data.attention.movieName = "";
        self.data.attention.iconPixmap = &.{};
        blk: {
            const iconName = item.get("AttentionIconName", dbus.String) catch {
                item.err.reset();
                break :blk;
            };
            defer iconName.deinit();
            self.data.attention.iconName = allocator.dupe(u8, iconName.value) catch unreachable;
        }
        blk: {
            const movieName = item.get("AttentionMovieName", dbus.String) catch {
                item.err.reset();
                break :blk;
            };
            defer movieName.deinit();
            self.data.attention.movieName = allocator.dupe(u8, movieName.value) catch unreachable;
        }
        const iconPixmap = item.get("AttentionIconPixmap", DBusPixmap) catch {
            item.err.reset();
            return;
        };
        defer iconPixmap.deinit();
        var pixmaps = allocator.alloc(Pixmap, iconPixmap.value.len) catch unreachable;
        for (iconPixmap.value, 0..) |pixmap, i| {
            pixmaps[i].width = pixmap[0];
            pixmaps[i].height = pixmap[1];
            pixmaps[i].webp = pixmapToWebp(allocator, pixmap[0], pixmap[1], pixmap[2]) catch {
                continue;
            };
        }
        self.data.attention.iconPixmap = pixmaps;
    }
    fn loadIcon(self: *Self) void {
        const item = self._object;
        const allocator = self._allocator;
        allocator.free(self.data.icon.name);
        allocator.free(self.data.icon.themePath);
        for (self.data.icon.pixmap) |*pixmap| {
            allocator.free(pixmap.webp);
        }
        allocator.free(self.data.icon.pixmap);
        self.data.icon.name = "";
        self.data.icon.themePath = "";
        self.data.icon.pixmap = &.{};

        blk: {
            const iconName = item.get("IconName", dbus.String) catch {
                item.err.reset();
                break :blk;
            };
            defer iconName.deinit();
            self.data.icon.name = allocator.dupe(u8, iconName.value) catch unreachable;
        }
        blk: {
            const themePath = item.get("IconThemePath", dbus.String) catch {
                item.err.reset();
                break :blk;
            };
            defer themePath.deinit();
            self.data.icon.themePath = allocator.dupe(u8, themePath.value) catch unreachable;
        }
        const iconPixmap = item.get("IconPixmap", DBusPixmap) catch {
            item.err.reset();
            return;
        };
        defer iconPixmap.deinit();
        const pixmaps = allocator.alloc(Pixmap, iconPixmap.value.len) catch unreachable;
        for (pixmaps, 0..) |*pixmap, i| {
            pixmap.* = Pixmap{
                .width = iconPixmap.value[i][0],
                .height = iconPixmap.value[i][1],
                .webp = pixmapToWebp(
                    allocator,
                    iconPixmap.value[i][0],
                    iconPixmap.value[i][1],
                    iconPixmap.value[i][2],
                ) catch {
                    continue;
                },
            };
        }
        self.data.icon.pixmap = pixmaps;
    }
    fn loadOverlay(self: *Self) void {
        const item = self._object;
        const allocator = self._allocator;
        allocator.free(self.data.overlay.iconName);
        for (self.data.overlay.iconPixmap) |*pixmap| {
            allocator.free(pixmap.webp);
        }
        allocator.free(self.data.overlay.iconPixmap);
        self.data.overlay.iconName = "";
        self.data.overlay.iconPixmap = &.{};
        blk: {
            const iconName = item.get("OverlayIconName", dbus.String) catch {
                item.err.reset();
                break :blk;
            };
            defer iconName.deinit();
            self.data.overlay.iconName = allocator.dupe(u8, iconName.value) catch unreachable;
        }

        const iconPixmap = item.get("OverlayIconPixmap", DBusPixmap) catch {
            item.err.reset();
            return;
        };
        defer iconPixmap.deinit();
        var pixmaps = allocator.alloc(Pixmap, iconPixmap.value.len) catch unreachable;
        for (iconPixmap.value, 0..) |pixmap, i| {
            pixmaps[i].width = pixmap[0];
            pixmaps[i].height = pixmap[1];
            pixmaps[i].webp = pixmapToWebp(allocator, pixmap[0], pixmap[1], pixmap[2]) catch {
                continue;
            };
        }
        self.data.overlay.iconPixmap = pixmaps;
    }
    fn loadTooltip(self: *Self) void {
        const item = self._object;
        const allocator = self._allocator;
        self.data.tooltip.iconName = "";
        for (self.data.tooltip.iconPixmap) |*pixmap| {
            allocator.free(pixmap.webp);
        }
        allocator.free(self.data.tooltip.iconPixmap);
        allocator.free(self.data.tooltip.title);
        allocator.free(self.data.tooltip.text);
        self.data.tooltip.title = "";
        self.data.tooltip.text = "";
        self.data.tooltip.iconPixmap = &.{};

        const tooltip = item.get("ToolTip", dbus.Struct(.{
            dbus.String,
            DBusPixmap,
            dbus.String,
            dbus.String,
        })) catch {
            item.err.reset();
            return;
        };
        defer tooltip.deinit();
        self.data.tooltip.iconName = allocator.dupe(u8, tooltip.value[0]) catch unreachable;
        const pixmaps = allocator.alloc(Pixmap, tooltip.value[1].len) catch unreachable;
        for (pixmaps, 0..) |*pixmap, i| {
            pixmap.* = Pixmap{
                .width = tooltip.value[1][i][0],
                .height = tooltip.value[1][i][1],
                .webp = pixmapToWebp(allocator, tooltip.value[1][i][0], tooltip.value[1][i][1], tooltip.value[1][i][2]) catch continue,
            };
        }
        self.data.tooltip.iconPixmap = pixmaps;
        self.data.tooltip.title = allocator.dupe(u8, tooltip.value[2]) catch unreachable;
        self.data.tooltip.text = allocator.dupe(u8, tooltip.value[3]) catch unreachable;
    }
    pub fn deinit(self: *Self) void {
        self._object.deinit();
        const arena: *std.heap.ArenaAllocator = @ptrCast(@alignCast(self._arena.ptr));
        arena.deinit();
        const allocator = self._allocator;
        allocator.free(self.data.title);
        allocator.free(self.data.status);
        allocator.free(self.owner);
        self._listeners.deinit();
        // attention
        allocator.free(self.data.attention.iconName);
        allocator.free(self.data.attention.movieName);
        for (self.data.attention.iconPixmap) |*pixmap| {
            allocator.free(pixmap.webp);
        }
        allocator.free(self.data.attention.iconPixmap);
        // icon
        allocator.free(self.data.icon.name);
        allocator.free(self.data.icon.themePath);
        for (self.data.icon.pixmap) |*pixmap| {
            allocator.free(pixmap.webp);
        }
        allocator.free(self.data.icon.pixmap);
        // overlay
        allocator.free(self.data.overlay.iconName);
        for (self.data.overlay.iconPixmap) |*pixmap| {
            allocator.free(pixmap.webp);
        }
        allocator.free(self.data.overlay.iconPixmap);
        // tooltip
        allocator.free(self.data.tooltip.iconName);
        for (self.data.tooltip.iconPixmap) |*pixmap| {
            allocator.free(pixmap.webp);
        }
        allocator.free(self.data.tooltip.iconPixmap);
        allocator.free(self.data.tooltip.title);
        allocator.free(self.data.tooltip.text);

        allocator.destroy(arena);
        allocator.destroy(self);
    }
};

const std = @import("std");
