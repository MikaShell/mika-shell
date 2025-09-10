const dbus = @import("dbus");
const glib = @import("glib");
const std = @import("std");
const defines = @import("network/defines.zig");
const helper = @import("network/helper.zig");
const structs = @import("network/structs.zig");
const Allocator = std.mem.Allocator;
const testing = std.testing;
// https://networkmanager.pages.freedesktop.org/NetworkManager/NetworkManager/nm-settings-nmcli.html?utm_source=chatgpt.com
pub const Network = struct {
    const Self = @This();
    bus: *dbus.Bus,
    manager: helper.DBusHelper,
    settings: helper.DBusHelper,
    pub fn init(bus: *dbus.Bus) !Self {
        var self: Self = undefined;
        self.bus = bus;
        self.manager = try helper.DBusHelper.init(bus, "/org/freedesktop/NetworkManager", "org.freedesktop.NetworkManager");
        errdefer self.manager.deinit();
        self.settings = try helper.DBusHelper.init(bus, "/org/freedesktop/NetworkManager/Settings", "org.freedesktop.NetworkManager.Settings");
        errdefer self.settings.deinit();
        return self;
    }
    pub fn deinit(self: Self) void {
        self.manager.deinit();
    }
    pub fn getDevices(self: Self, allocator: Allocator) ![]structs.Device {
        const result = try self.manager.get("Devices", dbus.Array(dbus.ObjectPath));
        defer result.deinit();
        var ds = std.ArrayList(structs.Device){};
        defer ds.deinit(allocator);
        for (result.value) |devicePath| {
            const d = try structs.Device.init(allocator, self.bus, devicePath);
            errdefer d.deinit(allocator);
            if (d.type == .ethernet or d.type == .wifi) {
                try ds.append(allocator, d);
            } else {
                d.deinit(allocator);
            }
        }
        return try ds.toOwnedSlice(allocator);
    }
    pub fn getState(self: Self) !defines.State {
        return @enumFromInt(try self.manager.getBasic("State", dbus.UInt32));
    }
    pub fn isEnabled(self: Self) !bool {
        return try self.manager.getBasic("NetworkingEnabled", dbus.Boolean);
    }
    pub fn enable(self: Network) !void {
        const result = try self.manager.call("Enable", .{dbus.Boolean}, .{true});
        result.deinit();
    }
    pub fn disable(self: Network) !void {
        const result = try self.manager.call("Enable", .{dbus.Boolean}, .{false});
        result.deinit();
    }
    pub fn getConnections(self: Self, allocator: Allocator) ![]structs.Connection {
        const result = try self.settings.call("ListConnections", .{}, .{});
        defer result.deinit();
        var cs = std.ArrayList(structs.Connection){};
        defer cs.deinit(allocator);
        for (result.next(dbus.Array(dbus.ObjectPath))) |path| {
            const c = try structs.Connection.init(allocator, self.bus, path);
            errdefer c.deinit(allocator);
            if (c.type == .@"802-11-wireless" or c.type == .@"802-3-ethernet") {
                try cs.append(allocator, c);
            } else {
                c.deinit(allocator);
            }
        }
        return try cs.toOwnedSlice(allocator);
    }
    pub fn getPrimaryConnection(self: Self, allocator: Allocator) !?structs.ActiveConnection {
        const path = try self.manager.getAlloc(allocator, "PrimaryConnection", dbus.ObjectPath);
        defer allocator.free(path);

        if (helper.isValidPath(path)) {
            const c = try structs.ActiveConnection.init(allocator, self.bus, path);
            errdefer c.deinit(allocator);
            return c;
        } else {
            return null;
        }
    }
    pub fn getActiveConnections(self: Self, allocator: Allocator) ![]structs.ActiveConnection {
        const result = try self.manager.get("ActiveConnections", dbus.Array(dbus.ObjectPath));
        defer result.deinit();
        var acs = std.ArrayList(structs.ActiveConnection){};
        defer acs.deinit(allocator);
        for (result.value) |path| {
            const ac = try structs.ActiveConnection.init(allocator, self.bus, path);
            errdefer ac.deinit(allocator);
            if (ac.connection.type == .@"802-11-wireless" or ac.connection.type == .@"802-3-ethernet") {
                try acs.append(allocator, ac);
            } else {
                ac.deinit(allocator);
            }
        }
        return try acs.toOwnedSlice(allocator);
    }
    /// path is Connection.dbusPath
    pub fn getWirelessPsk(self: Self, allocator: Allocator, path: []const u8) !?[]const u8 {
        if (!helper.isValidPath(path)) return null;
        if (!std.mem.startsWith(u8, path, "/org/freedesktop/NetworkManager/Settings/")) {
            return error.IsNotSettingsConnectionPath;
        }
        const conn = try helper.DBusHelper.init(self.bus, path, "org.freedesktop.NetworkManager.Settings.Connection");
        defer conn.deinit();
        const result = try conn.call(
            "GetSecrets",
            .{dbus.String},
            .{"802-11-wireless-security"},
        );
        defer result.deinit();
        const secrets = result.next(dbus.Dict(
            dbus.String,
            dbus.Dict(
                dbus.String,
                dbus.AnyVariant,
            ),
        ));
        const eql = std.mem.eql;
        for (secrets) |secret| {
            if (!eql(u8, secret.key, "802-11-wireless-security")) continue;
            for (secret.value) |sec| {
                const key = sec.key;
                if (eql(u8, key, "psk")) {
                    const psk = sec.value.as(dbus.String);
                    return try allocator.dupe(u8, psk);
                }
            }
        }
        return null;
    }
    pub fn activateConnection(self: Self, allocator: Allocator, connection: []const u8, device: []const u8, specific_object: []const u8) ![]const u8 {
        const result = try self.manager.call(
            "ActivateConnection",
            .{
                dbus.ObjectPath,
                dbus.ObjectPath,
                dbus.ObjectPath,
            },
            .{
                connection,
                device,
                specific_object,
            },
        );
        defer result.deinit();
        return try allocator.dupe(u8, result.next(dbus.ObjectPath));
    }
    pub fn deactivateConnection(self: Self, connection: []const u8) !void {
        const result = try self.manager.call(
            "DeactivateConnection",
            .{dbus.ObjectPath},
            .{connection},
        );
        result.deinit();
    }
    pub fn checkConnectivity(self: Self) !defines.ConnectivityState {
        const result = try self.manager.call("CheckConnectivity", .{}, .{});
        defer result.deinit();
        return @enumFromInt(result.next(dbus.UInt32));
    }
    pub fn getWirelessActiveAccessPoint(self: Self, allocator: Allocator, device: []const u8) !?structs.AccessPoint {
        const device_helper = try helper.DBusHelper.init(self.bus, device, "org.freedesktop.NetworkManager.Device.Wireless");
        defer device_helper.deinit();
        const ap = try device_helper.getAlloc(allocator, "ActiveAccessPoint", dbus.ObjectPath);
        defer allocator.free(ap);
        if (!helper.isValidPath(ap)) return null;
        return try structs.AccessPoint.init(allocator, self.bus, ap);
    }
    pub fn getWirelessAccessPoints(self: Self, allocator: Allocator, device: []const u8) ![]structs.AccessPoint {
        const device_helper = try helper.DBusHelper.init(self.bus, device, "org.freedesktop.NetworkManager.Device.Wireless");
        defer device_helper.deinit();
        const result = try device_helper.call("GetAccessPoints", .{}, .{});
        defer result.deinit();
        var aps = std.ArrayList(structs.AccessPoint){};
        defer aps.deinit(allocator);
        for (result.next(dbus.Array(dbus.ObjectPath))) |ap| {
            const a = try structs.AccessPoint.init(allocator, self.bus, ap);
            errdefer a.deinit(allocator);
            try aps.append(allocator, a);
        }
        return try aps.toOwnedSlice(allocator);
    }
    pub fn wirelessRequestScan(self: Self, device: []const u8) !void {
        const device_helper = try helper.DBusHelper.init(self.bus, device, "org.freedesktop.NetworkManager.Device.Wireless");
        defer device_helper.deinit();
        const result = try device_helper.call("RequestScan", .{dbus.Vardict}, .{dbus.Vardict.empty});
        result.deinit();
    }
};
const print = std.debug.print;
test {
    const allocator = testing.allocator;
    const bus = try dbus.Bus.init(allocator, .System);
    defer bus.deinit();
    const nm = try Network.init(bus);
    defer nm.deinit();

    var c = (try nm.getPrimaryConnection(allocator)).?;
    defer c.deinit(allocator);
}

fn printJson(data: anytype) void {
    const allocator = std.heap.page_allocator;
    const json = std.json.Stringify.valueAlloc(allocator, data, .{ .whitespace = .indent_4 }) catch unreachable;
    defer allocator.free(json);
    print("{s}\n", .{json});
}
