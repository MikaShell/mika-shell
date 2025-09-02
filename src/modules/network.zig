const App = @import("../app.zig").App;
const std = @import("std");
const modules = @import("root.zig");
const Args = modules.Args;
const InitContext = modules.InitContext;
const Context = modules.Context;
const Registry = modules.Registry;
const Allocator = std.mem.Allocator;
const networkManager = @import("../lib/network.zig");
const dbus = @import("dbus");
pub const Network = struct {
    const Self = @This();
    allocator: Allocator,
    nm: networkManager.Network,
    pub fn init(ctx: InitContext) !*Self {
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
        return .{
            .exports = &.{
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
            },
        };
    }
    pub fn getDevices(self: *Self, ctx: *Context) !void {
        const devices = try self.nm.getDevices(self.allocator);
        defer self.allocator.free(devices);
        defer for (devices) |device| device.deinit(self.allocator);
        ctx.commit(devices);
    }
    pub fn getState(self: *Self, ctx: *Context) !void {
        ctx.commit(try self.nm.getState());
    }
    pub fn isEnabled(self: *Self, ctx: *Context) !void {
        ctx.commit(try self.nm.isEnabled());
    }
    pub fn enable(self: *Self, _: *Context) !void {
        try self.nm.enable();
    }
    pub fn disable(self: *Self, _: *Context) !void {
        try self.nm.disable();
    }
    pub fn getConnections(self: *Self, ctx: *Context) !void {
        const connections = try self.nm.getConnections(self.allocator);
        defer self.allocator.free(connections);
        defer for (connections) |c| c.deinit(self.allocator);
        ctx.commit(connections);
    }
    pub fn getPrimaryConnection(self: *Self, ctx: *Context) !void {
        const connection = try self.nm.getPrimaryConnection(self.allocator);
        if (connection) |c| {
            defer c.deinit(self.allocator);
            ctx.commit(c);
        } else {
            ctx.commit(null);
        }
    }
    pub fn getActiveConnections(self: *Self, ctx: *Context) !void {
        const connections = try self.nm.getActiveConnections(self.allocator);
        defer self.allocator.free(connections);
        defer for (connections) |c| c.deinit(self.allocator);
        ctx.commit(connections);
    }
    pub fn getWirelessPsk(self: *Self, ctx: *Context) !void {
        const path = try ctx.args.string(0);
        const psk = try self.nm.getWirelessPsk(self.allocator, path);
        defer if (psk) |p| self.allocator.free(p);
        ctx.commit(psk);
    }
    pub fn activateConnection(self: *Self, ctx: *Context) !void {
        const connection = try ctx.args.string(0);
        const device = try ctx.args.string(1);
        const specific_object = try ctx.args.string(2);
        const path = try self.nm.activateConnection(self.allocator, connection, device, specific_object);
        defer self.allocator.free(path);
        ctx.commit(path);
    }
    pub fn deactivateConnection(self: *Self, ctx: *Context) !void {
        const connection = try ctx.args.string(0);
        try self.nm.deactivateConnection(connection);
    }
    pub fn checkConnectivity(self: *Self, ctx: *Context) !void {
        ctx.commit(try self.nm.checkConnectivity());
    }
    pub fn getWirelessActiveAccessPoint(self: *Self, ctx: *Context) !void {
        const device = try ctx.args.string(0);
        const ap = try self.nm.getWirelessActiveAccessPoint(self.allocator, device);
        defer if (ap) |a| a.deinit(self.allocator);
        ctx.commit(ap);
    }
    pub fn getWirelessAccessPoints(self: *Self, ctx: *Context) !void {
        const device = try ctx.args.string(0);
        const aps = try self.nm.getWirelessAccessPoints(self.allocator, device);
        defer self.allocator.free(aps);
        defer for (aps) |ap| ap.deinit(self.allocator);
        ctx.commit(aps);
    }
    pub fn wirelessRequestScan(self: *Self, ctx: *Context) !void {
        const device = try ctx.args.string(0);
        try self.nm.wirelessRequestScan(device);
    }
};
