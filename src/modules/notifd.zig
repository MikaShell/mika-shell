const std = @import("std");
const modules = @import("root.zig");
const Args = modules.Args;
const Context = modules.Context;
const InitContext = modules.InitContext;
const Registry = modules.Registry;
const Allocator = std.mem.Allocator;
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
    notifd: ?*notification.Notifd,
    dontDisturb: bool = false,

    pub fn init(ctx: InitContext) !*Self {
        const self = try ctx.allocator.create(Self);
        self.* = Self{
            .app = ctx.app,
            .allocator = ctx.allocator,
            .bus = ctx.sessionBus,
            .dontDisturb = false,
            .notifd = null,
        };
        return self;
    }
    pub fn deinit(self: *Self, allocator: Allocator) void {
        if (self.notifd) |notifd| notifd.deinit();
        allocator.destroy(self);
    }
    pub fn register() Registry(Self) {
        return .{
            .exports = &.{
                .{ "get", get },
                .{ "dismiss", dismiss },
                .{ "activate", activate },
                .{ "getAll", getAll },
                .{ "setDontDisturb", setDontDisturb },
            },
            .events = &.{
                .notifd_added,
                .notifd_removed,
            },
        };
    }

    fn onNotificationAdded(self: *Self, id: u32) void {
        const app = self.app;
        app.emitEvent(.notifd_added, id);
    }
    fn onNotificationRemoved(self: *Self, id: u32) void {
        const app = self.app;
        app.emitEvent(.notifd_removed, id);
    }
    fn initNotifd(self: *Self) !void {
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
    pub fn eventStart(self: *Self) !void {
        self.initNotifd() catch |err| {
            if (err == error.NameExists) {
                return error.HasAnotherNotifdServiceRunning;
            }
            return error.FailedToInitNotifd;
        };
    }
    fn setup(self: *Self, ctx: *Context) !void {
        self.initNotifd() catch |err| {
            if (err == error.NameExists) {
                ctx.errors("Another notification service is running, cannot initialize Notifd module", .{});
                return error.HasAnotherNotifdServiceRunning;
            }
            ctx.errors("Failed to initialize notifd: {s}", .{@errorName(err)});
            return error.FailedToInitNotifd;
        };
    }
    pub fn setDontDisturb(self: *Self, ctx: *Context) !void {
        const enable = try ctx.args.bool(0);
        self.dontDisturb = enable;
    }
    pub fn get(self: *Self, ctx: *Context) !void {
        const id = try ctx.args.uInteger(0);
        try self.setup(ctx);
        const notifd = self.notifd.?;
        if (notifd.items.get(@intCast(id))) |n| {
            ctx.commit(n);
        } else {
            return error.NotificationNotFound;
        }
    }
    pub fn getAll(self: *Self, ctx: *Context) !void {
        try self.setup(ctx);
        const notifd = self.notifd.?;
        var items = std.ArrayList(notification.Notification).init(self.allocator);
        defer items.deinit();
        var iter = notifd.items.iterator();
        while (iter.next()) |kv| try items.append(kv.value_ptr.*);
        ctx.commit(items.items);
    }
    pub fn activate(self: *Self, ctx: *Context) !void {
        try self.setup(ctx);
        const id = try ctx.args.uInteger(0);
        const action = try ctx.args.string(1);
        const notifd = self.notifd.?;
        notifd.invokeAction(@intCast(id), action);
    }
    pub fn dismiss(self: *Self, ctx: *Context) !void {
        const id = try ctx.args.uInteger(0);
        try self.setup(ctx);
        const notifd = self.notifd.?;
        notifd.dismiss(@intCast(id));
    }
};
