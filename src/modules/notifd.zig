const std = @import("std");
const Allocator = std.mem.Allocator;
const modules = @import("modules.zig");
const Args = modules.Args;
const Result = modules.Result;
const notification = @import("../lib/notifd.zig");
const dbus = @import("dbus");
const App = @import("../app.zig").App;
const Webview = @import("../app.zig").Webview;
const Events = @import("../events.zig").Notifd;
pub const Notifd = struct {
    const Self = @This();
    app: *App,
    allocator: Allocator,
    bus: *dbus.Bus,
    subscriber: std.ArrayList(u64),
    notifd: ?*notification.Notifd,
    pub fn init(allocator: Allocator, app: *App, bus: *dbus.Bus) !*Self {
        const self = try allocator.create(Self);
        self.* = Self{
            .app = app,
            .allocator = allocator,
            .bus = bus,
            .subscriber = std.ArrayList(u64).init(allocator),
            .notifd = null,
        };
        return self;
    }
    pub fn deinit(self: *Self) void {
        if (self.notifd) |notifd| notifd.deinit();
        self.subscriber.deinit();
        self.allocator.destroy(self);
    }
    fn onNotificationAdded(self: *Self, id: u32) void {
        const app = self.app;
        var i: usize = self.subscriber.items.len;
        while (i > 0) {
            i -= 1;
            const wid = self.subscriber.items[i];
            const webview = app.getWebview(wid) catch {
                _ = self.subscriber.swapRemove(i);
                continue;
            };
            webview.emitEvent(Events.added, id);
        }
    }
    fn onNotificationRemoved(self: *Self, id: u32) void {
        const app = self.app;
        var i: usize = self.subscriber.items.len;
        while (i > 0) {
            i -= 1;
            const wid = self.subscriber.items[i];
            const webview = app.getWebview(wid) catch {
                _ = self.subscriber.swapRemove(i);
                continue;
            };
            webview.emitEvent(Events.removed, id);
        }
    }
    fn setup(self: *Self) !void {
        if (self.notifd == null) {
            const notifd = try notification.Notifd.init(self.allocator, self.bus);
            errdefer notifd.deinit();
            notifd.listener = @ptrCast(self);
            notifd.onAdded = @ptrCast(&Self.onNotificationAdded);
            notifd.onRemoved = @ptrCast(&Self.onNotificationRemoved);
            try notifd.publish();
            self.notifd = notifd;
        }
    }
    pub fn subscribe(self: *Self, args: Args, _: *Result) !void {
        const id = args.uInteger(0) catch unreachable;
        try self.setup();
        for (self.subscriber.items) |id_| {
            if (id == id_) {
                return;
            }
        }
        try self.subscriber.append(id);
    }
    pub fn unsubscribe(self: *Self, args: Args, _: *Result) !void {
        const id = args.uInteger(0) catch unreachable;
        try self.setup();
        for (self.subscriber.items, 0..) |id_, i| {
            if (id == id_) {
                _ = self.subscriber.swapRemove(i);
                return;
            }
        }
    }
    pub fn get(self: *Self, args: Args, result: *Result) !void {
        const id = try args.uInteger(1);
        try self.setup();
        const notifd = self.notifd.?;
        if (notifd.items.get(@intCast(id))) |n| {
            try result.commit(n);
        } else {
            return error.NotificationNotFound;
        }
    }
    pub fn getAll(self: *Self, _: Args, result: *Result) !void {
        try self.setup();
        const notifd = self.notifd.?;
        var items = std.ArrayList(notification.Notification).init(self.allocator);
        defer items.deinit();
        var iter = notifd.items.iterator();
        while (iter.next()) |kv| try items.append(kv.value_ptr.*);
        try result.commit(items.items);
    }
    pub fn activate(self: *Self, args: Args, _: *Result) !void {
        try self.setup();
        const id = try args.uInteger(1);
        const action = try args.string(2);
        const notifd = self.notifd.?;
        notifd.invokeAction(@intCast(id), action);
    }
    pub fn dismiss(self: *Self, args: Args, _: *Result) !void {
        const id = try args.uInteger(1);
        try self.setup();
        const notifd = self.notifd.?;
        notifd.dismiss(@intCast(id));
    }
};
