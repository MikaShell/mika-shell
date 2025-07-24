const std = @import("std");
const modules = @import("modules.zig");
const Args = modules.Args;
const Result = modules.Result;
const Context = modules.Context;
const Registry = modules.Registry;
const Allocator = std.mem.Allocator;
const App = @import("../app.zig").App;
pub const Emitter = struct {
    const Self = @This();
    allocator: Allocator,
    app: *App,
    subscriber: std.StringHashMap(std.ArrayList(u64)),
    pub fn init(app: *App, allocator: Allocator) !*Self {
        const self = try allocator.create(Self);
        self.allocator = allocator;
        self.app = app;
        self.subscriber = std.StringHashMap(std.ArrayList(u64)).init(allocator);
        return self;
    }
    pub fn deinit(self: *Self) void {
        var it = self.subscriber.iterator();
        while (it.next()) |kv| {
            self.allocator.free(kv.key_ptr.*);
            kv.value_ptr.deinit();
        }
        self.subscriber.deinit();
        self.allocator.destroy(self);
    }
    pub fn subscribe(
        self: *Self,
        args: Args,
        event: []const u8,
    ) !void {
        const event_ = try self.allocator.dupe(u8, event);
        errdefer self.allocator.free(event_);
        const id = args.uInteger(0) catch unreachable;
        const list = try self.subscriber.getOrPut(event_);
        if (!list.found_existing) {
            list.value_ptr.* = std.ArrayList(u64).init(self.allocator);
        }
        try list.value_ptr.append(id);
    }
    fn unsubscribeAll_(self: *Self, id: u64) void {
        var it = self.subscriber.iterator();
        while (it.next()) |kv| {
            const list = kv.value_ptr;
            for (list.items, 0..) |item, i| {
                if (item == id) {
                    _ = list.swapRemove(i);
                    break;
                }
            }
            if (list.items.len == 0) {
                list.deinit();
                _ = self.subscriber.remove(kv.key_ptr.*);
                self.allocator.free(kv.key_ptr.*);
            }
        }
    }
    fn unsubscribe_(self: *Self, event: []const u8, id: u64) void {
        const list = self.subscriber.getPtr(event) orelse return;
        for (list.items, 0..) |item, i| {
            if (item == id) {
                _ = list.swapRemove(i);
                break;
            }
        }
        if (list.items.len == 0) {
            list.deinit();
            const key = self.subscriber.getKey(event).?;
            _ = self.subscriber.remove(key);
            self.allocator.free(key);
        }
    }
    pub fn unsubscribe(
        self: *Self,
        args: Args,
        event: []const u8,
    ) !void {
        const id = args.uInteger(0) catch unreachable;
        self.unsubscribe_(event, id);
    }
    pub fn emit(self: *Self, event: []const u8, data: anytype) void {
        const list = self.subscriber.get(event) orelse return;
        for (list.items) |id| {
            const ok = self.app.emitEventTo(id, event, data);
            if (!ok) self.unsubscribe_(event, id);
        }
    }
};
