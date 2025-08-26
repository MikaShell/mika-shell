const std = @import("std");
const wayland = @import("zig-wayland");
const wl = wayland.client.wl;
const ftm = @import("wayland/foreign-toplevel-manager.zig");

const Context = struct {
    ftm: *ftm.Manager,
    seat: *wl.Seat,
    allocator: Allocator,
};

const Allocator = std.mem.Allocator;
const glib = @import("glib");
var display: *wl.Display = undefined;
var context: Context = undefined;
pub const GLibWatch = struct {
    source: c_uint,
    pub fn deinit(self: @This()) void {
        _ = glib.Source.remove(self.source);
    }
};
pub fn withGLib() !GLibWatch {
    const ch = glib.IOChannel.unixNew(display.getFd());
    defer ch.unref();
    const source = glib.ioAddWatch(ch, .{ .in = true }, &struct {
        fn cb(_: *glib.IOChannel, _: glib.IOCondition, data: ?*anyopaque) callconv(.C) c_int {
            const d: *wl.Display = @alignCast(@ptrCast(data));
            if (d.roundtrip() == .SUCCESS) return 1;
            return 0;
        }
    }.cb, display);
    return .{ .source = source };
}
pub fn init(allocator: Allocator) !void {
    display = try wl.Display.connect(null);
    const registry = try display.getRegistry();
    defer registry.destroy();
    context.allocator = allocator;
    foreignToplevel.handlers = std.AutoHashMap(u32, *ftm.Handle).init(allocator);
    registry.setListener(*Context, registryListener, &context);
    _ = display.roundtrip();
    context.ftm.setListener(*Context, ftmListener, &context);
}
fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, ctx: *Context) void {
    const mem = std.mem;
    switch (event) {
        .global => |global| {
            if (mem.orderZ(u8, global.interface, ftm.Manager.interface.name) == .eq) {
                ctx.ftm = registry.bind(global.name, ftm.Manager, 3) catch return;
            } else if (mem.orderZ(u8, global.interface, wl.Seat.interface.name) == .eq) {
                ctx.seat = registry.bind(global.name, wl.Seat, 1) catch return;
            }
        },
        .global_remove => @panic("global_remove not implemented"),
    }
}
pub const foreignToplevel = struct {
    var handlers: std.AutoHashMap(u32, *ftm.Handle) = undefined;
    var listener: ftm.ToplevelListener = .{};
    var userData: ?*anyopaque = null;
    pub const Toplevel = ftm.Toplevel;
    pub const Listener: *ftm.ToplevelListener = &listener;
    pub const State = ftm.Handle.State;
    pub fn setUserData(data: ?*anyopaque) void {
        userData = data;
    }
    pub fn activate(id: u32) void {
        const handle = handlers.get(id) orelse return;
        handle.activate(context.seat);
    }
    pub fn close(id: u32) void {
        const handle = handlers.get(id) orelse return;
        handle.close();
    }
    pub fn setMaximized(id: u32, maximized: bool) void {
        const handle = handlers.get(id) orelse return;
        if (maximized) {
            handle.setMaximized();
        } else {
            handle.unsetMaximized();
        }
    }
    pub fn setMinimized(id: u32, minimized: bool) void {
        const handle = handlers.get(id) orelse return;
        if (minimized) {
            handle.setMinimized();
        } else {
            handle.unsetMinimized();
        }
    }
    pub fn setFullscreen(id: u32, fullscreen: bool) void {
        const handle = handlers.get(id) orelse return;
        if (fullscreen) {
            handle.setFullscreen(null);
        } else {
            handle.unsetFullscreen();
        }
    }
};
fn ftmListener(_: *ftm.Manager, event: ftm.Manager.Event, ctx: *Context) void {
    switch (event) {
        .toplevel => |t| {
            const toplevel_ = ctx.allocator.create(ftm.Context) catch return;
            toplevel_.* = .{
                .id = ftm.Handle.getId(t.toplevel),
                .allocator = ctx.allocator,
                .listener = foreignToplevel.Listener,
                .userData = foreignToplevel.userData,
                .handlers = &foreignToplevel.handlers,
            };
            foreignToplevel.handlers.put(toplevel_.id, t.toplevel) catch return;
            ftm.Handle.setListener(t.toplevel, *ftm.Context, ftm.handleToplevel, toplevel_);
        },
        .finished => {
            foreignToplevel.handlers.deinit();
        },
    }
}
