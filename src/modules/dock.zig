const std = @import("std");
const modules = @import("modules.zig");
const Args = modules.Args;
const Result = modules.Result;
const Context = modules.Context;
const Registry = modules.Registry;
const Allocator = std.mem.Allocator;
const App = @import("../app.zig").App;
const ForeignToplevelManager = @import("wayland").ForeignToplevelManager;
pub const Dock = struct {
    const Self = @This();
    allocator: Allocator,
    app: *App,
    manager: ?*ForeignToplevelManager.Manager,
    pub fn init(ctx: Context) !*Self {
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
                .dock_changed,
                .dock_closed,
                .dock_enter,
                .dock_leave,
            },
        };
    }
    fn onChanged(self: *Self, client: ForeignToplevelManager.Toplevel) void {
        self.app.emitEvent(.dock_changed, client);
    }
    fn onClosed(self: *Self, id: u32) void {
        self.app.emitEvent(.dock_closed, id);
    }
    fn onEnter(self: *Self, id: u32) void {
        self.app.emitEvent(.dock_enter, id);
    }
    fn onLeave(self: *Self, id: u32) void {
        self.app.emitEvent(.dock_leave, id);
    }
    pub fn list(self: *Self, _: Args, result: *Result) !void {
        try self.setup();
        const manager = self.manager.?;
        const items = try manager.list(self.allocator);
        defer self.allocator.free(items);
        result.commit(items);
    }
    pub fn activate(self: *Self, args: Args, _: *Result) !void {
        const id = try args.uInteger(1);
        try self.setup();
        const manager = self.manager.?;
        manager.activate(@intCast(id));
    }
    pub fn close(self: *Self, args: Args, _: *Result) !void {
        const id = try args.uInteger(1);
        try self.setup();
        const manager = self.manager.?;
        manager.close(@intCast(id));
    }
    pub fn setMaximized(self: *Self, args: Args, _: *Result) !void {
        const id = try args.uInteger(1);
        const maximized = try args.bool(2);
        try self.setup();
        const manager = self.manager.?;
        manager.setMaximized(@intCast(id), maximized);
    }
    pub fn setMinimized(self: *Self, args: Args, _: *Result) !void {
        const id = try args.uInteger(1);
        const minimized = try args.bool(2);
        try self.setup();
        const manager = self.manager.?;
        manager.setMinimized(@intCast(id), minimized);
    }
    pub fn setFullscreen(self: *Self, args: Args, _: *Result) !void {
        const id = try args.uInteger(1);
        const fullscreen = try args.bool(2);
        try self.setup();
        const manager = self.manager.?;
        manager.setFullscreen(@intCast(id), fullscreen);
    }
};
