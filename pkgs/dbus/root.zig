const libdbus = @import("libdbus.zig");
const std = @import("std");
const glib = @import("glib");
const Allocator = std.mem.Allocator;
pub const Connection = libdbus.Connection;
pub const Message = libdbus.Message;
pub const MessageIter = libdbus.MessageIter;
pub const Error = libdbus.Error;
pub const DBusError = libdbus.DBusError;
pub usingnamespace libdbus.Types;
pub usingnamespace @import("service.zig");
pub usingnamespace @import("object.zig");
pub usingnamespace @import("common.zig");
pub usingnamespace @import("bus.zig");
test {
    _ = @import("libdbus.zig");
    _ = @import("types.zig");
    _ = @import("bus.zig");
    _ = @import("object.zig");
    _ = @import("service.zig");
}
