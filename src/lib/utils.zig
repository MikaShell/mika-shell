const std = @import("std");
pub fn webpToBase64(allocator: std.mem.Allocator, webp: []const u8) ![]const u8 {
    return try std.fmt.allocPrint(allocator, "data:image/webp;base64,{b64}", .{webp});
}
