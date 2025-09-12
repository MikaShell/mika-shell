const std = @import("std");
const modules = @import("root.zig");
const Args = modules.Args;
const Context = modules.Context;
const InitContext = modules.InitContext;
const Registry = modules.Registry;
const Allocator = std.mem.Allocator;
const tray = @import("../lib/tray.zig");
const dbus = @import("dbus");
const App = @import("../app.zig").App;
const Webview = @import("../app.zig").Webview;
const Events = @import("../events.zig").Events;
fn trayWatcherThread(flag: *std.atomic.Value(bool)) !void {
    defer flag.store(true, .release);
    const allocator = std.heap.page_allocator;
    const bus = try dbus.Bus.init(allocator, .Session);
    defer bus.deinit();
    const watcher = tray.Watcher.init(allocator, bus) catch return;
    defer watcher.deinit();
    watcher.publish() catch |err| {
        std.log.err("Failed to publish tray watcher: {any}", .{err});
        return;
    };
    flag.store(true, .release);
    while (true) {
        if (!bus.conn.readWrite(-1)) return;
        while (bus.conn.dispatch() != .Complete) {}
    }
}
pub const Tray = struct {
    const Self = @This();
    allocator: Allocator,
    app: *App,
    host: ?*tray.Host = null,
    bus: *dbus.Bus,
    isWatcherInitialized: bool = false,
    pub fn init(ctx: InitContext) !*Self {
        const allocator = ctx.allocator;
        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .app = ctx.app,
            .bus = ctx.sessionBus,
        };
        return self;
    }
    pub fn deinit(self: *Self, allocator: Allocator) void {
        if (self.host) |h| h.deinit();
        allocator.destroy(self);
    }
    pub fn register() Registry(Self) {
        return .{
            .exports = &.{
                .{ "getItem", getItem },
                .{ "getItems", getItems },
                .{ "activate", activate },
                .{ "secondaryActivate", secondaryActivate },
                .{ "scroll", scroll },
                .{ "provideXdgActivationToken", provideXdgActivationToken },
                .{ "getMenu", getMenu },
                .{ "activateMenu", activateMenu },
            },
            .events = &.{
                .tray_added,
                .tray_removed,
                .tray_changed,
            },
        };
    }
    pub fn eventStart(self: *Self) !void {
        const allocator = self.allocator;
        const bus = self.bus;
        if (!self.isWatcherInitialized) {
            self.isWatcherInitialized = true;
            var flag = std.atomic.Value(bool).init(false);
            (try std.Thread.spawn(.{}, trayWatcherThread, .{&flag})).detach();
            while (!flag.load(.acquire)) {
                try std.Thread.yield();
            }
        }

        if (self.host == null) {
            self.host = try tray.Host.init(allocator, bus);
            try self.host.?.addListener(onItemUpdated, self);
        }
    }
    fn setup(self: *Self, ctx: *Context) !void {
        const allocator = self.allocator;
        const bus = self.bus;
        if (self.host == null) {
            self.host = tray.Host.init(allocator, bus) catch |err| {
                return ctx.errors("failed to init tray host {t}", .{err});
            };
            try self.host.?.addListener(onItemUpdated, self);
        }
    }
    fn onItemUpdated(_: *tray.Host, state: tray.ItemState, service: []const u8, data: ?*anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(data));
        const event = switch (state) {
            .added => Events.tray_added,
            .removed => Events.tray_removed,
            .changed => Events.tray_changed,
        };
        self.app.emitEventUseSocket(event, service);
    }
    pub fn getItems(self: *Self, ctx: *Context) !void {
        try self.setup(ctx);
        const host = self.host.?;

        const items = try self.allocator.alloc(tray.Item.Data, host.items.items.len);
        defer self.allocator.free(items);
        for (items, 0..) |*it, i| {
            it.* = host.items.items[i].data;
        }
        ctx.commit(items);
    }
    pub fn getItem(self: *Self, ctx: *Context) !void {
        try self.setup(ctx);
        const host = self.host.?;
        const service = try ctx.args.string(0);
        for (host.items.items) |item| {
            if (std.mem.eql(u8, item.data.service, service)) {
                ctx.commit(item.data);
                return;
            }
        }
    }
    pub fn activate(self: *Self, ctx: *Context) !void {
        try self.setup(ctx);
        const service = try ctx.args.string(0);
        const x = try ctx.args.integer(1);
        const y = try ctx.args.integer(2);

        const host = self.host.?;
        for (host.items.items) |item| {
            if (std.mem.eql(u8, item.data.service, service)) {
                item.activate(@intCast(x), @intCast(y));
                return;
            }
        }
    }
    pub fn secondaryActivate(self: *Self, ctx: *Context) !void {
        try self.setup(ctx);
        const service = try ctx.args.string(0);
        const x = try ctx.args.integer(1);
        const y = try ctx.args.integer(2);

        const host = self.host.?;
        for (host.items.items) |item| {
            if (std.mem.eql(u8, item.data.service, service)) {
                item.secondaryActivate(@intCast(x), @intCast(y));
                return;
            }
        }
    }
    pub fn provideXdgActivationToken(self: *Self, ctx: *Context) !void {
        try self.setup(ctx);
        const service = try ctx.args.string(0);
        const token = try ctx.args.string(1);

        const host = self.host.?;
        for (host.items.items) |item| {
            if (std.mem.eql(u8, item.data.service, service)) {
                item.provideXdgActivationToken(token);
                return;
            }
        }
    }
    pub fn scroll(self: *Self, ctx: *Context) !void {
        try self.setup(ctx);
        const service = try ctx.args.string(0);
        const delta = try ctx.args.integer(1);
        const orientationStr = try ctx.args.string(2);
        var orientation: u8 = undefined;
        if (std.mem.eql(u8, orientationStr, "vertical")) {
            orientation = 0;
        } else if (std.mem.eql(u8, orientationStr, "horizontal")) {
            orientation = 1;
        } else {
            return ctx.errors("invalid orientation {s}, only 'horizontal' or'vertical' is allowed", .{orientationStr});
        }
        const host = self.host.?;
        for (host.items.items) |item| {
            if (std.mem.eql(u8, item.data.service, service)) {
                item.scrool(@intCast(delta), @enumFromInt(orientation));
                return;
            }
        }
    }
    pub fn getMenu(self: *Self, ctx: *Context) !void {
        try self.setup(ctx);
        const service = try ctx.args.string(0);

        const host = self.host.?;
        for (host.items.items) |item| {
            if (std.mem.eql(u8, item.data.service, service)) {
                const menu = try tray.Menu.new(self.allocator, self.bus, item.owner, item.data.menu);
                defer menu.deinit(self.allocator);
                ctx.commit(menu);
                return;
            }
        }
        return ctx.errors("item service not found: {s}", .{service});
    }
    pub fn activateMenu(self: *Self, ctx: *Context) !void {
        try self.setup(ctx);
        const service = try ctx.args.string(0);
        const id = try ctx.args.integer(1);

        const host = self.host.?;
        for (host.items.items) |item| {
            if (std.mem.eql(u8, item.data.service, service)) {
                try tray.Menu.activate(self.allocator, self.bus, item.owner, item.data.menu, @intCast(id));
                return;
            }
        }
    }
};
