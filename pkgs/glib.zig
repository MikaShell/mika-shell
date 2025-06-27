const c = @cImport({
    @cInclude("glib-2.0/glib.h");
    @cInclude("gio/gio.h");
});
const std = @import("std");
pub fn timeoutMainLoop(timeout_ms: u32) void {
    const loop = c.g_main_loop_new(null, 0);
    _ = c.g_timeout_add(timeout_ms, &struct {
        fn timeout(loop_: ?*anyopaque) callconv(.c) c_int {
            const loop__: *c.GMainLoop = @ptrCast(@alignCast(loop_));
            c.g_main_loop_quit(loop__);
            return 0;
        }
    }.timeout, loop);
    c.g_main_loop_run(loop);
}
pub fn mainIteration() bool {
    return c.g_main_context_iteration(null, 1) == 1;
}
pub fn FdWatch(T: type) type {
    return struct {
        const Callback = if (T == void) *const fn () bool else *const fn (*T) bool;
        const Wrapper = struct {
            d: *T,
            c: Callback,
            fn f(_: *c.GIOChannel, _: c.GIOCondition, w: *@This()) callconv(.c) c_int {
                return @intFromBool(if (T == void) w.c() else w.c(w.d));
            }
        };

        source: c_uint,
        wrapper: *Wrapper,
        pub fn add(fd: c_int, callback: Callback, data: *T) !@This() {
            const ch = c.g_io_channel_unix_new(fd);
            if (ch == null) return error.FailedToCreateChannel;
            defer c.g_io_channel_unref(ch);
            const wrapper = try std.heap.page_allocator.create(Wrapper);
            wrapper.* = .{
                .d = data,
                .c = callback,
            };
            const source = c.g_io_add_watch(ch, c.G_IO_IN, @ptrCast(&Wrapper.f), wrapper);
            return .{
                .source = source,
                .wrapper = wrapper,
            };
        }
        pub fn deinit(self: @This()) void {
            _ = c.g_source_remove(self.source);
            std.heap.page_allocator.destroy(self.wrapper);
        }
    };
}
