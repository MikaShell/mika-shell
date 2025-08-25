pub const c = @cImport({
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
// TODO: 优化这个玩意
pub fn FdWatch(T: type) type {
    return struct {
        const Callback = if (T == void) *const fn () bool else *const fn (*T) bool;
        const Wrapper = struct {
            d: *T,
            c: Callback,
            result: bool,
            fn f(_: *c.GIOChannel, _: c.GIOCondition, w: *@This()) callconv(.c) c_int {
                w.result = if (T == void) w.c() else w.c(w.d);
                return @intFromBool(w.result);
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
                .result = true,
            };
            const source = c.g_io_add_watch(ch, c.G_IO_IN, @ptrCast(&Wrapper.f), wrapper);
            if (source == 0) {
                std.heap.page_allocator.destroy(wrapper);
                return error.FailedToAddWatch;
            }
            return .{
                .source = source,
                .wrapper = wrapper,
            };
        }
        pub fn deinit(self: @This()) void {
            if (self.wrapper.result) {
                _ = c.g_source_remove(self.source);
            }
            std.heap.page_allocator.destroy(self.wrapper);
        }
    };
}
pub fn FdWatch2(T: type) type {
    switch (@typeInfo(T)) {
        .pointer, .void => {},
        else => {
            @panic("T must be a pointer or void");
        },
    }
    return struct {
        const Callback = if (T == void) *const fn (void) bool else *const fn (T) bool;
        const Wrapper = struct {
            d: T,
            c: Callback,
            result: bool,
            fn f(_: *c.GIOChannel, _: c.GIOCondition, w: *@This()) callconv(.c) c_int {
                w.result = if (T == void) w.c({}) else w.c(w.d);
                return @intFromBool(w.result);
            }
        };

        source: c_uint,
        wrapper: *Wrapper,
        pub fn add(fd: c_int, callback: Callback, data: if (T == void) null else T) !@This() {
            const ch = c.g_io_channel_unix_new(fd);
            if (ch == null) return error.FailedToCreateChannel;
            defer c.g_io_channel_unref(ch);
            const wrapper = try std.heap.page_allocator.create(Wrapper);
            wrapper.* = .{
                .d = data,
                .c = callback,
                .result = true,
            };
            const source = c.g_io_add_watch(ch, c.G_IO_IN, @ptrCast(&Wrapper.f), wrapper);
            if (source == 0) {
                std.heap.page_allocator.destroy(wrapper);
                return error.FailedToAddWatch;
            }
            return .{
                .source = source,
                .wrapper = wrapper,
            };
        }
        pub fn deinit(self: @This()) void {
            if (self.wrapper.result) {
                _ = c.g_source_remove(self.source);
            }
            std.heap.page_allocator.destroy(self.wrapper);
        }
    };
}
