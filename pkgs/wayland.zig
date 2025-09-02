pub const ForeignToplevel = @import("wayland/foreign-toplevel.zig");
pub const Screencopy = @import("wayland/screencopy.zig");
test {
    _ = @import("wayland/foreign-toplevel.zig");
    _ = @import("wayland/screencopy.zig");
}
