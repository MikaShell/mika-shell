const std = @import("std");
const modules = @import("modules.zig");
const Args = modules.Args;
const Result = modules.Result;
const Context = modules.Context;
const Registry = modules.Registry;
const Allocator = std.mem.Allocator;
const App = @import("../app.zig").App;
const dock = @import("../lib/dock.zig");
const events = @import("../events.zig").Dock;
pub const Dock = struct {
    const Self = @This();
    allocator: Allocator,
    app: *App,
    dock: *dock.Dock,
    subscriber: std.ArrayList(u64),
    pub fn init(ctx: Context) !*Self {
        const self = try ctx.allocator.create(Self);
        const allocator = ctx.allocator;
        self.allocator = allocator;
        self.app = ctx.app;
        self.dock = try dock.Dock.init(allocator, self);
        self.subscriber = std.ArrayList(u64).init(allocator);
        self.dock.onAdded = @ptrCast(&onAdded);
        self.dock.onChanged = @ptrCast(&onChanged);
        self.dock.onClosed = @ptrCast(&onClosed);
        self.dock.onEnter = @ptrCast(&onEnter);
        self.dock.onLeave = @ptrCast(&onLeave);
        self.dock.onActivated = @ptrCast(&onActivated);
        return self;
    }
    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.dock.deinit();
        self.subscriber.deinit();
        allocator.destroy(self);
    }
    pub fn register() Registry(Self) {
        return &.{
            .{ "list", list },
            .{ "activate", activate },
            .{ "close", close },
            .{ "maximized", setMaximized },
            .{ "minimized", setMinimized },
            .{ "fullscreen", setFullscreen },
            .{ "subscribe", subscribe },
            .{ "unsubscribe", unsubscribe },
        };
    }
    pub fn subscribe(self: *Self, args: Args, _: *Result) !void {
        const id = args.uInteger(0) catch unreachable;
        try self.subscriber.append(id);
    }
    fn unsubscribe_(self: *Self, id: u64) void {
        for (self.subscriber.items, 0..) |item, i| {
            if (item == id) {
                _ = self.subscriber.swapRemove(i);
                break;
            }
        }
    }
    pub fn unsubscribe(self: *Self, args: Args, _: *Result) !void {
        const id = args.uInteger(0) catch unreachable;
        self.unsubscribe_(id);
    }
    fn emit(self: *Self, event: []const u8, data: anytype) void {
        for (self.subscriber.items) |id| {
            const ok = self.app.emitEventTo(id, event, data);
            if (!ok) self.unsubscribe_(id);
        }
    }
    fn onAdded(self: *Self, item: dock.Item) void {
        self.emit(events.added, item);
    }
    fn onChanged(self: *Self, item: dock.Item) void {
        self.emit(events.changed, item);
    }
    fn onClosed(self: *Self, id: u32) void {
        self.emit(events.closed, id);
    }
    fn onEnter(self: *Self, id: u32) void {
        self.emit(events.enter, id);
    }
    fn onLeave(self: *Self, id: u32) void {
        self.emit(events.leave, id);
    }
    fn onActivated(self: *Self, id: u32) void {
        self.emit(events.activated, id);
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
