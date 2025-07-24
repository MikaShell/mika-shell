const std = @import("std");
const c = @cImport({
    @cInclude("libinput.h");
    @cInclude("libudev.h");
});
pub const struct_libinput_interface = struct {
    open_restricted: ?*const fn ([*c]const u8, c_int, ?*anyopaque) callconv(.c) c_int = @import("std").mem.zeroes(?*const fn ([*c]const u8, c_int, ?*anyopaque) callconv(.c) c_int),
    close_restricted: ?*const fn (c_int, ?*anyopaque) callconv(.c) void = @import("std").mem.zeroes(?*const fn (c_int, ?*anyopaque) callconv(.c) void),
};
fn open_restricted(path: [*c]const u8, flags: c_int, data: ?*anyopaque) callconv(.c) c_int {
    const libinput: *Libinput = @ptrCast(@alignCast(data));
    const fd = std.posix.open(std.mem.span(path), @bitCast(flags), 0o666) catch |err| {
        if (libinput.onError) |onError| onError(libinput.userData, err);
        return -1;
    };
    return fd;
}
fn close_restricted(fd: c_int, _: ?*anyopaque) callconv(.c) void {
    std.posix.close(fd);
}
const glib = @import("glib");
const Allocator = std.mem.Allocator;

pub const Libinput = struct {
    const Self = @This();
    allocator: Allocator,
    libinput: *c.struct_libinput,
    udev: *c.struct_udev,
    watch: glib.FdWatch2(*Self),
    userData: ?*anyopaque,
    onEvent: ?*const fn (?*anyopaque, Event) void,
    onError: ?*const fn (?*anyopaque, anyerror) void,
    listen: std.AutoHashMap(EventType, void),
    pub fn init(allocator: Allocator) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);
        const udev = c.udev_new();
        if (udev == null) return error.UdevInitFailed;
        const libinputIface = c.libinput_interface{
            .open_restricted = open_restricted,
            .close_restricted = close_restricted,
        };
        const libinput = c.libinput_udev_create_context(&libinputIface, self, udev);
        if (libinput == null) return error.LibinputInitFailed;
        _ = c.libinput_udev_assign_seat(libinput, "seat0");
        const watch = try glib.FdWatch2(*Self).add(c.libinput_get_fd(libinput), onEvent, self);
        self.* = Self{
            .allocator = allocator,
            .libinput = libinput.?,
            .udev = udev.?,
            .watch = watch,
            .userData = null,
            .onEvent = null,
            .onError = null,
            .listen = std.AutoHashMap(EventType, void).init(allocator),
        };
        return self;
    }
    pub fn deinit(self: *Self) void {
        _ = c.libinput_unref(self.libinput);
        _ = c.udev_unref(self.udev);
        self.watch.deinit();
        self.allocator.destroy(self);
    }
    pub fn addListener(self: *Self, e: EventType) void {
        _ = self.listen.put(e, {}) catch {};
    }
    pub fn removeListener(self: *Self, e: EventType) void {
        _ = self.listen.remove(e);
    }
};
fn onEvent(self: *Libinput) bool {
    const libinput = self.libinput;
    while (true) {
        if (c.libinput_dispatch(libinput) != 0) {
            if (self.onError) |onError| {
                onError(self.userData, error.LibinputDispatchFailed);
            }
            return false;
        }
        const e = c.libinput_get_event(libinput);
        if (e == null) return true;
        defer c.libinput_event_destroy(e);
        const eventType: EventType = @enumFromInt(c.libinput_event_get_type(e));
        if (self.onEvent) |handle| {
            if (!self.listen.contains(eventType)) continue;
            const event = makeEvent(eventType, e);
            handle(self.userData, event);
        }
    }
    return true;
}
fn makeEvent(t: EventType, e: ?*c.struct_libinput_event) Event {
    switch (t) {
        .keyboardKey => {
            const keyEvent = c.libinput_event_get_keyboard_event(e);
            const key = c.libinput_event_keyboard_get_key(keyEvent);
            const state = c.libinput_event_keyboard_get_key_state(keyEvent);
            return Event{
                .keyboardKey = .{
                    .key = key,
                    .state = state,
                },
            };
        },
        .pointerMotion => {
            const motionEvent = c.libinput_event_get_pointer_event(e);
            const dx = c.libinput_event_pointer_get_dx(motionEvent);
            const dy = c.libinput_event_pointer_get_dy(motionEvent);
            const dxUnaccelerated = c.libinput_event_pointer_get_dx_unaccelerated(motionEvent);
            const dyUnaccelerated = c.libinput_event_pointer_get_dy_unaccelerated(motionEvent);
            return Event{
                .pointerMotion = .{
                    .dx = dx,
                    .dy = dy,
                    .dxUnaccelerated = dxUnaccelerated,
                    .dyUnaccelerated = dyUnaccelerated,
                },
            };
        },
        .pointerButton => {
            const buttonEvent = c.libinput_event_get_pointer_event(e);
            const button = c.libinput_event_pointer_get_button(buttonEvent);
            const state = c.libinput_event_pointer_get_button_state(buttonEvent);
            return Event{
                .pointerButton = .{
                    .button = button,
                    .state = state,
                },
            };
        },
        else => {
            return .{ .none = {} };
        },
    }
}
pub const EventType = enum(c_int) {
    none = c.LIBINPUT_EVENT_NONE,
    deviceAdded = c.LIBINPUT_EVENT_DEVICE_ADDED,
    deviceRemoved = c.LIBINPUT_EVENT_DEVICE_REMOVED,
    keyboardKey = c.LIBINPUT_EVENT_KEYBOARD_KEY,
    pointerMotion = c.LIBINPUT_EVENT_POINTER_MOTION,
    pointerMotionAbsolute = c.LIBINPUT_EVENT_POINTER_MOTION_ABSOLUTE,
    pointerButton = c.LIBINPUT_EVENT_POINTER_BUTTON,
    pointerAxis = c.LIBINPUT_EVENT_POINTER_AXIS,
    pointerScrollWheel = c.LIBINPUT_EVENT_POINTER_SCROLL_WHEEL,
    pointerScrollFinger = c.LIBINPUT_EVENT_POINTER_SCROLL_FINGER,
    pointerScrollContinuous = c.LIBINPUT_EVENT_POINTER_SCROLL_CONTINUOUS,
    touchDown = c.LIBINPUT_EVENT_TOUCH_DOWN,
    touchUp = c.LIBINPUT_EVENT_TOUCH_UP,
    touchMotion = c.LIBINPUT_EVENT_TOUCH_MOTION,
    touchCancel = c.LIBINPUT_EVENT_TOUCH_CANCEL,
    touchFrame = c.LIBINPUT_EVENT_TOUCH_FRAME,
    tabletToolAxis = c.LIBINPUT_EVENT_TABLET_TOOL_AXIS,
    tabletToolProximity = c.LIBINPUT_EVENT_TABLET_TOOL_PROXIMITY,
    tabletToolTip = c.LIBINPUT_EVENT_TABLET_TOOL_TIP,
    tabletToolButton = c.LIBINPUT_EVENT_TABLET_TOOL_BUTTON,
    tabletPadButton = c.LIBINPUT_EVENT_TABLET_PAD_BUTTON,
    tabletPadRing = c.LIBINPUT_EVENT_TABLET_PAD_RING,
    tabletPadStrip = c.LIBINPUT_EVENT_TABLET_PAD_STRIP,
    tabletPadKey = c.LIBINPUT_EVENT_TABLET_PAD_KEY,
    tabletPadDial = c.LIBINPUT_EVENT_TABLET_PAD_DIAL,
    gestureSwipeBegin = c.LIBINPUT_EVENT_GESTURE_SWIPE_BEGIN,
    gestureSwipeUpdate = c.LIBINPUT_EVENT_GESTURE_SWIPE_UPDATE,
    gestureSwipeEnd = c.LIBINPUT_EVENT_GESTURE_SWIPE_END,
    gesturePinchBegin = c.LIBINPUT_EVENT_GESTURE_PINCH_BEGIN,
    gesturePinchUpdate = c.LIBINPUT_EVENT_GESTURE_PINCH_UPDATE,
    gesturePinchEnd = c.LIBINPUT_EVENT_GESTURE_PINCH_END,
    gestureHoldBegin = c.LIBINPUT_EVENT_GESTURE_HOLD_BEGIN,
    gestureHoldEnd = c.LIBINPUT_EVENT_GESTURE_HOLD_END,
    switchToggle = c.LIBINPUT_EVENT_SWITCH_TOGGLE,
};
// TODO: 实现其他事件
pub const Event = union(enum) {
    none: void,
    keyboardKey: struct {
        key: u32,
        state: u32,
    },
    pointerMotion: struct {
        dx: f64,
        dy: f64,
        dxUnaccelerated: f64,
        dyUnaccelerated: f64,
    },
    pointerButton: struct {
        button: u32,
        state: u32,
    },
};
