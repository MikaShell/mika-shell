const foreignToplevel = @import("wayland").foreignToplevel;
const std = @import("std");
const Allocator = std.mem.Allocator;
var isInitialized = false;
pub const Item = struct {
    id: u32,
    title: []const u8,
    appId: []const u8,
    state: []State,
    pub fn deinit(self: Item, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
        allocator.free(self.appId);
        allocator.free(self.state);
    }
};

pub const State = foreignToplevel.State;
pub const Dock = struct {
    const Self = @This();
    allocator: Allocator,
    windows: std.AutoHashMap(u32, Item),
    userData: ?*anyopaque,
    onAdded: ?*const fn (?*anyopaque, Item) void = null,
    onChanged: ?*const fn (?*anyopaque, Item) void = null,
    onClosed: ?*const fn (?*anyopaque, u32) void = null,
    onEnter: ?*const fn (?*anyopaque, u32) void = null,
    onLeave: ?*const fn (?*anyopaque, u32) void = null,
    onActivated: ?*const fn (?*anyopaque, u32) void = null,
    pub fn init(allocator: Allocator, userData: ?*anyopaque) !*Self {
        if (isInitialized) return error.AlreadyInitialized;
        isInitialized = true;
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .userData = userData,
            .windows = std.AutoHashMap(u32, Item).init(allocator),
        };
        foreignToplevel.setUserData(self);
        foreignToplevel.Listener.onChanged = @ptrCast(&onChanged_);
        foreignToplevel.Listener.onClosed = @ptrCast(&onClosed_);
        foreignToplevel.Listener.onEnter = @ptrCast(&onEnter_);
        foreignToplevel.Listener.onLeave = @ptrCast(&onLeave_);
        return self;
    }
    pub fn deinit(self: *Self) void {
        foreignToplevel.Listener.onChanged = null;
        foreignToplevel.Listener.onClosed = null;
        foreignToplevel.Listener.onEnter = null;
        foreignToplevel.Listener.onLeave = null;
        foreignToplevel.setUserData(null);
        self.windows.deinit();
        self.allocator.destroy(self);
        isInitialized = false;
    }
    fn onChanged_(self: *Self, t: foreignToplevel.Toplevel) void {
        const isNew = !self.windows.contains(t.id);
        const w = Item{
            .id = t.id,
            .title = self.allocator.dupe(u8, t.title) catch unreachable,
            .appId = self.allocator.dupe(u8, t.appId) catch unreachable,
            .state = self.allocator.dupe(State, t.state) catch unreachable,
        };
        self.windows.put(t.id, w) catch unreachable;
        if (isNew) {
            if (self.onAdded) |onAdded| onAdded(self.userData, w);
        } else {
            if (self.onChanged) |onChanged| onChanged(self.userData, w);
            for (t.state) |state| {
                if (state == .activated) {
                    if (self.onActivated) |onActivated| onActivated(self.userData, t.id);
                }
            }
        }
    }
    fn onClosed_(self: *Self, id: u32) void {
        const w = self.windows.get(id) orelse unreachable;
        defer w.deinit(self.allocator);
        if (self.windows.remove(id)) {
            if (self.onClosed) |onClosed| onClosed(self.userData, id);
        }
    }
    fn onEnter_(self: *Self, id: u32) void {
        if (self.onEnter) |onEnter| onEnter(self.userData, id);
    }
    fn onLeave_(self: *Self, id: u32) void {
        if (self.onLeave) |onLeave| onLeave(self.userData, id);
    }
    pub fn list(self: *Self, allocator: Allocator) ![]Item {
        var items = std.ArrayList(Item).init(allocator);
        var it = self.windows.iterator();
        while (it.next()) |kv| {
            const value = kv.value_ptr.*;
            try items.append(.{
                .id = value.id,
                .appId = try allocator.dupe(u8, value.appId),
                .title = try allocator.dupe(u8, value.title),
                .state = try allocator.dupe(State, value.state),
            });
        }
        return try items.toOwnedSlice();
    }
};
pub fn activate(id: u32) void {
    foreignToplevel.activate(id);
}
pub fn close(id: u32) void {
    foreignToplevel.close(id);
}
pub fn setMaximized(id: u32, maximized: bool) void {
    foreignToplevel.setMaximized(id, maximized);
}
pub fn setMinimized(id: u32, minimized: bool) void {
    foreignToplevel.setMinimized(id, minimized);
}
pub fn setFullscreen(id: u32, fullscreen: bool) void {
    foreignToplevel.setFullscreen(id, fullscreen);
}
