const dbus = @import("dbus");
const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const c = @cImport({
    @cInclude("webp/encode.h");
});
fn pixmapToWebp(
    allocator: Allocator,
    width: i32,
    height: i32,
    rowstride: i32,
    hasAlpha: bool,
    rgb: []const u8,
) ![]u8 {
    var output_ptr: [*c]u8 = undefined;
    var size: usize = 0;
    if (!hasAlpha) {
        size = c.WebPEncodeRGB(
            rgb.ptr,
            @intCast(width),
            @intCast(height),
            @intCast(rowstride),
            100.0,
            &output_ptr,
        );
    } else {
        size = c.WebPEncodeRGBA(
            rgb.ptr,
            @intCast(width),
            @intCast(height),
            @intCast(rowstride),
            100.0,
            &output_ptr,
        );
    }
    if (size == 0 or output_ptr == null) {
        return error.WebPEncodingFailed;
    }
    defer c.WebPFree(output_ptr);
    return try allocator.dupe(u8, output_ptr[0..size]);
}
pub const ImageData = struct {
    width: i32,
    height: i32,
    rowstride: i32,
    hasAlpha: bool,
    bitsPerSample: i32,
    channels: i32,
    webp: []const u8,
};
pub const Urgency = enum {
    low,
    normal,
    critical,
};

pub const Hint = union(enum) {
    actionIcons: bool,
    category: []const u8,
    desktopEntry: []const u8,
    imageData: ImageData,
    imagePath: []const u8,
    resident: bool,
    soundFile: []const u8,
    soundName: []const u8,
    suppressSound: bool,
    transient: bool,
    x: i32,
    y: i32,
    urgency: Urgency,
    senderPID: i64,
    fn deinit(hint: Hint, allocator: Allocator) void {
        switch (hint) {
            .category => |s| allocator.free(s),
            .desktopEntry => |s| allocator.free(s),
            .imagePath => |s| allocator.free(s),
            .soundFile => |s| allocator.free(s),
            .soundName => |s| allocator.free(s),
            .imageData => |data| allocator.free(data.webp),
            else => {},
        }
    }
};
pub const Notification = struct {
    id: u32,
    appName: []const u8,
    replacesId: u32,
    appIcon: []const u8,
    summary: []const u8,
    body: []const u8,
    actions: [][]const u8,
    hints: []Hint,
    expireTimeout: i32,
    timestamp: i64,
    fn deinit(n: Notification, allocator: Allocator) void {
        allocator.free(n.appIcon);
        allocator.free(n.appName);
        allocator.free(n.summary);
        allocator.free(n.body);
        for (n.actions) |action| allocator.free(action);
        allocator.free(n.actions);
        for (n.hints) |hint| hint.deinit(allocator);
        allocator.free(n.hints);
    }
};

pub const Notifd = struct {
    const Self = @This();
    const Reason = enum(u32) {
        expired = 1,
        dismissed = 2,
        closed = 3,
        unknown = 4,
    };
    emitter: dbus.Emitter,
    allocator: Allocator,
    id: u32,
    items: std.AutoHashMap(u32, Notification),
    service: *dbus.Service,
    mutex: std.Thread.Mutex = .{},
    listener: ?*anyopaque,
    onAdded: ?*const fn (listener: ?*anyopaque, id: u32) void,
    onRemoved: ?*const fn (listener: ?*anyopaque, id: u32) void,
    pub fn init(allocator: Allocator, bus: *dbus.Bus) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);
        self.items = std.AutoHashMap(u32, Notification).init(allocator);
        errdefer self.items.deinit();
        self.id = 0;
        self.listener = null;
        self.onAdded = null;
        self.onRemoved = null;
        self.allocator = allocator;
        self.service = bus.owner("org.freedesktop.Notifications", .DoNotQueue) catch |err| {
            bus.err.reset();
            return err;
        };
        return self;
    }
    pub fn deinit(self: *Self) void {
        var iter = self.items.iterator();
        while (iter.next()) |kv| kv.value_ptr.deinit(self.allocator);
        self.items.deinit();
        self.service.deinit();
        self.allocator.destroy(self);
    }

    pub fn publish(self: *Self) !void {
        self.service.publish(Notifd, "/org/freedesktop/Notifications", Interface, self, &self.emitter) catch {
            self.service.err.reset();
            return error.FailedToPublishNtificationsService;
        };
    }

    pub fn invokeAction(self: *Notifd, id: u32, action_key: []const u8) void {
        self.emitter.emit("ActionInvoked", .{ dbus.UInt32, dbus.String }, .{ id, action_key });
    }
    pub fn activationToken(self: *Notifd, id: u32, activation_token: []const u8) void {
        self.emitter.emit("ActivationToken", .{ dbus.UInt32, dbus.String }, .{ id, activation_token });
    }
    fn getCapabilities(_: *Self, _: []const u8, _: Allocator, _: *dbus.MessageIter, out: *dbus.MessageIter, _: *dbus.CallError) !void {
        try out.append(dbus.Array(dbus.String), &.{
            "action-icons",
            "actions",
            "body",
            "body-hyperlinks",
            "body-images",
            "body-markup",
            "icon-multi",
            "icon-static",
            "persistence",
            "sound",
        });
    }
    fn closeNotification_(self: *Self, id: u32, reason: Reason) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.items.get(id)) |n| {
            n.deinit(self.allocator);
            _ = self.items.remove(id);
            if (self.onRemoved) |f| f(self.listener, id);
            self.emitter.emit("NotificationClosed", .{ dbus.UInt32, dbus.UInt32 }, .{ id, @intFromEnum(reason) });
        }
    }
    pub fn dismiss(self: *Self, id: u32) void {
        self.closeNotification_(id, .dismissed);
    }
    fn closeNotificationDBus(self: *Self, _: []const u8, _: Allocator, in: *dbus.MessageIter, _: *dbus.MessageIter, _: *dbus.CallError) !void {
        const id = in.next(dbus.UInt32) orelse return error.InvalidArgs;
        if (id == 0) return error.InvalidArgs; // 0 is not a valid notification ID
        self.closeNotification_(id, .closed);
    }

    fn setupNotification(self: *Self, n: Notification) !void {
        if (n.replacesId != 0) {
            if (self.items.get(n.replacesId)) |old| {
                old.deinit(self.allocator);
                _ = self.items.remove(n.replacesId);
            }
        } else {
            try self.items.put(n.id, n);
        }
        if (self.onAdded) |f| f(self.listener, n.id);
    }
    fn notify(self: *Self, _: []const u8, _: Allocator, in: *dbus.MessageIter, out: *dbus.MessageIter, _: *dbus.CallError) !void {
        const app_name = in.next(dbus.String) orelse return error.InvalidArgs;
        const replaces_id = in.next(dbus.UInt32) orelse return error.InvalidArgs;
        const app_icon = in.next(dbus.String) orelse return error.InvalidArgs;
        const summary = in.next(dbus.String) orelse return error.InvalidArgs;
        const body = in.next(dbus.String) orelse return error.InvalidArgs;
        const actions = in.next(dbus.Array(dbus.String)) orelse return error.InvalidArgs;
        const hints = in.next(dbus.Dict(dbus.String, dbus.Variant)) orelse return error.InvalidArgs;
        const expire_timeout = in.next(dbus.Int32) orelse return error.InvalidArgs;
        const allocator = self.allocator;
        var n: Notification = undefined;
        n.replacesId = replaces_id;
        n.expireTimeout = expire_timeout;
        n.appIcon = try allocator.dupe(u8, app_icon);
        errdefer allocator.free(n.appIcon);
        n.appName = try allocator.dupe(u8, app_name);
        errdefer allocator.free(n.appName);
        n.summary = try allocator.dupe(u8, summary);
        errdefer allocator.free(n.summary);
        n.body = try allocator.dupe(u8, body);
        errdefer allocator.free(n.body);
        n.actions = try allocator.alloc([]const u8, actions.len);
        errdefer allocator.free(n.actions);
        errdefer for (n.actions) |action| allocator.free(action);
        for (n.actions, 0..) |*action, i| {
            action.* = try allocator.dupe(u8, actions[i]);
        }
        n.hints = try allocator.alloc(Hint, hints.len);
        errdefer allocator.free(n.hints);
        errdefer for (n.hints) |hint| hint.deinit(allocator);
        for (n.hints, 0..) |*hint, i| {
            const key = hints[i].key;
            const variant = hints[i].value;
            const eql = std.mem.eql;
            if (eql(u8, key, "action-icons")) {
                hint.* = Hint{ .actionIcons = try variant.get(dbus.Boolean) };
            } else if (eql(u8, key, "category")) {
                hint.* = Hint{ .category = try allocator.dupe(u8, try variant.get(dbus.String)) };
            } else if (eql(u8, key, "desktop-entry")) {
                hint.* = Hint{ .desktopEntry = try allocator.dupe(u8, try variant.get(dbus.String)) };
            } else if (eql(u8, key, "image-data")) {
                const data = try variant.get(dbus.Struct(.{
                    dbus.Int32, // width
                    dbus.Int32, // height
                    dbus.Int32, // rowstride
                    dbus.Boolean, // hasAlpha
                    dbus.Int32, // bitsPerSample
                    dbus.Int32, // channels
                    dbus.Array(dbus.Byte), // imageData
                }));
                const webp = try pixmapToWebp(allocator, data[0], data[1], data[2], data[3], data[6]);
                hint.* = Hint{ .imageData = ImageData{
                    .width = data[0],
                    .height = data[1],
                    .rowstride = data[2],
                    .hasAlpha = data[3],
                    .bitsPerSample = data[4],
                    .channels = data[5],
                    .webp = webp,
                } };
            } else if (eql(u8, key, "image-path")) {
                hint.* = Hint{ .imagePath = try allocator.dupe(u8, try variant.get(dbus.String)) };
            } else if (eql(u8, key, "resident")) {
                hint.* = Hint{ .resident = try variant.get(dbus.Boolean) };
            } else if (eql(u8, key, "sound-file")) {
                hint.* = Hint{ .soundFile = try allocator.dupe(u8, try variant.get(dbus.String)) };
            } else if (eql(u8, key, "sound-name")) {
                hint.* = Hint{ .soundName = try allocator.dupe(u8, try variant.get(dbus.String)) };
            } else if (eql(u8, key, "suppress-sound")) {
                hint.* = Hint{ .suppressSound = try variant.get(dbus.Boolean) };
            } else if (eql(u8, key, "transient")) {
                hint.* = Hint{ .transient = try variant.get(dbus.Boolean) };
            } else if (eql(u8, key, "x")) {
                hint.* = Hint{ .x = try variant.get(dbus.Int32) };
            } else if (eql(u8, key, "y")) {
                hint.* = Hint{ .y = try variant.get(dbus.Int32) };
            } else if (eql(u8, key, "urgency")) {
                const u = try variant.get(dbus.Byte);
                hint.* = Hint{ .urgency = @enumFromInt(u) };
            } else if (eql(u8, key, "sender-pid")) {
                hint.* = Hint{ .senderPID = try variant.get(dbus.Int64) };
            }
        }
        self.id += 1;
        const id = self.id;
        n.id = id;
        n.timestamp = @intCast(std.time.nanoTimestamp());
        try self.setupNotification(n);
        try out.append(dbus.UInt32, id);
    }
    fn getServerInformation(_: *Self, _: []const u8, _: Allocator, _: *dbus.MessageIter, out: *dbus.MessageIter, _: *dbus.CallError) !void {
        try out.append(dbus.String, "notifd");
        try out.append(dbus.String, "mika-shell");
        try out.append(dbus.String, "0.1");
        try out.append(dbus.String, "1.2");
    }
};
const Interface = dbus.Interface(Notifd){
    .name = "org.freedesktop.Notifications",
    .method = &.{
        .{
            .name = "CloseNotification",
            .func = Notifd.closeNotificationDBus,
            .args = &.{.{ .name = "id", .type = dbus.UInt32, .direction = .in }},
        },
        .{
            .name = "GetCapabilities",
            .func = Notifd.getCapabilities,
            .args = &.{.{ .name = "result", .type = dbus.Array(dbus.String), .direction = .out }},
        },
        .{
            .name = "GetServerInformation",
            .func = Notifd.getServerInformation,
            .args = &.{
                .{ .name = "name", .type = dbus.String, .direction = .out },
                .{ .name = "vendor", .type = dbus.String, .direction = .out },
                .{ .name = "version", .type = dbus.String, .direction = .out },
                .{ .name = "spec_version", .type = dbus.String, .direction = .out }, // 1.2
            },
        },
        .{
            .name = "Notify",
            .func = Notifd.notify,
            .args = &.{
                .{ .name = "app_name", .type = dbus.String, .direction = .in },
                .{ .name = "replaces_id", .type = dbus.UInt32, .direction = .in },
                .{ .name = "app_icon", .type = dbus.String, .direction = .in },
                .{ .name = "summary", .type = dbus.String, .direction = .in },
                .{ .name = "body", .type = dbus.String, .direction = .in },
                .{ .name = "actions", .type = dbus.Array(dbus.String), .direction = .in },
                .{ .name = "hints", .type = dbus.Dict(dbus.String, dbus.Variant), .direction = .in },
                .{ .name = "expire_timeout", .type = dbus.Int32, .direction = .in },
                .{ .name = "id", .type = dbus.UInt32, .direction = .out },
            },
        },
    },
    .signal = &.{
        dbus.Signal{
            .name = "ActionInvoked",
            .args = &.{
                .{ .name = "id", .type = dbus.UInt32 },
                .{ .name = "action_key", .type = dbus.String },
            },
        },
        dbus.Signal{
            .name = "ActivationToken",
            .args = &.{
                .{ .name = "id", .type = dbus.UInt32 },
                .{ .name = "activation_token", .type = dbus.String },
            },
        },
        dbus.Signal{
            .name = "NotificationClosed",
            .args = &.{
                .{ .name = "id", .type = dbus.UInt32 },
                .{ .name = "reason", .type = dbus.UInt32 },
            },
        },
    },
};
const glib = @import("glib");
test {
    const allocator = testing.allocator;
    const bus = try dbus.Bus.init(allocator, .Session);
    defer bus.deinit();
    var notifd = try Notifd.init(allocator, bus);
    defer notifd.deinit();
    try notifd.publish();
    const watch = try dbus.withGLibLoop(bus);
    defer watch.deinit();
    glib.timeoutMainLoop(5_000);
}
