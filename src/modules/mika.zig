const std = @import("std");
const webkit = @import("webkit");
const modules = @import("modules.zig");
const App = @import("../app.zig").App;
pub const Mika = struct {
    app: *App,
    const Self = @This();

    pub fn open(self: *Self, args: modules.Args, result: *modules.Result) !void {
        const pageName = try args.string(1);
        const webview = try self.app.open(pageName);
        const id = webview.impl.getPageId();
        try result.commit(id);
    }
};
