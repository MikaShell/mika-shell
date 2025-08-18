const std = @import("std");
const modules = @import("modules.zig");
const Args = modules.Args;
const Result = modules.Result;
const Context = modules.Context;
const Registry = modules.Registry;
const Allocator = std.mem.Allocator;
const tray = @import("../lib/tray.zig");
const dbus = @import("dbus");
const App = @import("../app.zig").App;
const Webview = @import("../app.zig").Webview;
const Events = @import("../events.zig").Events;
fn trayWatcherThread(flag: *std.atomic.Value(bool)) !void {
    defer flag.store(false, .release);
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
    pub fn init(ctx: Context) !*Self {
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
    fn setup(self: *Self, result: *Result) !void {
        const allocator = self.allocator;
        const bus = self.bus;
        if (self.host == null) {
            self.host = tray.Host.init(allocator, bus) catch |err| {
                return result.errors("failed to init tray host {s}", .{@errorName(err)});
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
        self.app.emitEvent(event, service);
    }
    pub fn getItems(self: *Self, _: Args, result: *Result) !void {
        try self.setup(result);
        const host = self.host.?;

        const items = try self.allocator.alloc(tray.Item.Data, host.items.items.len);
        for (items, 0..) |*it, i| {
            it.* = host.items.items[i].data;
        }
        result.commit(items);
    }
    pub fn getItem(self: *Self, args: Args, result: *Result) !void {
        try self.setup(result);
        const host = self.host.?;
        const service = try args.string(1);
        for (host.items.items) |item| {
            if (std.mem.eql(u8, item.data.service, service)) {
                result.commit(item.data);
                return;
            }
        }
    }
    pub fn activate(self: *Self, args: Args, result: *Result) !void {
        try self.setup(result);
        const service = try args.string(1);
        const x = try args.integer(2);
        const y = try args.integer(3);

        const host = self.host.?;
        for (host.items.items) |item| {
            if (std.mem.eql(u8, item.data.service, service)) {
                item.activate(@intCast(x), @intCast(y));
                return;
            }
        }
    }
    pub fn secondaryActivate(self: *Self, args: Args, result: *Result) !void {
        try self.setup(result);
        const service = try args.string(1);
        const x = try args.integer(2);
        const y = try args.integer(3);

        const host = self.host.?;
        for (host.items.items) |item| {
            if (std.mem.eql(u8, item.data.service, service)) {
                item.secondaryActivate(@intCast(x), @intCast(y));
                return;
            }
        }
    }
    pub fn provideXdgActivationToken(self: *Self, args: Args, result: *Result) !void {
        try self.setup(result);
        const service = try args.string(1);
        const token = try args.string(2);

        const host = self.host.?;
        for (host.items.items) |item| {
            if (std.mem.eql(u8, item.data.service, service)) {
                item.provideXdgActivationToken(token);
                return;
            }
        }
    }
    pub fn scroll(self: *Self, args: Args, result: *Result) !void {
        try self.setup(result);
        const service = try args.string(1);
        const delta = try args.integer(2);
        const orientationStr = try args.string(3);
        var orientation: u8 = undefined;
        if (std.mem.eql(u8, orientationStr, "vertical")) {
            orientation = 0;
        } else if (std.mem.eql(u8, orientationStr, "horizontal")) {
            orientation = 1;
        } else {
            return result.errors("invalid orientation {s}, only 'horizontal' or'vertical' is allowed", .{orientationStr});
        }
        const host = self.host.?;
        for (host.items.items) |item| {
            if (std.mem.eql(u8, item.data.service, service)) {
                item.scrool(@intCast(delta), @enumFromInt(orientation));
                return;
            }
        }
    }
    pub fn getMenu(self: *Self, args: Args, result: *Result) !void {
        try self.setup(result);
        const service = try args.string(1);

        const host = self.host.?;
        for (host.items.items) |item| {
            if (std.mem.eql(u8, item.data.service, service)) {
                const menu = try tray.Menu.new(self.allocator, self.bus, item.owner, item.data.menu);
                defer menu.deinit(self.allocator);
                result.commit(menu);
                return;
            }
        }
        return result.errors("item service not found: {s}", .{service});
    }
    pub fn activateMenu(self: *Self, args: Args, result: *Result) !void {
        try self.setup(result);
        const service = try args.string(1);
        const id = try args.integer(2);

        const host = self.host.?;
        for (host.items.items) |item| {
            if (std.mem.eql(u8, item.data.service, service)) {
                try tray.Menu.activate(self.allocator, self.bus, item.owner, item.data.menu, @intCast(id));
                return;
            }
        }
    }
};
