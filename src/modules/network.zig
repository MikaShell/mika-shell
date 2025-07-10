const modules = @import("modules.zig");
const Args = modules.Args;
const Result = modules.Result;
const App = @import("../app.zig").App;
const std = @import("std");
const Allocator = std.mem.Allocator;
const networkManager = @import("../lib/network.zig");
const dbus = @import("dbus");
pub const Network = struct {
    const Self = @This();
    allocator: Allocator,
    nm: networkManager.Network,
    pub fn init(allocator: Allocator, bus: *dbus.Bus) !*Self {
        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .nm = try networkManager.Network.init(bus),
        };
        return self;
    }
    pub fn deinit(self: *Self) void {
        self.nm.deinit();
        self.allocator.destroy(self);
    }
    pub fn getDevices(self: *Self, _: Args, result: *Result) !void {
        const devices = try self.nm.getDevices(self.allocator);
        defer self.allocator.free(devices);
        defer for (devices) |device| device.deinit(self.allocator);
        result.commit(devices);
    }
    pub fn getState(self: *Self, _: Args, result: *Result) !void {
        result.commit(try self.nm.getState());
    }
    pub fn isEnabled(self: *Self, _: Args, result: *Result) !void {
        result.commit(try self.nm.isEnabled());
    }
    pub fn enable(self: *Self, _: Args, _: *Result) !void {
        try self.nm.enable();
    }
    pub fn disable(self: *Self, _: Args, _: *Result) !void {
        try self.nm.disable();
    }
    pub fn getConnections(self: *Self, _: Args, result: *Result) !void {
        const connections = try self.nm.getConnections(self.allocator);
        defer self.allocator.free(connections);
        defer for (connections) |c| c.deinit(self.allocator);
        result.commit(connections);
    }
    pub fn getPrimaryConnection(self: *Self, _: Args, result: *Result) !void {
        const connection = try self.nm.getPrimaryConnection(self.allocator);
        if (connection) |c| {
            defer c.deinit(self.allocator);
            result.commit(c);
        } else {
            result.commit(null);
        }
    }
    pub fn getActiveConnections(self: *Self, _: Args, result: *Result) !void {
        const connections = try self.nm.getActiveConnections(self.allocator);
        defer self.allocator.free(connections);
        defer for (connections) |c| c.deinit(self.allocator);
        result.commit(connections);
    }
    pub fn getWirelessPsk(self: *Self, args: Args, result: *Result) !void {
        const path = try args.string(1);
        const psk = try self.nm.getWirelessPsk(self.allocator, path);
        defer if (psk) |p| self.allocator.free(p);
        result.commit(psk);
    }
};
