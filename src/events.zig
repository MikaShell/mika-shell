const std = @import("std");
pub const Events = enum(u32) {
    mika_close_request,
    mika_show_request,
    mika_hide_request,
    mika_open,
    mika_close,
    mika_show,
    mika_hide,
    tray_added,
    tray_removed,
    tray_changed,
    notifd_added,
    notifd_removed,
    dock_added,
    dock_changed,
    dock_closed,
    dock_enter,
    dock_leave,
    dock_activated,
    libinput_pointer_motion,
    libinput_pointer_button,
    libinput_keyboard_key,
};
pub const ChangeState = enum {
    add,
    remove,
};
const Allocator = std.mem.Allocator;
pub const Event = struct {
    allocator: Allocator,
    dist: u64,
    data: []const u8,
    pub fn deinit(self: *Event) void {
        self.allocator.free(self.data);
    }
};
fn Channel(comptime T: type, comptime size: usize) type {
    return struct {
        const Self = @This();
        const Buffer = [size]T;
        buf1: Buffer,
        buf2: Buffer,
        index1: std.atomic.Value(usize),
        index2: std.atomic.Value(usize),
        flag: std.atomic.Value(bool),
        out: std.posix.fd_t,
        in: std.posix.fd_t,
        mutex: std.Thread.Mutex,
        condition: std.Thread.Condition,
        signalBuffer: [size]u8,
        pub fn init() !Self {
            const pipe = try std.posix.pipe();
            return Self{
                .buf1 = undefined,
                .buf2 = undefined,
                .signalBuffer = undefined,
                .index1 = std.atomic.Value(usize).init(0),
                .index2 = std.atomic.Value(usize).init(0),
                .flag = std.atomic.Value(bool).init(false),
                .mutex = std.Thread.Mutex{},
                .out = pipe[0],
                .in = pipe[1],
                .condition = std.Thread.Condition{},
            };
        }
        pub fn deinit(self: *Self) void {
            std.posix.close(self.in);
            std.posix.close(self.out);
        }
        pub fn store(self: *Self, event: T) !void {
            const flag = self.flag.load(.acquire);
            const index = if (flag) &self.index1 else &self.index2;
            const buf = if (flag) &self.buf1 else &self.buf2;
            const i = index.load(.acquire);
            if (i == size) {
                self.mutex.lock();
                self.condition.wait(&self.mutex);
                self.mutex.unlock();
                return self.store(event);
            }
            buf[i] = event;
            index.store(i + 1, .release);
            _ = try std.posix.write(self.in, &.{1});
        }
        pub fn load(self: *Self) []T {
            _ = std.posix.read(self.out, &self.signalBuffer) catch unreachable;
            const flag = self.flag.load(.acquire);
            const index = if (flag) &self.index1 else &self.index2;
            const buf = if (flag) &self.buf1 else &self.buf2;
            self.flag.store(!flag, .release);
            const i = index.swap(0, .seq_cst);
            self.condition.signal();
            return buf[0..i];
        }
    };
}
pub const EventChannel = Channel(Event, 128);
fn testChannel(c: *TestChannel) !void {
    for (0..testCount) |i| {
        try c.store(@intCast(i));
    }
}
const testCount = 300;
const print = std.debug.print;
const utils = @import("utils.zig");
const testing = std.testing;
const TestChannel = Channel(i32, 2);
const glib = @import("glib");
test {
    var c = try TestChannel.init();
    _ = try std.Thread.spawn(.{}, testChannel, .{&c});
    const ch = glib.IOChannel.unixNew(c.out);
    defer ch.unref();
    const watch = glib.ioAddWatch(ch, .{ .in = true }, glibCallback, &c);
    defer _ = glib.Source.remove(watch);
    utils.timeoutMainLoop(500);
    try testing.expectEqual(testCount, count);
}
var count: i32 = 0;
fn glibCallback(_: *glib.IOChannel, _: glib.IOCondition, data: ?*anyopaque) callconv(.c) c_int {
    const c: *TestChannel = @alignCast(@ptrCast(data));
    const events = c.load();
    for (events) |event| {
        testing.expectEqual(count, event) catch return 0;
        count += 1;
    }
    return 1;
}
