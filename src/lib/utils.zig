const std = @import("std");
pub fn webpToBase64(allocator: std.mem.Allocator, webp: []const u8) ![]u8 {
    const encoder = std.base64.standard.Encoder;
    const base64 = try allocator.alloc(u8, encoder.calcSize(webp.len));
    defer allocator.free(base64);
    return try std.fmt.allocPrint(allocator, "data:image/webp;base64,{s}", .{encoder.encode(base64, webp)});
}
