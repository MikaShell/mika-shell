const std = @import("std");
const modules = @import("root.zig");
const Args = modules.Args;
const Context = modules.Context;
const InitContext = modules.InitContext;
const Registry = modules.Registry;
const Allocator = std.mem.Allocator;
const App = @import("../app.zig").App;
const ForeignToplevelManager = @import("wayland").ForeignToplevel;
pub const Dock = struct {
    const Self = @This();
    allocator: Allocator,
    app: *App,
    manager: ?*ForeignToplevelManager.Manager,
    pub fn init(ctx: InitContext) !*Self {
        const self = try ctx.allocator.create(Self);
        const allocator = ctx.allocator;
        self.allocator = allocator;
        self.app = ctx.app;
        self.manager = null;
        return self;
    }
    fn setup(self: *Self) !void {
        if (self.manager == null) {
            self.manager = try ForeignToplevelManager.Manager.init(self.allocator, .{
                .userdata = @ptrCast(self),
                .changed = @ptrCast(&onChanged),
                .closed = @ptrCast(&onClosed),
                .enter = @ptrCast(&onEnter),
                .leave = @ptrCast(&onLeave),
            });
        }
    }
    pub fn eventStart(self: *Self) !void {
        try self.setup();
    }
    pub fn eventStop(self: *Self) !void {
        if (self.manager) |m| {
            m.deinit();
            self.manager = null;
        }
    }
    pub fn deinit(self: *Self, allocator: Allocator) void {
        if (self.manager) |m| m.deinit();
        allocator.destroy(self);
    }
    pub fn register() Registry(Self) {
        return .{
            .exports = &.{
                .{ "list", list },
                .{ "activate", activate },
                .{ "close", close },
                .{ "maximized", setMaximized },
                .{ "minimized", setMinimized },
                .{ "fullscreen", setFullscreen },
            },
            .events = &.{
                .@"dock.changed",
                .@"dock.closed",
                .@"dock.enter",
                .@"dock.leave",
            },
        };
    }
    fn onChanged(self: *Self, client: ForeignToplevelManager.Toplevel) void {
        self.app.emitEventUseSocket(.@"dock.changed", client);
    }
    fn onClosed(self: *Self, id: u32) void {
        self.app.emitEventUseSocket(.@"dock.closed", id);
    }
    fn onEnter(self: *Self, id: u32) void {
        self.app.emitEventUseSocket(.@"dock.enter", id);
    }
    fn onLeave(self: *Self, id: u32) void {
        self.app.emitEventUseSocket(.@"dock.leave", id);
    }
    pub fn list(self: *Self, ctx: *Context) !void {
        try self.setup();
        const manager = self.manager.?;
        const items = try manager.list(self.allocator);
        defer self.allocator.free(items);
        ctx.commit(items);
    }
    pub fn activate(self: *Self, ctx: *Context) !void {
        const id = try ctx.args.uInteger(0);
        try self.setup();
        const manager = self.manager.?;
        try manager.activate(@intCast(id));
    }
    pub fn close(self: *Self, ctx: *Context) !void {
        const id = try ctx.args.uInteger(0);
        try self.setup();
        const manager = self.manager.?;
        try manager.close(@intCast(id));
    }
    pub fn setMaximized(self: *Self, ctx: *Context) !void {
        const id = try ctx.args.uInteger(0);
        const maximized = try ctx.args.bool(1);
        try self.setup();
        const manager = self.manager.?;
        try manager.setMaximized(@intCast(id), maximized);
    }
    pub fn setMinimized(self: *Self, ctx: *Context) !void {
        const id = try ctx.args.uInteger(0);
        const minimized = try ctx.args.bool(1);
        try self.setup();
        const manager = self.manager.?;
        try manager.setMinimized(@intCast(id), minimized);
    }
    pub fn setFullscreen(self: *Self, ctx: *Context) !void {
        const id = try ctx.args.uInteger(0);
        const fullscreen = try ctx.args.bool(1);
        try self.setup();
        const manager = self.manager.?;
        try manager.setFullscreen(@intCast(id), fullscreen);
    }
};
