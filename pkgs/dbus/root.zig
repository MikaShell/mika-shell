const libdbus = @import("libdbus.zig");
const std = @import("std");
const glib = @import("glib");
const Allocator = std.mem.Allocator;
pub usingnamespace libdbus.Types;
pub const Message = libdbus.Message;
pub const MessageIter = libdbus.MessageIter;
pub usingnamespace @import("service.zig");
pub usingnamespace @import("client.zig");
pub usingnamespace @import("common.zig");
test {
    _ = @import("libdbus.zig");
    _ = @import("types.zig");
    _ = @import("client.zig");
    _ = @import("service.zig");
}
