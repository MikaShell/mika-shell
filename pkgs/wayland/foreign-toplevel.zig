const std = @import("std");
const Allocator = std.mem.Allocator;
const wayland = @import("zig-wayland");
const wl = wayland.client.wl;
const ForeignToplevelManager = wayland.client.zwlr.ForeignToplevelManagerV1;
const ForeignToplevelHandle = wayland.client.zwlr.ForeignToplevelHandleV1;
pub const Listener = struct {
    userdata: ?*anyopaque = null,
    changed: ?*const fn (?*anyopaque, Toplevel) void = null,
    closed: ?*const fn (?*anyopaque, u32) void = null,
    enter: ?*const fn (?*anyopaque, u32) void = null,
    leave: ?*const fn (?*anyopaque, u32) void = null,
};

fn handleToplevel(h: *ForeignToplevelHandle, event: ForeignToplevelHandle.Event, ctx: *Manager) void {
    const toplevelNode = blk: {
        var it = ctx.toplevels.first;
        while (it) |node| {
            const toplevelNode: *ToplevelNode = @fieldParentPtr("node", node);
            if (toplevelNode.data.handler == h) {
                break :blk toplevelNode;
            }
            it = node.next;
        }
        return;
    };
    const t = &toplevelNode.data;
    const allocator = ctx.allocator;
    const span = std.mem.span;
    switch (event) {
        .app_id => |appId| {
            allocator.free(t.appId);
            t.appId = allocator.dupe(u8, span(appId.app_id)) catch return;
        },
        .title => |title| {
            allocator.free(t.title);
            t.title = allocator.dupe(u8, span(title.title)) catch return;
        },
        .state => |state| {
            allocator.free(t.state);
            const status = state.state.slice(c_int);
            var status_ = allocator.alloc(ForeignToplevelHandle.State, status.len) catch return;
            for (status, 0..) |s, i| {
                status_[i] = @enumFromInt(s);
            }
            t.state = status_;
        },
        .done => {
            const toplevelData = t.make();
            if (ctx.listener.changed) |callback| callback(ctx.listener.userdata, toplevelData);
        },
        .closed => {
            if (ctx.listener.closed) |callback| callback(ctx.listener.userdata, h.getId());
            ctx.remove(toplevelNode);
        },
        .output_enter => {
            if (ctx.listener.enter) |callback| callback(ctx.listener.userdata, h.getId());
        },
        .output_leave => {
            if (ctx.listener.leave) |callback| callback(ctx.listener.userdata, h.getId());
        },
        else => {},
    }
}
fn foreignToplevelManagerListener(_: *ForeignToplevelManager, event: ForeignToplevelManager.Event, ctx: *Manager) void {
    switch (event) {
        .toplevel => |t| {
            ctx.append(t.toplevel);
        },
        .finished => {
            ctx.destroy();
        },
    }
}
const ToplevelNode = struct {
    data: ToplevelContext,
    node: std.DoublyLinkedList.Node,
};

pub const Toplevel = struct {
    id: u32,
    title: []const u8,
    appId: []const u8,
    state: []ForeignToplevelHandle.State,
};
const ToplevelContext = struct {
    allocator: Allocator,
    handler: *ForeignToplevelHandle,
    title: []const u8,
    appId: []const u8,
    state: []ForeignToplevelHandle.State,
    fn init(allocator: Allocator, handler: *ForeignToplevelHandle) ToplevelContext {
        return .{
            .allocator = allocator,
            .handler = handler,
            .title = "",
            .appId = "",
            .state = &.{},
        };
    }
    fn deinit(self: *ToplevelContext) void {
        self.allocator.free(self.title);
        self.allocator.free(self.appId);
        self.allocator.free(self.state);
        self.handler.destroy();
    }
    fn make(self: *ToplevelContext) Toplevel {
        return .{
            .id = self.handler.getId(),
            .title = self.title,
            .appId = self.appId,
            .state = self.state,
        };
    }
};
const common = @import("common.zig");
pub const Manager = struct {
    const Self = @This();
    listener: Listener,
    allocator: Allocator,
    foreignToplevelManager: ?*ForeignToplevelManager,
    seat: ?*wl.Seat,
    toplevels: std.DoublyLinkedList,
    glibWatch: common.GLibWatch,
    display: *wl.Display,
    pub fn init(allocator: Allocator, listener: Listener) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.allocator = allocator;
        self.listener = listener;
        self.toplevels = .{};
        const display = try common.init(*Self, registryListener, self);
        errdefer display.disconnect();
        self.display = display;
        try self.check();
        self.foreignToplevelManager.?.setListener(*Self, foreignToplevelManagerListener, self);
        self.glibWatch = try common.withGLibMainLoop(display);
        return self;
    }
    fn check(self: *Self) !void {
        if (self.foreignToplevelManager == null) return error.NotAvailable;
        if (self.seat == null) return error.NotAvailable;
    }
    fn getHandler(self: *Self, id: u32) ?*ForeignToplevelHandle {
        var it = self.toplevels.first;
        while (it) |node| {
            const toplevel: *ToplevelNode = @fieldParentPtr("node", node);
            if (toplevel.data.handler.getId() == id) {
                return toplevel.data.handler;
            }
            it = node.next;
        }
        return null;
    }
    pub fn deinit(self: *Self) void {
        if (self.foreignToplevelManager) |m| {
            m.stop();
            _ = self.display.roundtrip();
        } else {
            self.destroy();
        }
        self.glibWatch.deinit();
        self.display.disconnect();
        self.allocator.destroy(self);
    }
    // 由 wayland 回调的 finish 事件调用
    fn destroy(self: *Self) void {
        while (self.toplevels.pop()) |node| {
            const toplevel: *ToplevelNode = @fieldParentPtr("node", node);
            toplevel.data.deinit();
            self.allocator.destroy(toplevel);
        }
        self.foreignToplevelManager.?.destroy();
        self.foreignToplevelManager = null;
    }
    fn append(self: *Self, t: *ForeignToplevelHandle) void {
        const toplevelNode = self.allocator.create(ToplevelNode) catch unreachable;
        toplevelNode.* = .{
            .data = ToplevelContext.init(self.allocator, t),
            .node = .{},
        };
        self.toplevels.append(&toplevelNode.node);
        t.setListener(*Self, handleToplevel, self);
    }
    fn remove(self: *Self, node: *ToplevelNode) void {
        self.toplevels.remove(&node.node);
        node.data.deinit();
        self.allocator.destroy(node);
    }

    pub fn list(self: *Self, allocator: Allocator) ![]Toplevel {
        var result = std.ArrayList(Toplevel){};
        errdefer result.deinit(allocator);
        var it = self.toplevels.first;
        while (it) |node| {
            const toplevel: *ToplevelNode = @fieldParentPtr("node", node);
            try result.append(allocator, toplevel.data.make());
            it = node.next;
        }
        return try result.toOwnedSlice(allocator);
    }
    pub fn activate(self: *Self, id: u32) !void {
        try self.check();
        const handle = self.getHandler(id) orelse return;
        handle.activate(self.seat.?);
    }
    pub fn close(self: *Self, id: u32) !void {
        try self.check();
        const handle = self.getHandler(id) orelse return;
        handle.close();
    }
    pub fn setMaximized(self: *Self, id: u32, maximized: bool) !void {
        try self.check();
        const handle = self.getHandler(id) orelse return;
        if (maximized) {
            handle.setMaximized();
        } else {
            handle.unsetMaximized();
        }
    }
    pub fn setMinimized(self: *Self, id: u32, minimized: bool) !void {
        try self.check();
        const handle = self.getHandler(id) orelse return;
        if (minimized) {
            handle.setMinimized();
        } else {
            handle.unsetMinimized();
        }
    }
    pub fn setFullscreen(self: *Self, id: u32, fullscreen: bool) !void {
        try self.check();
        const handle = self.getHandler(id) orelse return;
        if (fullscreen) {
            handle.setFullscreen(null);
        } else {
            handle.unsetFullscreen();
        }
    }
};

fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, ctx: *Manager) void {
    const mem = std.mem;
    switch (event) {
        .global => |global| {
            if (mem.orderZ(u8, global.interface, ForeignToplevelManager.interface.name) == .eq) {
                ctx.foreignToplevelManager = registry.bind(global.name, ForeignToplevelManager, 3) catch return;
            } else if (mem.orderZ(u8, global.interface, wl.Seat.interface.name) == .eq) {
                ctx.seat = registry.bind(global.name, wl.Seat, 9) catch return;
            }
        },
        .global_remove => |global| {
            if (global.name == ctx.foreignToplevelManager.?.getId()) {
                ctx.foreignToplevelManager = null;
            } else if (global.name == ctx.seat.?.getId()) {
                ctx.seat = null;
            }
        },
    }
}

test "foreign-toplevel" {
    const allocator = std.testing.allocator;
    const manager = try Manager.init(allocator, .{});
    defer manager.deinit();

    const glib = @import("glib");
    _ = glib.idleAdd(@ptrCast(&struct {
        fn f(data: ?*anyopaque) callconv(.C) c_int {
            const m: *Manager = @ptrCast(@alignCast(data));
            const toplevels = m.list(allocator) catch unreachable;
            allocator.free(toplevels);
            if (toplevels.len == 0) return 1;
            return 0;
        }
    }.f), @ptrCast(manager));
    common.timeoutMainLoop(100);
}
