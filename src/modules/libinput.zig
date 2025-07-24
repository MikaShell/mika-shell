const std = @import("std");
const modules = @import("modules.zig");
const Args = modules.Args;
const Result = modules.Result;
const Context = modules.Context;
const Registry = modules.Registry;
const Allocator = std.mem.Allocator;
const App = @import("../app.zig").App;
const events = @import("../events.zig").Dock;
const Emitter = @import("common.zig").Emitter;
const libinput = @import("../lib/libinput.zig");
pub const Libinput = struct {
    const Self = @This();
    allocator: Allocator,
    app: *App,
    emitter: *Emitter,
    input: ?*libinput.Libinput,
    pub fn init(ctx: Context) !*Self {
        const self = try ctx.allocator.create(Self);
        errdefer ctx.allocator.destroy(self);
        const allocator = ctx.allocator;
        self.allocator = allocator;
        self.app = ctx.app;
        self.emitter = try Emitter.init(ctx.app, ctx.allocator);
        self.input = null;
        return self;
    }
    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.emitter.deinit();
        allocator.destroy(self);
    }
    fn onEvent(self: *Self, e: libinput.Event) void {
        const fullEvent = std.fmt.allocPrint(self.allocator, "libinput-{s}", .{@tagName(e)}) catch unreachable;
        defer self.allocator.free(fullEvent);
        switch (e) {
            .keyboardKey => |key| self.emitter.emit(fullEvent, key),
            .pointerMotion => |motion| self.emitter.emit(fullEvent, motion),
            .pointerButton => |button| self.emitter.emit(fullEvent, button),
            else => @panic("Unsupported event type"),
        }
    }
    pub fn register() Registry(Self) {
        return &.{
            .{ "subscribe", subscribe },
            .{ "unsubscribe", unsubscribe },
        };
    }
    fn setup(self: *Self) !void {
        if (self.input == null) {
            const input = try libinput.Libinput.init(self.allocator);
            self.input = input;
            input.userData = self;
            input.onEvent = @ptrCast(&onEvent);
        }
    }
    fn parseEventType(t: []const u8) !libinput.EventType {
        const eql = std.mem.eql;
        for (std.enums.values(libinput.EventType)) |e| {
            if (eql(u8, @tagName(e), t)) {
                return e;
            }
        }
        return error.InvalidEventType;
    }
    pub fn subscribe(self: *Self, args: Args, _: *Result) !void {
        try self.setup();
        const event = try args.string(1);
        const fullEvent = try std.fmt.allocPrint(self.allocator, "libinput-{s}", .{event});
        defer self.allocator.free(fullEvent);
        try self.emitter.subscribe(args, fullEvent);
        self.input.?.addListener(try parseEventType(event));
    }
    pub fn unsubscribe(self: *Self, args: Args, _: *Result) !void {
        const event = try args.string(1);
        const fullEvent = try std.fmt.allocPrint(self.allocator, "libinput-{s}", .{event});
        defer self.allocator.free(fullEvent);
        try self.emitter.unsubscribe(args, fullEvent);
        if (self.input != null) {
            if (self.emitter.subscriber.get(fullEvent) == null) {
                self.input.?.removeListener(try parseEventType(event));
            }
            if (self.emitter.subscriber.count() == 0) {
                self.input.?.deinit();
                self.input = null;
            }
        }
    }
};
