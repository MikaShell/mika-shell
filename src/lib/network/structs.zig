const defines = @import("defines.zig");
const dbus = @import("dbus");
const std = @import("std");
const Allocator = std.mem.Allocator;
const DBusHelper = @import("helper.zig").DBusHelper;
pub const Device = struct {
    dbus_path: []const u8,
    interface: []const u8,
    driver: []const u8,
    driver_version: []const u8,
    hw_address: []const u8,
    path: []const u8,
    type: defines.DeviceType,
    pub fn deinit(self: Device, allocator: Allocator) void {
        allocator.free(self.dbus_path);
        allocator.free(self.interface);
        allocator.free(self.driver);
        allocator.free(self.driver_version);
        allocator.free(self.hw_address);
        allocator.free(self.path);
    }
    pub fn init(allocator: Allocator, bus: *dbus.Bus, path: []const u8) !Device {
        const device = try bus.proxy("org.freedesktop.NetworkManager", path, "org.freedesktop.NetworkManager.Device");
        defer device.deinit();

        var d: Device = undefined;
        d.dbus_path = try allocator.dupe(u8, path);
        try device.get2Alloc(allocator, "Interface", dbus.String, &d.interface);
        errdefer allocator.free(d.interface);
        try device.get2Alloc(allocator, "Driver", dbus.String, &d.driver);
        errdefer allocator.free(d.driver);
        try device.get2Alloc(allocator, "DriverVersion", dbus.String, &d.driver_version);
        errdefer allocator.free(d.driver_version);
        try device.get2Alloc(allocator, "HwAddress", dbus.String, &d.hw_address);
        errdefer allocator.free(d.hw_address);
        try device.get2Alloc(allocator, "Path", dbus.String, &d.path);
        errdefer allocator.free(d.path);
        var typ: u32 = undefined;
        try device.get2("DeviceType", dbus.UInt32, &typ);
        d.type = @enumFromInt(typ);
        return d;
    }
};
pub const Connection = struct {
    const Wireless = struct {
        const Security = struct {
            @"key-mgmt": enum {
                none,
                ieee8021x,
                @"wpa-psk",
                @"wpa-eap",
                @"wpa-eap-suite-b-192",
                sae,
                owe,
            },
            psk: ?[]const u8,
        };
        band: ?enum {
            @"5GHz",
            @"2.4GHz",
        },
        bssid: ?[]const u8,
        hidden: bool,
        mode: enum {
            infrastructure,
            adhoc,
            ap,
            mesh,
        },
        powersave: enum {
            default,
            ignore,
            disable,
            enable,
        },
        ssid: ?[]const u8,
        security: ?Security,
    };
    dbus_path: []const u8,
    filename: []const u8,
    id: []const u8,
    type: defines.ConnectionType,
    zone: ?[]const u8,
    autoconnect: bool,
    autoconnect_ports: enum { true, false, default },
    metered: enum { yes, no, default },
    autoconnect_priority: i32,
    controller: ?[]const u8,
    wireless: ?Wireless,
    pub fn init(allocator: Allocator, bus: *dbus.Bus, path: []const u8) !Connection {
        const conn = try DBusHelper.init(bus, path, "org.freedesktop.NetworkManager.Settings.Connection");
        defer conn.deinit();
        var c: Connection = undefined;
        c.dbus_path = try allocator.dupe(u8, path);
        errdefer allocator.free(c.dbus_path);
        c.zone = null;
        c.autoconnect = true;
        c.autoconnect_ports = .default;
        c.metered = .default;
        c.autoconnect_priority = 0;
        c.controller = null;
        c.wireless = null;

        try conn.get2Alloc(allocator, "Filename", dbus.String, &c.filename);
        errdefer allocator.free(c.filename);
        const result = try conn.call("GetSettings", .{}, null, .{
            dbus.Dict(
                dbus.String,
                dbus.Dict(
                    dbus.String,
                    dbus.Variant,
                ),
            ),
        });
        defer result.deinit();
        const settings = result.values.?[0];
        const eql = std.mem.eql;
        for (settings) |sett| {
            if (eql(u8, sett.key, "connection")) {
                for (sett.value) |con| {
                    const key = con.key;
                    if (eql(u8, key, "id")) {
                        c.id = try allocator.dupe(u8, try con.value.get(dbus.String));
                    } else if (eql(u8, key, "type")) {
                        c.type = defines.ConnectionType.parse(try con.value.get(dbus.String));
                    } else if (eql(u8, key, "zone")) {
                        c.zone = try allocator.dupe(u8, try con.value.get(dbus.String));
                    } else if (eql(u8, key, "autoconnect")) {
                        c.autoconnect = try con.value.get(dbus.Boolean);
                    } else if (eql(u8, key, "autoconnect-ports")) {
                        const v = try con.value.get(dbus.Int32);
                        if (v == -1) {
                            c.autoconnect_ports = .default;
                        } else if (v == 0) {
                            c.autoconnect_ports = .false;
                        } else if (v == 1) {
                            c.autoconnect_ports = .true;
                        } else @panic("unsupported autoconnect-ports value");
                    } else if (eql(u8, key, "metered")) {
                        // true/yes/on、false/no/off、default/unknown
                        const v = try con.value.get(dbus.String);
                        if (eql(u8, v, "true") or eql(u8, v, "yes") or eql(u8, v, "on")) {
                            c.metered = .yes;
                        } else if (eql(u8, v, "false") or eql(u8, v, "no") or eql(u8, v, "off")) {
                            c.metered = .no;
                        } else if (eql(u8, v, "default") or eql(u8, v, "unknown")) {
                            c.metered = .default;
                        } else @panic("unsupported metered value");
                    } else if (eql(u8, key, "autoconnect-priority")) {
                        const v = try con.value.get(dbus.Int32);
                        c.autoconnect_priority = v;
                    } else if (eql(u8, key, "controller")) {
                        c.controller = try allocator.dupe(u8, try con.value.get(dbus.String));
                    }
                }
            } else if (eql(u8, sett.key, "802-11-wireless")) {
                var wireless: Wireless = undefined;
                wireless.bssid = null;
                wireless.ssid = null;
                wireless.hidden = false;
                wireless.mode = .infrastructure;
                wireless.powersave = .default;
                for (sett.value) |wirl| {
                    const key = wirl.key;
                    if (eql(u8, key, "band")) {
                        const band = try wirl.value.get(dbus.String);
                        if (eql(u8, band, "bg")) {
                            wireless.band = .@"2.4GHz";
                        } else if (eql(u8, band, "a")) {
                            wireless.band = .@"5GHz";
                        } else @panic("unsupported band value");
                    } else if (eql(u8, key, "bssid")) {
                        const bssid = try wirl.value.get(dbus.Array(dbus.Byte));
                        wireless.bssid = try allocator.dupe(u8, bssid);
                    } else if (eql(u8, key, "hidden")) {
                        wireless.hidden = try wirl.value.get(dbus.Boolean);
                    } else if (eql(u8, key, "mode")) {
                        const mode = try wirl.value.get(dbus.String);
                        if (eql(u8, mode, "infrastructure")) {
                            wireless.mode = .infrastructure;
                        } else if (eql(u8, mode, "adhoc")) {
                            wireless.mode = .adhoc;
                        } else if (eql(u8, mode, "ap")) {
                            wireless.mode = .ap;
                        } else if (eql(u8, mode, "mesh")) {
                            wireless.mode = .mesh;
                        } else @panic("unsupported mode value");
                    } else if (eql(u8, key, "powersave")) {
                        const powersave = try wirl.value.get(dbus.Int32);
                        wireless.powersave = switch (powersave) {
                            0 => .default,
                            1 => .ignore,
                            2 => .disable,
                            3 => .enable,
                            else => @panic("unsupported powersave value"),
                        };
                    } else if (eql(u8, key, "ssid")) {
                        const ssid = try wirl.value.get(dbus.Array(dbus.Byte));
                        wireless.ssid = try allocator.dupe(u8, ssid);
                    }
                }
                c.wireless = wireless;
            } else if (eql(u8, sett.key, "802-11-wireless-security")) {
                var s: Wireless.Security = .{
                    .@"key-mgmt" = .none,
                    .psk = null, // need permission
                };
                for (sett.value) |sec| {
                    const key = sec.key;
                    if (eql(u8, key, "key-mgmt")) {
                        const key_mgmt = try sec.value.get(dbus.String);
                        if (eql(u8, key_mgmt, "none")) {
                            s.@"key-mgmt" = .none;
                        } else if (eql(u8, key_mgmt, "ieee8021x")) {
                            s.@"key-mgmt" = .ieee8021x;
                        } else if (eql(u8, key_mgmt, "wpa-psk")) {
                            s.@"key-mgmt" = .@"wpa-psk";
                        } else if (eql(u8, key_mgmt, "wpa-eap")) {
                            s.@"key-mgmt" = .@"wpa-eap";
                        } else if (eql(u8, key_mgmt, "wpa-eap-suite-b-192")) {
                            s.@"key-mgmt" = .@"wpa-eap-suite-b-192";
                        } else if (eql(u8, key_mgmt, "sae")) {
                            s.@"key-mgmt" = .sae;
                        } else if (eql(u8, key_mgmt, "owe")) {
                            s.@"key-mgmt" = .owe;
                        } else @panic("unsupported security protocol");
                    }
                }
                c.wireless.?.security = s;
            }
        }

        return c;
    }
    pub fn deinit(self: Connection, allocator: Allocator) void {
        allocator.free(self.dbus_path);
        allocator.free(self.filename);
        allocator.free(self.id);
        if (self.zone) |zone| allocator.free(zone);
        if (self.controller) |controller| allocator.free(controller);
        if (self.wireless) |wireless| {
            if (wireless.bssid) |bssid| allocator.free(bssid);
            if (wireless.ssid) |ssid| allocator.free(ssid);
            if (wireless.security) |security| {
                if (security.psk) |psk| allocator.free(psk);
            }
        }
    }
};
pub const ActiveConnection = struct {
    connection: Connection,
    default4: bool,
    default6: bool,
    devices: []Device,
    state: defines.ActiveConnectionState,
    state_flags: defines.ActiveConnectionStateFlags,
    type: defines.ConnectionType,
    pub fn init(allocator: Allocator, bus: *dbus.Bus, path: []const u8) !ActiveConnection {
        const active = try DBusHelper.init(bus, path, "org.freedesktop.NetworkManager.Connection.Active");
        defer active.deinit();
        var ac: ActiveConnection = undefined;
        ac.default4 = false;
        ac.default6 = false;
        ac.devices = try allocator.alloc(Device, 0);
        ac.state = .unknown;
        ac.state_flags = .{};

        var conn: []const u8 = undefined;
        defer allocator.free(conn);
        try active.get2Alloc(allocator, "Connection", dbus.ObjectPath, &conn);
        ac.connection = try Connection.init(allocator, bus, conn);
        errdefer ac.connection.deinit(allocator);

        const devices = try active.get("Devices", dbus.Array(dbus.ObjectPath));
        defer devices.deinit();
        var ds = std.ArrayList(Device).init(allocator);
        defer ds.deinit();
        for (devices.value) |devicePath| {
            const d = try Device.init(allocator, bus, devicePath);
            errdefer d.deinit(allocator);
            try ds.append(d);
        }
        ac.devices = try ds.toOwnedSlice();

        var typ: []const u8 = undefined;
        defer allocator.free(typ);
        try active.get2Alloc(allocator, "Type", dbus.String, &typ);
        ac.type = defines.ConnectionType.parse(typ);

        try active.get2("Default", dbus.Boolean, &ac.default4);
        try active.get2("Default6", dbus.Boolean, &ac.default6);
        var state: u32 = undefined;
        try active.get2("State", dbus.UInt32, &state);
        ac.state = @enumFromInt(state);
        var stateFlags: u32 = undefined;
        try active.get2("StateFlags", dbus.UInt32, &stateFlags);
        ac.state_flags = defines.ActiveConnectionStateFlags.fromRaw(stateFlags);
        return ac;
    }
    pub fn deinit(self: ActiveConnection, allocator: Allocator) void {
        for (self.devices) |device| device.deinit(allocator);
        allocator.free(self.devices);
        self.connection.deinit(allocator);
    }
};
