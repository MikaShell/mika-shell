const wayland = @import("zig-wayland");
const wl = wayland.client.wl;
const glib = @import("glib");
pub const GLibWatch = struct {
    source: c_uint,
    display: *wl.Display,
    pub fn deinit(self: @This()) void {
        _ = glib.Source.remove(self.source);
        self.display.disconnect();
    }
};
pub fn withGLibMainLoop(display: *wl.Display) !GLibWatch {
    const ch = glib.IOChannel.unixNew(display.getFd());
    defer ch.unref();
    const source = glib.ioAddWatch(ch, .{ .in = true }, &struct {
        fn cb(_: *glib.IOChannel, _: glib.IOCondition, data: ?*anyopaque) callconv(.C) c_int {
            const d: *wl.Display = @alignCast(@ptrCast(data));
            if (d.dispatch() == .SUCCESS) return 1;
            return 0;
        }
    }.cb, display);
    _ = display.flush();
    return .{ .source = source, .display = display };
}
const xev = @import("xev");
const std = @import("std");
pub const XevWatch = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    display: *wl.Display,
    loop: *xev.IO_Uring.Loop,
    completion: xev.Completion,
    cancel: xev.Completion,
    shouldStop: bool,
    /// 异步地执行 display.disconnect() 和释放 XevWatch
    ///
    /// 需要 loop 处于运行状态
    pub fn deinit(self: *Self) void {
        self.shouldStop = true;
        self.loop.add(&self.cancel);
    }
};

pub fn withXevLoop(allocator: std.mem.Allocator, display: *wl.Display, loop: *xev.IO_Uring.Loop) !*XevWatch {
    const watch = try allocator.create(XevWatch);
    watch.* = .{
        .allocator = allocator,
        .display = display,
        .loop = loop,
        .completion = undefined,
        .cancel = undefined,
        .shouldStop = false,
    };
    watch.completion = .{
        .op = .{ .poll = .{ .fd = display.getFd() } },
        .callback = struct {
            fn cb(
                data: ?*anyopaque,
                _: *xev.Loop,
                _: *xev.Completion,
                r: xev.Result,
            ) xev.CallbackAction {
                _ = r.poll catch |err| {
                    std.log.scoped(.wayland).err("Failed to read events: {s}", .{@errorName(err)});
                    return .disarm;
                };
                const watch_inner: *XevWatch = @ptrCast(@alignCast(data));
                const d = watch_inner.display;
                if (d.prepareRead()) {
                    if (d.readEvents() != .SUCCESS) {
                        std.log.scoped(.wayland).err("Failed to read events", .{});
                        return .disarm;
                    }
                }
                if (d.dispatchPending() != .SUCCESS) {
                    std.log.scoped(.wayland).err("Failed to dispatch events", .{});
                    return .disarm;
                }
                if (watch_inner.shouldStop) return .disarm;
                return .rearm;
            }
        }.cb,
        .userdata = watch,
    };

    watch.cancel = .{
        .op = .{ .cancel = .{ .c = &watch.completion } },
        .callback = struct {
            fn cb(
                data: ?*anyopaque,
                _: *xev.IO_Uring.Loop,
                _: *xev.Completion,
                r: xev.Result,
            ) xev.CallbackAction {
                _ = r.cancel catch {};
                const watch_: *XevWatch = @ptrCast(@alignCast(data));
                watch_.display.disconnect();
                watch_.allocator.destroy(watch_);
                return .disarm;
            }
        }.cb,
        .userdata = watch,
    };
    loop.add(&watch.completion);
    _ = display.flush();
    return watch;
}
// connect to the display and set the listener for the registry
pub fn init(comptime T: type, listener: *const fn (registry: *wl.Registry, event: wl.Registry.Event, data: T) void, data: T) !*wl.Display {
    const display = try wl.Display.connect(null);
    errdefer display.disconnect();
    const registry = try display.getRegistry();
    defer registry.destroy();
    registry.setListener(T, listener, data);
    _ = display.roundtrip();
    return display;
}

// testing use only
pub fn timeoutMainLoop(timeout_ms: u32) void {
    const loop = glib.MainLoop.new(null, 0);
    _ = glib.timeoutAddOnce(timeout_ms, @ptrCast(&struct {
        fn timeout(data: ?*anyopaque) callconv(.c) c_int {
            const loop_: *glib.MainLoop = @ptrCast(@alignCast(data));
            loop_.quit();
            return 0;
        }
    }.timeout), loop);
    loop.run();
}
