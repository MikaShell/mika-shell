const wayland = @import("zig-wayland");
const wl = wayland.client.wl;
const glib = @import("glib");
pub const GLibWatch = struct {
    source: c_uint,
    display: *wl.Display,
    pub fn deinit(self: @This()) void {
        _ = glib.Source.remove(self.source);
    }
};
pub fn withGLibMainLoop(display: *wl.Display) !GLibWatch {
    const ch = glib.IOChannel.unixNew(display.getFd());
    defer ch.unref();
    const source = glib.ioAddWatch(ch, .{ .in = true }, &struct {
        fn cb(_: *glib.IOChannel, _: glib.IOCondition, data: ?*anyopaque) callconv(.c) c_int {
            const d: *wl.Display = @ptrCast(@alignCast(data));
            if (d.prepareRead()) {
                if (d.readEvents() != .SUCCESS) {
                    std.log.scoped(.wayland).err("Failed to read events", .{});
                    return 0;
                }
            }
            if (d.dispatchPending() != .SUCCESS) {
                std.log.scoped(.wayland).err("Failed to dispatch events", .{});
                return 0;
            }
            return 1;
        }
    }.cb, display);
    _ = display.flush();
    return .{ .source = source, .display = display };
}
const std = @import("std");
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
