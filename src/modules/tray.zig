const std = @import("std");
const Allocator = std.mem.Allocator;
const modules = @import("modules.zig");
const Args = modules.Args;
const Result = modules.Result;
const tray = @import("../lib/tray.zig");
const dbus = @import("dbus");
const App = @import("../app.zig").App;
const Webview = @import("../app.zig").Webview;
const Events = @import("../events.zig").Tray;
fn trayWatcherThread() !void {
    const allocator = std.heap.page_allocator;
    const bus = try dbus.Bus.init(allocator, .Session);
    defer bus.deinit();
    const watcher = tray.Watcher.init(allocator, bus) catch return;
    defer watcher.deinit();
    watcher.publish() catch @panic("failed to publish tray watcher");

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
    subscriber: std.ArrayList(u64),
    pub fn init(allocator: Allocator, app: *App, bus: *dbus.Bus) !*Self {
        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .app = app,
            .bus = bus,
            .subscriber = std.ArrayList(u64).init(allocator),
        };
        // TODO: 这个线程需要关闭吗?
        _ = try std.Thread.spawn(.{}, trayWatcherThread, .{});
        return self;
    }
    fn setup(self: *Self) !void {
        const allocator = self.allocator;
        const bus = self.bus;
        if (self.host == null) {
            self.host = tray.Host.init(allocator, bus) catch {
                return error.FailedToInitTrayHost;
            };
            try self.host.?.addListener(onItemUpdated, self);
        }
    }
    pub fn deinit(self: *Self) void {
        self.subscriber.deinit();
        if (self.host) |h| h.deinit();
        self.allocator.destroy(self);
    }
    fn onItemUpdated(_: *tray.Host, state: tray.ItemState, service: []const u8, data: ?*anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(data));
        const app = self.app;
        var event: []const u8 = undefined;
        switch (state) {
            .added => event = Events.added,
            .removed => event = Events.removed,
            .changed => event = Events.changed,
        }
        var i: usize = self.subscriber.items.len;
        while (i > 0) {
            i -= 1;
            const id = self.subscriber.items[i];
            const webview = app.getWebview(id) catch {
                _ = self.subscriber.swapRemove(i);
                continue;
            };
            webview.emitEvent(event, service);
        }
    }
    pub fn subscribe(self: *Self, args: Args, _: *Result) !void {
        const id = args.uInteger(0) catch unreachable;
        blk: {
            for (self.subscriber.items) |id_| {
                if (id == id_) {
                    break :blk;
                }
            }
            try self.subscriber.append(id);
        }
        try self.setup();
        const webview = self.app.getWebview(id) catch unreachable;
        const host = self.host.?;
        for (host.items.items) |item| {
            webview.emitEvent(Events.added, item.data.service);
        }
    }
    pub fn unsubscribe(self: *Self, args: Args, _: *Result) !void {
        const id = args.uInteger(0) catch unreachable;
        for (self.subscriber.items, 0..) |id_, i| {
            if (id == id_) {
                _ = self.subscriber.swapRemove(i);
                return;
            }
        }
    }
    pub fn getItems(self: *Self, _: Args, result: *Result) !void {
        try self.setup();
        const host = self.host.?;

        const items = try self.allocator.alloc(tray.Item.Data, host.items.items.len);
        for (items, 0..) |*it, i| {
            it.* = host.items.items[i].data;
        }
        try result.commit(items);
    }
    pub fn getItem(self: *Self, args: Args, result: *Result) !void {
        try self.setup();
        const host = self.host.?;
        const service = try args.string(1);
        for (host.items.items) |item| {
            if (std.mem.eql(u8, item.data.service, service)) {
                try result.commit(item.data);
                return;
            }
        }
    }
    pub fn activate(self: *Self, args: Args, _: *Result) !void {
        const service = try args.string(1);
        const x = try args.integer(2);
        const y = try args.integer(3);
        if (self.host == null) {
            return error.TrayHostNotInitlized;
        }
        const host = self.host.?;
        for (host.items.items) |item| {
            if (std.mem.eql(u8, item.data.service, service)) {
                item.activate(@intCast(x), @intCast(y));
                return;
            }
        }
    }
    pub fn secondaryActivate(self: *Self, args: Args, _: *Result) !void {
        const service = try args.string(1);
        const x = try args.integer(2);
        const y = try args.integer(3);
        if (self.host == null) {
            return error.TrayHostNotInitlized;
        }
        const host = self.host.?;
        for (host.items.items) |item| {
            if (std.mem.eql(u8, item.data.service, service)) {
                item.secondaryActivate(@intCast(x), @intCast(y));
                return;
            }
        }
    }
    pub fn provideXdgActivationToken(self: *Self, args: Args, _: *Result) !void {
        const service = try args.string(1);
        const token = try args.string(2);
        if (self.host == null) {
            return error.TrayHostNotInitlized;
        }
        const host = self.host.?;
        for (host.items.items) |item| {
            if (std.mem.eql(u8, item.data.service, service)) {
                item.provideXdgActivationToken(token);
                return;
            }
        }
    }
    pub fn scroll(self: *Self, args: Args, _: *Result) !void {
        const service = try args.string(1);
        const delta = try args.integer(2);
        const orientationStr = try args.string(3);
        if (self.host == null) {
            return error.TrayHostNotInitlized;
        }
        var orientation: u8 = undefined;
        if (std.mem.eql(u8, orientationStr, "vertical")) {
            orientation = 0;
        } else if (std.mem.eql(u8, orientationStr, "horizontal")) {
            orientation = 1;
        } else {
            return error.InvalidOrientation;
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
        const service = try args.string(1);
        if (self.host == null) {
            return error.TrayHostNotInitlized;
        }
        const host = self.host.?;
        for (host.items.items) |item| {
            if (std.mem.eql(u8, item.data.service, service)) {
                const menu = try tray.Menu.new(self.allocator, self.bus, item.owner, item.data.menu);
                defer menu.deinit(self.allocator);
                try result.commit(menu);
                return;
            }
        }
    }
    pub fn activateMenu(self: *Self, args: Args, _: *Result) !void {
        const service = try args.string(1);
        const id = try args.integer(2);
        if (self.host == null) {
            return error.TrayHostNotInitlized;
        }
        const host = self.host.?;
        for (host.items.items) |item| {
            if (std.mem.eql(u8, item.data.service, service)) {
                try tray.Menu.activate(self.allocator, self.bus, item.owner, item.data.menu, @intCast(id));
                return;
            }
        }
    }
};
