const std = @import("std");
const wayland = @import("zig-wayland");
const wl = wayland.client.wl;
pub const Manager = wayland.client.zwlr.ForeignToplevelManagerV1;
pub const Handle = wayland.client.zwlr.ForeignToplevelHandleV1;
pub const ToplevelListener = struct {
    onChanged: ?*const fn (?*anyopaque, Toplevel) void = null,
    onClosed: ?*const fn (?*anyopaque, u32) void = null,
    onEnter: ?*const fn (?*anyopaque, u32) void = null,
    onLeave: ?*const fn (?*anyopaque, u32) void = null,
};

pub const Toplevel = struct {
    id: u32,
    title: []const u8,
    appId: []const u8,
    state: []Handle.State,
};

pub const Context = struct {
    allocator: std.mem.Allocator,
    listener: *ToplevelListener,
    userData: ?*anyopaque = null,
    handlers: *std.AutoHashMap(u32, *Handle),
    closed: bool = false,
    id: u32,
    title: []const u8 = "",
    appId: []const u8 = "",
    state: []Handle.State = &.{},
};
pub fn handleToplevel(h: *Handle, event: Handle.Event, t: *Context) void {
    switch (event) {
        .app_id => |appId| {
            if (t.closed) return;
            t.allocator.free(t.appId);
            t.appId = t.allocator.dupe(u8, std.mem.span(appId.app_id)) catch return;
        },
        .title => |title| {
            if (t.closed) return;
            t.allocator.free(t.title);
            t.title = t.allocator.dupe(u8, std.mem.span(title.title)) catch return;
        },
        .state => |state| {
            if (t.closed) return;
            t.allocator.free(t.state);
            const status = state.state.slice(c_int);
            var status_ = t.allocator.alloc(Handle.State, status.len) catch return;
            for (status, 0..) |s, i| {
                status_[i] = @enumFromInt(s);
            }
            t.state = status_;
        },
        .done => {
            if (t.closed) return;
            if (t.listener.onChanged) |onChanged| onChanged(t.userData, .{
                .id = t.id,
                .title = t.title,
                .appId = t.appId,
                .state = t.state,
            });
        },
        .closed => {
            t.closed = true;
            if (t.listener.onClosed) |onRemoved| onRemoved(t.userData, t.id);
            h.destroy();
            _ = t.handlers.remove(t.id);
            t.allocator.free(t.title);
            t.allocator.free(t.appId);
            t.allocator.free(t.state);
            t.allocator.destroy(t);
        },
        .output_enter => {
            if (t.listener.onEnter) |onEnter| onEnter(t.userData, t.id);
        },
        .output_leave => {
            if (t.listener.onLeave) |onLeave| onLeave(t.userData, t.id);
        },
        else => {},
    }
}
