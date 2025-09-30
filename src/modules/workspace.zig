const std = @import("std");
const modules = @import("root.zig");
const Args = modules.Args;
const Context = modules.Context;
const InitContext = modules.InitContext;
const Registry = modules.Registry;
const Allocator = std.mem.Allocator;
const App = @import("../app.zig").App;
const WorkspaceManager = @import("wayland").Workspace;
pub const Workspace = struct {
    const Self = @This();
    allocator: Allocator,
    app: *App,
    manager: ?*WorkspaceManager.Manager,
    pub fn init(ctx: InitContext) !*Self {
        const self = try ctx.allocator.create(Self);
        const allocator = ctx.allocator;
        self.allocator = allocator;
        self.app = ctx.app;
        self.manager = null;
        return self;
    }
    fn setup(self: *Self) !void {
        if (self.manager == null) {
            self.manager = try WorkspaceManager.Manager.init(self.allocator, .{
                .userdata = @ptrCast(self),
                .groupAdded = @ptrCast(&onGroupAdded),
                .groupRemoved = @ptrCast(&onGroupRemoved),
                .groupEnter = @ptrCast(&onGroupEnter),
                .groupLeave = @ptrCast(&onGroupLeave),
                .groupWorkspaceEnter = @ptrCast(&onGroupWorkspaceEnter),
                .groupWorkspaceLeave = @ptrCast(&onGroupWorkspaceLeave),
                .workspaceChanged = @ptrCast(&onWorkspaceChanged),
                .workspaceAdded = @ptrCast(&onWorkspaceAdded),
                .workspaceRemoved = @ptrCast(&onWorkspaceRemoved),
            });
            // wait for the registry to be ready
            _ = self.manager.?.display.roundtrip();
        }
    }
    pub fn eventStart(self: *Self) !void {
        try self.setup();
    }
    pub fn eventStop(self: *Self) !void {
        if (self.manager) |m| {
            m.deinit();
            self.manager = null;
        }
    }
    pub fn deinit(self: *Self, allocator: Allocator) void {
        if (self.manager) |m| m.deinit();
        allocator.destroy(self);
    }
    pub fn register() Registry(Self) {
        return .{
            .exports = &.{
                .{ "groups", groups },
                .{ "getGroup", getGroup },
                .{ "createWorkspace", createWorkspace },
                .{ "getWorkspace", getWorkspace },
                .{ "activate", activate },
                .{ "deactivate", deactivate },
                .{ "assign", assign },
                .{ "remove", remove },
                .{ "list", list },
            },
            .events = &.{
                .@"workspace.workspace-changed",
                .@"workspace.workspace-added",
                .@"workspace.workspace-removed",
                .@"workspace.group-enter",
                .@"workspace.group-leave",
                .@"workspace.group-workspace-enter",
                .@"workspace.group-workspace-leave",
            },
        };
    }
    fn onGroupAdded(self: *Self, group: WorkspaceManager.WorkspaceGroup) void {
        self.app.emitEventUseSocket(.@"workspace.group-added", group);
    }
    fn onGroupRemoved(self: *Self, group: WorkspaceManager.WorkspaceGroup) void {
        self.app.emitEventUseSocket(.@"workspace.group-removed", group);
    }
    fn onGroupEnter(self: *Self, group: WorkspaceManager.WorkspaceGroup) void {
        self.app.emitEventUseSocket(.@"workspace.group-enter", group);
    }
    fn onGroupLeave(self: *Self, group: WorkspaceManager.WorkspaceGroup) void {
        self.app.emitEventUseSocket(.@"workspace.group-leave", group);
    }
    fn onGroupWorkspaceEnter(self: *Self, group: WorkspaceManager.WorkspaceGroup, workspace: WorkspaceManager.Workspace) void {
        self.app.emitEventUseSocket(.@"workspace.group-workspace-enter", .{
            .group = group,
            .workspace = workspace,
        });
    }
    fn onGroupWorkspaceLeave(self: *Self, group: WorkspaceManager.WorkspaceGroup, workspace: WorkspaceManager.Workspace) void {
        self.app.emitEventUseSocket(.@"workspace.group-workspace-leave", .{
            .group = group,
            .workspace = workspace,
        });
    }
    fn onWorkspaceChanged(self: *Self, workspace: WorkspaceManager.Workspace) void {
        self.app.emitEventUseSocket(.@"workspace.workspace-changed", workspace);
    }
    fn onWorkspaceAdded(self: *Self, workspace: WorkspaceManager.Workspace) void {
        self.app.emitEventUseSocket(.@"workspace.workspace-added", workspace);
    }
    fn onWorkspaceRemoved(self: *Self, workspace: WorkspaceManager.Workspace) void {
        self.app.emitEventUseSocket(.@"workspace.workspace-removed", workspace);
    }
    pub fn groups(self: *Self, ctx: *Context) !void {
        try self.setup();
        const manager = self.manager.?;
        const groups_ = try manager.groups(self.allocator);
        defer self.allocator.free(groups_);
        defer for (groups_) |group| group.deinit(self.allocator);
        ctx.commit(groups_);
    }
    pub fn getGroup(self: *Self, ctx: *Context) !void {
        try self.setup();
        const id = try ctx.args.uInteger(0);
        const manager = self.manager.?;
        const group = try manager.getGroup(self.allocator, @intCast(id));
        defer group.deinit(self.allocator);
        ctx.commit(group);
    }
    pub fn createWorkspace(self: *Self, ctx: *Context) !void {
        try self.setup();
        const group = try ctx.args.uInteger(0);
        const name = try ctx.args.string(1);
        const manager = self.manager.?;
        const name_ = try self.allocator.dupeZ(u8, name);
        defer self.allocator.free(name_);
        try manager.createWorkspace(@intCast(group), name_);
    }
    pub fn getWorkspace(self: *Self, ctx: *Context) !void {
        try self.setup();
        const id = try ctx.args.uInteger(0);
        const manager = self.manager.?;
        const workspace = try manager.getWorkspace(@intCast(id));
        ctx.commit(workspace);
    }
    pub fn list(self: *Self, ctx: *Context) !void {
        try self.setup();
        const manager = self.manager.?;
        const items = try manager.list(self.allocator);
        defer self.allocator.free(items);
        ctx.commit(items);
    }
    pub fn activate(self: *Self, ctx: *Context) !void {
        const id = try ctx.args.uInteger(0);
        try self.setup();
        const manager = self.manager.?;
        try manager.activate(@intCast(id));
    }
    pub fn deactivate(self: *Self, ctx: *Context) !void {
        const id = try ctx.args.uInteger(0);
        try self.setup();
        const manager = self.manager.?;
        try manager.deactivate(@intCast(id));
    }
    pub fn assign(self: *Self, ctx: *Context) !void {
        const id = try ctx.args.uInteger(0);
        const group = try ctx.args.uInteger(1);
        try self.setup();
        const manager = self.manager.?;
        try manager.assign(@intCast(id), @intCast(group));
    }
    pub fn remove(self: *Self, ctx: *Context) !void {
        const id = try ctx.args.uInteger(0);
        try self.setup();
        const manager = self.manager.?;
        try manager.remove(@intCast(id));
    }
};
