const App = @import("../app.zig").App;
const std = @import("std");
const modules = @import("modules.zig");
const Args = modules.Args;
const Result = modules.Result;
const Context = modules.Context;
const Registry = modules.Registry;
const Allocator = std.mem.Allocator;
const networkManager = @import("../lib/network.zig");
const dbus = @import("dbus");
pub const Network = struct {
    const Self = @This();
    allocator: Allocator,
    nm: networkManager.Network,
    pub fn init(ctx: Context) !*Self {
        const self = try ctx.allocator.create(Self);
        self.allocator = ctx.allocator;
        self.nm = try networkManager.Network.init(ctx.systemBus);
        return self;
    }
    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.nm.deinit();
        allocator.destroy(self);
    }
    pub fn register() Registry(Self) {
        return &.{
            .{ "getDevices", getDevices },
            .{ "getState", getState },
            .{ "isEnabled", isEnabled },
            .{ "enable", enable },
            .{ "disable", disable },
            .{ "getConnections", getConnections },
            .{ "getPrimaryConnection", getPrimaryConnection },
            .{ "getActiveConnections", getActiveConnections },
            .{ "getWirelessPsk", getWirelessPsk },
            .{ "activateConnection", activateConnection },
            .{ "deactivateConnection", deactivateConnection },
            .{ "checkConnectivity", checkConnectivity },
            .{ "getWirelessActiveAccessPoint", getWirelessActiveAccessPoint },
            .{ "getWirelessAccessPoints", getWirelessAccessPoints },
            .{ "wirelessRequestScan", wirelessRequestScan },
        };
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
    pub fn activateConnection(self: *Self, args: Args, result: *Result) !void {
        const connection = try args.string(1);
        const device = try args.string(2);
        const specific_object = try args.string(3);
        const path = try self.nm.activateConnection(self.allocator, connection, device, specific_object);
        defer self.allocator.free(path);
        result.commit(path);
    }
    pub fn deactivateConnection(self: *Self, args: Args, _: *Result) !void {
        const connection = try args.string(1);
        try self.nm.deactivateConnection(connection);
    }
    pub fn checkConnectivity(self: *Self, _: Args, result: *Result) !void {
        result.commit(try self.nm.checkConnectivity());
    }
    pub fn getWirelessActiveAccessPoint(self: *Self, args: Args, result: *Result) !void {
        const device = try args.string(1);
        const ap = try self.nm.getWirelessActiveAccessPoint(self.allocator, device);
        defer if (ap) |a| a.deinit(self.allocator);
        result.commit(ap);
    }
    pub fn getWirelessAccessPoints(self: *Self, args: Args, result: *Result) !void {
        const device = try args.string(1);
        const aps = try self.nm.getWirelessAccessPoints(self.allocator, device);
        defer self.allocator.free(aps);
        defer for (aps) |ap| ap.deinit(self.allocator);
        result.commit(aps);
    }
    pub fn wirelessRequestScan(self: *Self, args: Args, _: *Result) !void {
        const device = try args.string(1);
        try self.nm.wirelessRequestScan(device);
    }
};
