const libdbus = @import("libdbus.zig");
const std = @import("std");
pub const Bus = struct {
    const Self = @This();
    conn: *libdbus.Connection,
    pub fn init(bus_type: libdbus.BusType, err: libdbus.Error) !Bus {
        return Bus{ .conn = try libdbus.Connection.get(bus_type, err) };
    }
    pub fn object(self: *Self, name: []const u8, path: []const u8, iface: []const u8) Object {
        return Object{
            .name = name,
            .path = path,
            .iface = iface,
            .conn = self.conn,
        };
    }
};
pub const Object = struct {
    name: []const u8,
    path: []const u8,
    iface: []const u8,
    conn: *libdbus.Connection,
};
test "dbus" {
    _ = libdbus;
}
