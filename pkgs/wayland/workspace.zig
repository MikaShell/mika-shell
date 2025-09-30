const std = @import("std");
const Allocator = std.mem.Allocator;
const wayland = @import("zig-wayland");
const common = @import("common.zig");
const wl = wayland.client.wl;
const WorkspaceManager = wayland.client.ext.WorkspaceManagerV1;
const WorkspaceHandle = wayland.client.ext.WorkspaceHandleV1;
const WorkspaceGroupHandle = wayland.client.ext.WorkspaceGroupHandleV1;
pub const WorkspaceGroup = struct {
    id: u32,
    capabilities: WorkspaceGroupHandle.GroupCapabilities,
    workspaces: []u32,
    pub fn deinit(self: @This(), allocator: Allocator) void {
        allocator.free(self.workspaces);
    }
};
const WorkspaceGroupContext = struct {
    allocator: Allocator,
    handle: *WorkspaceGroupHandle,
    capabilities: WorkspaceGroupHandle.GroupCapabilities,
    workspaces: std.ArrayList(u32),
    fn init(allocator: Allocator, hande: *WorkspaceGroupHandle) WorkspaceGroupContext {
        return .{
            .allocator = allocator,
            .handle = hande,
            .capabilities = .{},
            .workspaces = std.ArrayList(u32){},
        };
    }
    fn deinit(self: *WorkspaceGroupContext) void {
        self.handle.destroy();
        self.workspaces.deinit(self.allocator);
    }
    fn make(self: *WorkspaceGroupContext, allocator: Allocator) !WorkspaceGroup {
        var workspaces = try self.workspaces.clone(allocator);
        return .{
            .id = self.handle.getId(),
            .capabilities = self.capabilities,
            .workspaces = try workspaces.toOwnedSlice(allocator),
        };
    }
};
pub const Workspace = struct {
    id: u32,
    workspaceId: ?[]const u8,
    name: []const u8,
    state: WorkspaceHandle.State,
    coordinates: []u32,
    capabilities: WorkspaceHandle.WorkspaceCapabilities,
};
const WorkspaceContext = struct {
    allocator: Allocator,
    handle: *WorkspaceHandle,
    workspaceId: ?[]const u8,
    name: []const u8,
    state: WorkspaceHandle.State,
    coordinates: []u32,
    capabilities: WorkspaceHandle.WorkspaceCapabilities,
    fn init(allocator: Allocator, handle: *WorkspaceHandle) WorkspaceContext {
        return .{
            .allocator = allocator,
            .handle = handle,
            .workspaceId = null,
            .name = "",
            .state = .{ .active = false, .hidden = false, .urgent = false },
            .coordinates = &.{},
            .capabilities = .{},
        };
    }
    fn deinit(self: *WorkspaceContext) void {
        if (self.workspaceId) |wid| self.allocator.free(wid);
        self.allocator.free(self.name);
        self.allocator.free(self.coordinates);
        self.handle.destroy();
    }
    fn make(self: *WorkspaceContext) Workspace {
        return .{
            .id = self.handle.getId(),
            .workspaceId = self.workspaceId,
            .name = self.name,
            .state = self.state,
            .coordinates = self.coordinates,
            .capabilities = self.capabilities,
        };
    }
};
const GroupHandleNode = struct {
    data: WorkspaceGroupContext,
    node: std.DoublyLinkedList.Node,
};
const HandleNode = struct {
    data: WorkspaceContext,
    node: std.DoublyLinkedList.Node,
};

pub const Manager = struct {
    const Self = @This();
    const Listener = struct {
        userdata: ?*anyopaque = null,
        groupAdded: ?*const fn (data: ?*anyopaque, group: WorkspaceGroup) void = null,
        groupRemoved: ?*const fn (data: ?*anyopaque, group: WorkspaceGroup) void = null,
        groupEnter: ?*const fn (data: ?*anyopaque, group: WorkspaceGroup) void = null,
        groupLeave: ?*const fn (data: ?*anyopaque, group: WorkspaceGroup) void = null,
        groupWorkspaceEnter: ?*const fn (data: ?*anyopaque, group: WorkspaceGroup, workspace: Workspace) void = null,
        groupWorkspaceLeave: ?*const fn (data: ?*anyopaque, group: WorkspaceGroup, workspace: Workspace) void = null,
        workspaceChanged: ?*const fn (data: ?*anyopaque, workspace: Workspace) void = null,
        workspaceAdded: ?*const fn (data: ?*anyopaque, workspace: Workspace) void = null,
        workspaceRemoved: ?*const fn (data: ?*anyopaque, workspace: Workspace) void = null,
    };
    allocator: Allocator,
    isReady: bool,
    workspaceManager: ?*WorkspaceManager,
    display: *wl.Display,
    glibWatch: common.GLibWatch,
    listener: Listener,
    groupHandles: std.DoublyLinkedList,
    handles: std.DoublyLinkedList,
    pub fn init(allocator: Allocator, listener: Listener) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.allocator = allocator;
        self.groupHandles = .{};
        self.handles = .{};
        self.workspaceManager = null;
        self.listener = listener;
        self.isReady = false;

        const display = try common.init(*Self, registryListener, self);
        errdefer display.disconnect();
        try self.check();

        self.display = display;
        self.workspaceManager.?.setListener(*Self, workspaceManagerListener, self);

        self.glibWatch = try common.withGLibMainLoop(display);
        return self;
    }
    pub fn deinit(self: *Self) void {
        if (self.workspaceManager) |m| {
            m.stop();
            _ = self.display.roundtrip();
        } else {
            self.destroy();
        }
        self.glibWatch.deinit();
        self.display.disconnect();
        self.allocator.destroy(self);
    }
    fn destroy(self: *Self) void {
        while (self.groupHandles.pop()) |node| {
            const handle: *GroupHandleNode = @fieldParentPtr("node", node);
            handle.data.deinit();
            self.allocator.destroy(handle);
        }
        while (self.handles.pop()) |node| {
            const handle: *HandleNode = @fieldParentPtr("node", node);
            handle.data.deinit();
            self.allocator.destroy(handle);
        }
        self.workspaceManager.?.destroy();
        self.workspaceManager = null;
    }
    fn check(self: *Self) !void {
        if (self.workspaceManager == null) return common.ErrNoAvarible;
    }
    pub fn list(self: *Self, allocator: Allocator) ![]Workspace {
        try self.check();
        var result = std.ArrayList(Workspace){};
        defer result.deinit(allocator);
        var it = self.handles.first;
        while (it) |node| {
            const handleNode: *HandleNode = @fieldParentPtr("node", node);
            result.append(allocator, handleNode.data.make()) catch unreachable;
            it = node.next;
        }
        return result.toOwnedSlice(allocator);
    }
    pub fn groups(self: *Self, allocator: Allocator) ![]WorkspaceGroup {
        try self.check();
        var result = std.ArrayList(WorkspaceGroup){};
        defer result.deinit(allocator);
        var it = self.groupHandles.first;
        while (it) |node| {
            const handleNode: *GroupHandleNode = @fieldParentPtr("node", node);
            try result.append(allocator, try handleNode.data.make(allocator));
            it = node.next;
        }
        return result.toOwnedSlice(allocator);
    }
    pub fn getWorkspace(self: *Self, workspace: u32) !Workspace {
        var it = self.handles.first;
        while (it) |node| {
            const handleNode: *HandleNode = @fieldParentPtr("node", node);
            if (handleNode.data.handle.getId() == workspace) {
                return handleNode.data.make();
            }
            it = node.next;
        }
        return error.WorkspaceNotFound;
    }
    /// need to free the returned group, use `WorkspaceGroup.deinit(allocator)`
    pub fn getGroup(self: *Self, allocator: Allocator, group: u32) !WorkspaceGroup {
        var it = self.groupHandles.first;
        while (it) |node| {
            const handleNode: *GroupHandleNode = @fieldParentPtr("node", node);
            if (handleNode.data.handle.getId() == group) {
                return try handleNode.data.make(allocator);
            }
            it = node.next;
        }
        return error.GroupNotFound;
    }
    pub fn createWorkspace(self: *Self, group: u32, name: [:0]const u8) !void {
        try self.check();
        var it = self.groupHandles.first;
        while (it) |node| {
            const handleNode: *GroupHandleNode = @fieldParentPtr("node", node);
            const group_ = handleNode.data;
            if (group_.handle.getId() == group) {
                if (group_.capabilities.create_workspace == false) {
                    return error.NotAllowed;
                }
                group_.handle.createWorkspace(name.ptr);
                _ = self.display.flush();
                return;
            }
            it = node.next;
        }
        return error.GroupNotFound;
    }
    pub fn activate(self: *Self, workspace: u32) !void {
        try self.check();
        var it = self.handles.first;
        while (it) |node| {
            const handleNode: *HandleNode = @fieldParentPtr("node", node);
            if (handleNode.data.handle.getId() == workspace) {
                if (handleNode.data.capabilities.activate == false) {
                    return error.NotAllowed;
                }
                handleNode.data.handle.activate();
                _ = self.display.flush();
                return;
            }
            it = node.next;
        }
        return error.WorkspaceNotFound;
    }
    pub fn deactivate(self: *Self, workspace: u32) !void {
        try self.check();
        var it = self.handles.first;
        while (it) |node| {
            const handleNode: *HandleNode = @fieldParentPtr("node", node);
            if (handleNode.data.handle.getId() == workspace) {
                if (handleNode.data.capabilities.deactivate == false) {
                    return error.NotAllowed;
                }
                handleNode.data.handle.deactivate();
                _ = self.display.flush();
                return;
            }
            it = node.next;
        }
        return error.WorkspaceNotFound;
    }
    pub fn assign(self: *Self, workspace: u32, group: u32) !void {
        try self.check();
        var it = self.handles.first;
        while (it) |node| {
            const handleNode: *HandleNode = @fieldParentPtr("node", node);
            if (handleNode.data.handle.getId() == workspace) {
                if (handleNode.data.capabilities.assign == false) {
                    return error.NotAllowed;
                }
                var it2 = self.groupHandles.first;
                while (it2) |node2| {
                    const groupNode: *GroupHandleNode = @fieldParentPtr("node", node2);
                    if (groupNode.data.handle.getId() == group) {
                        handleNode.data.handle.assign(groupNode.data.handle);
                        _ = self.display.flush();
                        return;
                    }
                    it2 = node2.next;
                }
                return error.GroupNotFound;
            }
            it = node.next;
        }
        return error.WorkspaceNotFound;
    }
    pub fn remove(self: *Self, workspace: u32) !void {
        try self.check();
        var it = self.handles.first;
        while (it) |node| {
            const handleNode: *HandleNode = @fieldParentPtr("node", node);
            if (handleNode.data.handle.getId() == workspace) {
                if (handleNode.data.capabilities.remove == false) {
                    return error.NotAllowed;
                }
                handleNode.data.handle.remove();
                _ = self.display.flush();
                return;
            }
            it = node.next;
        }
        return error.WorkspaceNotFound;
    }
};
fn workspaceManagerListener(_: *WorkspaceManager, event: WorkspaceManager.Event, ctx: *Manager) void {
    const allocator = ctx.allocator;
    switch (event) {
        .workspace => |e| {
            const workspace = allocator.create(HandleNode) catch unreachable;
            workspace.data = .init(allocator, e.workspace);
            workspace.node = .{};
            e.workspace.setListener(*Manager, workspaceListener, ctx);
            ctx.handles.append(&workspace.node);
            if (!ctx.isReady) return;
            if (ctx.listener.workspaceAdded) |cb| cb(ctx.listener.userdata, workspace.data.make());
        },
        .workspace_group => |e| {
            const handle = allocator.create(GroupHandleNode) catch unreachable;
            handle.data = .init(allocator, e.workspace_group);
            handle.node = .{};
            e.workspace_group.setListener(*Manager, workspaceGroupListener, ctx);
            ctx.groupHandles.append(&handle.node);
            if (!ctx.isReady) return;
            const group = handle.data.make(allocator) catch unreachable;
            defer group.deinit(allocator);
            if (ctx.listener.groupAdded) |cb| cb(ctx.listener.userdata, group);
        },
        .done => {
            ctx.isReady = true;
        },
        .finished => {
            ctx.destroy();
        },
    }
}
fn workspaceGroupListener(h: *WorkspaceGroupHandle, event: WorkspaceGroupHandle.Event, manager: *Manager) void {
    const node = blk: {
        var it = manager.groupHandles.first;
        while (it) |node| {
            const handleNode: *GroupHandleNode = @fieldParentPtr("node", node);
            if (handleNode.data.handle == h) {
                break :blk handleNode;
            }
            it = node.next;
        }
        unreachable;
    };
    const ctx = &node.data;
    switch (event) {
        .capabilities => |e| {
            ctx.capabilities = e.capabilities;
        },
        .removed => {
            manager.groupHandles.remove(&node.node);
            if (manager.isReady) {
                const group = ctx.make(manager.allocator) catch unreachable;
                defer group.deinit(manager.allocator);
                if (manager.listener.groupRemoved) |cb| cb(manager.listener.userdata, group);
            }
            manager.allocator.destroy(node);
        },
        .output_enter => {
            var group = ctx.make(manager.allocator) catch unreachable;
            defer group.deinit(manager.allocator);
            if (!manager.isReady) return;
            if (manager.listener.groupEnter) |cb| cb(manager.listener.userdata, group);
        },
        .output_leave => {
            var group = ctx.make(manager.allocator) catch unreachable;
            defer group.deinit(manager.allocator);
            if (!manager.isReady) return;
            if (manager.listener.groupLeave) |cb| cb(manager.listener.userdata, group);
        },
        .workspace_enter => |e| {
            ctx.workspaces.append(ctx.allocator, h.getId()) catch unreachable;
            var group = ctx.make(manager.allocator) catch unreachable;
            defer group.deinit(manager.allocator);
            const workspace = blk: {
                var it = manager.handles.first;
                while (it) |n| {
                    const handleNode: *HandleNode = @fieldParentPtr("node", n);
                    if (handleNode.data.handle == e.workspace) {
                        break :blk handleNode.data.make();
                    }
                    it = n.next;
                }
                unreachable;
            };
            if (!manager.isReady) return;
            if (manager.listener.groupWorkspaceEnter) |cb| cb(manager.listener.userdata, group, workspace);
        },
        .workspace_leave => |e| {
            {
                const target = h.getId();
                for (ctx.workspaces.items) |id| {
                    if (id == target) {
                        _ = ctx.workspaces.swapRemove(id);
                        break;
                    }
                }
                unreachable;
            }

            var group = ctx.make(manager.allocator) catch unreachable;
            defer group.deinit(manager.allocator);
            const workspace = blk: {
                var it = manager.handles.first;
                while (it) |n| {
                    const handleNode: *HandleNode = @fieldParentPtr("node", n);
                    if (handleNode.data.handle == e.workspace) {
                        break :blk handleNode.data.make();
                    }
                    it = n.next;
                }
                unreachable;
            };
            if (!manager.isReady) return;
            if (manager.listener.groupWorkspaceLeave) |cb| cb(manager.listener.userdata, group, workspace);
        },
    }
}
fn workspaceListener(h: *WorkspaceHandle, event: WorkspaceHandle.Event, manager: *Manager) void {
    const span = std.mem.span;
    const node = blk: {
        var it = manager.handles.first;
        while (it) |node| {
            const handleNode: *HandleNode = @fieldParentPtr("node", node);
            if (handleNode.data.handle == h) {
                break :blk handleNode;
            }
            it = node.next;
        }
        unreachable;
    };
    const ctx = &node.data;
    const allocator = ctx.allocator;

    switch (event) {
        .id => |e| {
            if (ctx.workspaceId) |wid| allocator.free(wid);
            ctx.workspaceId = allocator.dupe(u8, span(e.id)) catch unreachable;
        },
        .name => |e| {
            allocator.free(ctx.name);
            ctx.name = allocator.dupe(u8, span(e.name)) catch unreachable;
        },
        .state => |e| {
            ctx.state = e.state;
        },
        .coordinates => |e| {
            allocator.free(ctx.coordinates);
            ctx.coordinates = allocator.dupe(u32, e.coordinates.slice(u32)) catch unreachable;
        },
        .capabilities => |e| {
            ctx.capabilities = e.capabilities;
        },
        .removed => {
            manager.handles.remove(&node.node);
            node.data.deinit();
            if (manager.isReady) {
                if (manager.listener.workspaceRemoved) |cb| cb(manager.listener.userdata, node.data.make());
            }
            manager.allocator.destroy(node);
            return;
        },
    }
    if (!manager.isReady) return;
    if (manager.listener.workspaceChanged) |cb| cb(manager.listener.userdata, ctx.make());
}
fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, ctx: *Manager) void {
    const mem = std.mem;
    switch (event) {
        .global => |global| {
            if (mem.orderZ(u8, global.interface, WorkspaceManager.interface.name) == .eq) {
                ctx.workspaceManager = registry.bind(global.name, WorkspaceManager, 1) catch return;
                std.debug.print("found workspace manager\n", .{});
            }
        },
        .global_remove => @panic("global_remove not implemented"),
    }
}
test "workspace" {
    const allocator = std.testing.allocator;
    const manager = try Manager.init(allocator, .{ .groupWorkspaceEnter = struct {
        fn f(group: WorkspaceGroup, workspace: Workspace, _: ?*anyopaque) void {
            std.debug.print("group: {any}, workspace: {d}\n", .{ group.workspaces, workspace.id });
        }
    }.f });
    defer manager.deinit();

    const glib = @import("glib");
    _ = glib.idleAdd(@ptrCast(&struct {
        fn f(data: ?*anyopaque) callconv(.c) c_int {
            const m: *Manager = @ptrCast(@alignCast(data));
            const ws = m.list(allocator) catch unreachable;
            for (ws) |w| {
                std.debug.print("id: {d}\nname: {s}\ncoor: {any}\n", .{ w.id, w.name, w.coordinates });
            }
            allocator.free(ws);
            if (ws.len == 0) return 1;
            return 0;
        }
    }.f), @ptrCast(manager));
    common.timeoutMainLoop(5_000);
}
