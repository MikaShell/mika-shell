const glib = @import("glib");

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
