const dbus = @import("dbus");
const std = @import("std");
const Allocator = std.mem.Allocator;
pub const DBusHelper = struct {
    const Self = @This();
    const ErrorMap = [_]std.meta.Tuple(&.{ []const u8, anyerror }){
        .{ "org.freedesktop.NetworkManager.AlreadyEnabledOrDisabled", error.AlreadyEnabledOrDisabled },
        .{ "org.freedesktop.NetworkManager.ConnectionNotActive", error.ConnectionNotActive },
        .{ "org.freedesktop.NetworkManager.Device.NotAllowed", error.NotAllowed },
    };
    object: *dbus.Object,
    pub fn init(bus: *dbus.Bus, path: []const u8, iface: []const u8) !Self {
        return .{
            .object = try bus.proxy("org.freedesktop.NetworkManager", path, iface),
        };
    }
    pub fn deinit(self: Self) void {
        self.object.deinit();
    }
    fn parseError(self: Self, err: anyerror) anyerror {
        if (err != error.DBusError) return err;
        const eql = std.mem.eql;
        const errName = self.object.err.name();
        const errMsg = self.object.err.message();
        for (ErrorMap) |em| {
            if (eql(u8, errName, em[0])) {
                return em[1];
            }
        }

        std.debug.print("unknown DBus error: {s}:{s}", .{ errName, errMsg });
        return err;
    }
    pub fn get(self: Self, prop: []const u8, ResultTyep: type) !dbus.ResultGet(ResultTyep) {
        return self.object.get(prop, ResultTyep) catch |err| return self.parseError(err);
    }
    pub fn getBasic(self: Self, prop: []const u8, ResultTyep: type) !ResultTyep.Type {
        return self.object.getBasic(prop, ResultTyep) catch |err| return self.parseError(err);
    }
    pub fn getAlloc(self: Self, alloctor: Allocator, prop: []const u8, ResultTyep: type) !ResultTyep.Type {
        return self.object.getAlloc(alloctor, prop, ResultTyep) catch |err| return self.parseError(err);
    }
    pub fn call(self: Self, name: []const u8, comptime argsType: anytype, args: dbus.getTupleTypes(argsType)) !dbus.Result {
        return self.object.call(name, argsType, args) catch |err| return self.parseError(err);
    }
    pub fn callN(self: Self, name: []const u8, comptime argsType: anytype, args: dbus.getTupleTypes(argsType)) !void {
        return self.object.callN(name, argsType, args) catch |err| return self.parseError(err);
    }
};
pub fn isValidPath(path: []const u8) bool {
    return !std.mem.eql(u8, path, "/");
}
