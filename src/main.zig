const gtk = @import("gtk");
const webkit = @import("webkit");
const std = @import("std");
pub fn main() !void {
    gtk.init();
    const v = webkit.version();
    std.debug.print("WebKit version: {}\n", .{v});
}
