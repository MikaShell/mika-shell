const std = @import("std");
const webkit = @import("webkit");
const modules = @import("modules.zig");
const appM = @import("../app.zig");
pub const Mikami = struct {
    app: *appM.App,
    const Self = @This();

    pub fn open(self: *Self, args: modules.Args, result: *modules.Result) !void {
        const uri = try args.string(1);
        const id = self.app.createWebview(uri);
        try result.commit(id);
    }

    pub fn show(self: *Self, args: modules.Args, _: *modules.Result) !void {
        var id: u64 = undefined;
        const caller = try args.integer(1);
        if (caller >= 0) {
            id = @intCast(caller);
        } else {
            id = @intCast(try args.integer(0)); // caller id
        }
        for (self.app.webviews.items) |webview| {
            if (webview._webview.getPageId() == id) {
                webview.show();
                break;
            }
        }
    }
};
