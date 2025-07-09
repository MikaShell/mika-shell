const cli = @import("cli.zig");
pub fn main() !void {
    return cli.run();
}

test {
    _ = @import("lib/tray.zig");
    _ = @import("lib/notifd.zig");
    _ = @import("modules/modules.zig");
    _ = @import("modules/apps.zig");
    _ = @import("modules/icon.zig");
    _ = @import("modules/layer.zig");
    _ = @import("modules/os.zig");
    _ = @import("modules/tray.zig");
    _ = @import("modules/window.zig");
}
