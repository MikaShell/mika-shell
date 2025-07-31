const std = @import("std");
const modules = @import("modules.zig");
const Args = modules.Args;
const Result = modules.Result;
const Context = modules.Context;
const Registry = modules.Registry;
const Allocator = std.mem.Allocator;
const App = @import("../app.zig").App;
const dock = @import("../lib/dock.zig");
pub const Dock = struct {
    const Self = @This();
    allocator: Allocator,
    app: *App,
    dock: *dock.Dock,
    pub fn init(ctx: Context) !*Self {
        const self = try ctx.allocator.create(Self);
        const allocator = ctx.allocator;
        self.allocator = allocator;
        self.app = ctx.app;
        const dock_ = try dock.Dock.init(self.allocator, self);
        dock_.onAdded = @ptrCast(&onAdded);
        dock_.onChanged = @ptrCast(&onChanged);
        dock_.onClosed = @ptrCast(&onClosed);
        dock_.onEnter = @ptrCast(&onEnter);
        dock_.onLeave = @ptrCast(&onLeave);
        dock_.onActivated = @ptrCast(&onActivated);
        self.dock = dock_;
        return self;
    }
    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.dock.deinit();
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
                .dock_added,
                .dock_changed,
                .dock_closed,
                .dock_enter,
                .dock_leave,
                .dock_activated,
            },
        };
    }
    fn onAdded(self: *Self, item: dock.Item) void {
        self.app.emitEvent(.dock_added, item);
    }
    fn onChanged(self: *Self, item: dock.Item) void {
        self.app.emitEvent(.dock_changed, item);
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
    fn onActivated(self: *Self, id: u32) void {
        self.app.emitEvent(.dock_activated, id);
    }
    pub fn list(self: *Self, _: Args, result: *Result) !void {
        const items = try self.dock.list(self.allocator);
        defer self.allocator.free(items);
        defer for (items) |item| item.deinit(self.allocator);
        result.commit(items);
    }
    pub fn activate(_: *Self, args: Args, _: *Result) !void {
        const id = try args.uInteger(1);
        dock.activate(@intCast(id));
    }
    pub fn close(_: *Self, args: Args, _: *Result) !void {
        const id = try args.uInteger(1);
        dock.close(@intCast(id));
    }
    pub fn setMaximized(_: *Self, args: Args, _: *Result) !void {
        const id = try args.uInteger(1);
        const maximized = try args.bool(2);
        dock.setMaximized(@intCast(id), maximized);
    }
    pub fn setMinimized(_: *Self, args: Args, _: *Result) !void {
        const id = try args.uInteger(1);
        const minimized = try args.bool(2);
        dock.setMinimized(@intCast(id), minimized);
    }
    pub fn setFullscreen(_: *Self, args: Args, _: *Result) !void {
        const id = try args.uInteger(1);
        const fullscreen = try args.bool(2);
        dock.setFullscreen(@intCast(id), fullscreen);
    }
};
