const libdbus = @import("libdbus.zig");
pub const Event = struct {
    sender: []const u8,
    iface: []const u8,
    path: []const u8,
    member: []const u8,
    serial: u32,
    destination: ?[]const u8,
    iter: *libdbus.MessageIter,
};
pub const Listener = struct {
    signal: []const u8,
    handler: *const fn (Event, ?*anyopaque) void,
    data: ?*anyopaque,
};
const object = @import("object.zig");
pub fn freedesktopDBus(bus: *@import("bus.zig").Bus) !*object.Object {
    return try bus.proxy("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus");
}
