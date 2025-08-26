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
            if (d.roundtrip() == .SUCCESS) return 1;
            return 0;
        }
    }.cb, display);
    _ = display.flush();
    return .{ .source = source, .display = display };
}
