const std = @import("std");
const modules = @import("root.zig");
const dbus = @import("dbus");
const Args = modules.Args;
const InitContext = modules.InitContext;
const Context = modules.Context;
const Registry = modules.Registry;
const Allocator = std.mem.Allocator;
const App = @import("../app.zig").App;
const Webview = @import("../app.zig").Webview;
const events = @import("../events.zig");
const polkit = @import("../lib/polkit.zig");
pub const PolkitAgent = struct {
    const Self = @This();
    gpa: Allocator,
    app: *App,
    bus: *dbus.Bus,
    agent: ?*polkit.Agent,

    pub fn init(ctx: InitContext) !*Self {
        const self = try ctx.allocator.create(Self);
        errdefer ctx.allocator.destroy(self);
        const allocator = ctx.allocator;
        self.gpa = allocator;
        self.app = ctx.app;
        self.agent = null;
        self.bus = ctx.systemBus;
        return self;
    }
    pub fn deinit(self: *Self, allocator: Allocator) void {
        if (self.agent) |agent| agent.deinit();
        allocator.destroy(self);
    }
    pub fn eventStart(self: *Self) !void {
        self.agent = try polkit.Agent.init(Self, self.gpa, self.bus, .{
            .userdata = self,
            .onBeginAuthentication = onBeginAuthentication,
            .onCancelAuthentication = onCancelAuthentication,
        });
    }
    pub fn eventStop(self: *Self) !void {
        self.agent.?.deinit();
    }
    pub fn register() Registry(Self) {
        return .{
            .exports = &.{
                .{ "auth", auth },
                .{ "cancel", cancel },
            },
            .events = &.{
                .@"polkitAgent.begin",
                .@"polkitAgent.cancel",
            },
        };
    }
    fn onBeginAuthentication(self: *Self, ctx: polkit.Agent.Context) void {
        self.app.emitter.emit(.@"polkitAgent.begin", ctx);
    }
    fn onCancelAuthentication(self: *Self, cookie: []const u8) void {
        self.app.emitter.emit(.@"polkitAgent.cancel", cookie);
    }
    fn auth(self: *Self, ctx: *Context) !void {
        if (self.agent == null) {
            return error.AgentNotInit;
        }
        const cookie = try ctx.args.string(0);
        const username = try ctx.args.string(1);
        const password = try ctx.args.string(2);
        try self.agent.?.auth(modules.Async, self.gpa, cookie, username, password, authCallback, ctx.async());
    }
    fn authCallback(async: modules.Async, ok: bool, err: ?[]const u8) void {
        async.commit(.{
            .ok = ok,
            .err = err,
        });
    }
    fn cancel(self: *Self, ctx: *Context) !void {
        if (self.agent == null) {
            return error.AgentNotInit;
        }
        const cookie = try ctx.args.string(0);
        try self.agent.?.cancel(cookie);
    }
};
