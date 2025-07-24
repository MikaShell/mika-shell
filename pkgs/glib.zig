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
pub const FileMonitor = struct {
    pub const Event = enum(c_int) {
        changed = c.G_FILE_MONITOR_EVENT_CHANGED,
        changesDone = c.G_FILE_MONITOR_EVENT_CHANGES_DONE_HINT,
        deleted = c.G_FILE_MONITOR_EVENT_DELETED,
        created = c.G_FILE_MONITOR_EVENT_CREATED,
        attributeChanged = c.G_FILE_MONITOR_EVENT_ATTRIBUTE_CHANGED,
        preunmount = c.G_FILE_MONITOR_EVENT_PRE_UNMOUNT,
        unmounted = c.G_FILE_MONITOR_EVENT_UNMOUNTED,
        moved = c.G_FILE_MONITOR_EVENT_MOVED,
        renamed = c.G_FILE_MONITOR_EVENT_RENAMED,
        movein = c.G_FILE_MONITOR_EVENT_MOVED_IN,
        moveout = c.G_FILE_MONITOR_EVENT_MOVED_OUT,
    };
    const Callback = *const fn (?*anyopaque, file: ?[]const u8, otherFile: ?[]const u8, event: Event) void;
    const Wrapper = struct {
        d: ?*anyopaque,
        c: Callback,
        fn f(_: *c.GFileMonitor, file: ?*c.GFile, otherFile: ?*c.GFile, event: c.GFileMonitorEvent, w: *@This()) callconv(.c) void {
            var file_: ?[]const u8 = null;
            var otherFile_: ?[]const u8 = null;
            const file_c = if (file) |fc| c.g_file_get_path(fc) else null;
            defer if (file_c) |fc| c.g_free(fc);
            const otherFile_c = if (otherFile) |ofc| c.g_file_get_path(ofc) else null;
            defer if (otherFile_c) |ofc| c.g_free(ofc);
            if (file_c) |fc| file_ = std.mem.span(fc);
            if (otherFile_c) |ofc| otherFile_ = std.mem.span(ofc);
            const event_: Event = @enumFromInt(event);
            w.c(w.d, file_, otherFile_, event_);
        }
    };
    wrapper: *Wrapper,
    monitor: *c.GFileMonitor,
    pub fn addFile(path: []const u8, callback: Callback, data: ?*anyopaque) !@This() {
        return try add(true, path, callback, data);
    }
    pub fn addDirectory(path: []const u8, callback: Callback, data: ?*anyopaque) !@This() {
        return try add(false, path, callback, data);
    }
    fn add(isFile: bool, path: []const u8, callback: Callback, data: ?*anyopaque) !@This() {
        const gFile = c.g_file_new_for_path(path.ptr);
        if (gFile == null) return error.FailedToCreateFile;
        defer c.g_object_unref(gFile);
        const wrapper = try std.heap.page_allocator.create(Wrapper);
        errdefer std.heap.page_allocator.destroy(wrapper);
        wrapper.* = .{
            .d = data,
            .c = callback,
        };
        var err: *c.GError = undefined;
        const monitor = if (isFile) c.g_file_monitor(gFile, c.G_FILE_MONITOR_NONE, null, @ptrCast(&err)) else c.g_file_monitor_directory(gFile, c.G_FILE_MONITOR_NONE, null, @ptrCast(&err));
        if (monitor == null) {
            c.g_error_free(@ptrCast(&err));
            return error.FailedToMonitorFile;
        }
        _ = c.g_signal_connect_data(monitor, "changed", @ptrCast(&Wrapper.f), @ptrCast(wrapper), null, 0);
        return .{
            .wrapper = wrapper,
            .monitor = monitor,
        };
    }
    pub fn deinit(self: @This()) void {
        c.g_object_unref(self.monitor);
        std.heap.page_allocator.destroy(self.wrapper);
    }
};

pub const Timeout = struct {
    const Callback = *const fn (?*anyopaque) bool;
    const Wrapper = struct {
        d: ?*anyopaque,
        c: Callback,
        result: bool,
        fn f(w: *@This()) callconv(.c) c_int {
            w.result = w.c(w.d);
            return @intFromBool(w.result);
        }
    };
    wrapper: *Wrapper,
    source: c_uint,
    pub fn add(timeout_ms: u32, callback: Callback, data: ?*anyopaque) !@This() {
        const wrapper = try std.heap.page_allocator.create(Wrapper);
        wrapper.* = .{
            .d = data,
            .c = callback,
            .result = true,
        };
        const source = c.g_timeout_add(timeout_ms, @ptrCast(&Wrapper.f), @ptrCast(wrapper));
        if (source == 0) {
            std.heap.page_allocator.destroy(wrapper);
            return error.FailedToAddTimeout;
        }
        return .{
            .wrapper = wrapper,
            .source = source,
        };
    }
    pub fn deinit(self: @This()) void {
        if (self.wrapper.result) {
            _ = c.g_source_remove(self.source);
        }
        std.heap.page_allocator.destroy(self.wrapper);
    }
};
