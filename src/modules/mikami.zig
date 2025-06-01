const std = @import("std");
const webkit = @import("webkit");
const modules = @import("modules.zig");
const appM = @import("../app.zig");
pub const Mikami = struct {
    app: *appM.App,
    const Self = @This();

    pub fn open(self: *Self, args: modules.Args, result: *modules.Result) !void {
        const uri = try args.string(1);
        const webview = self.app.open(uri);
        const id = webview.impl.getPageId();
        try result.commit(id);
    }
};
