const std = @import("std");
const webkit = @import("webkit");
const Args = @import("modules.zig").Args;
const Result = @import("modules.zig").Result;
const App = @import("../app.zig").App;
const events = @import("../events.zig");
pub const Mika = struct {
    app: *App,
    const Self = @This();
    pub fn open(self: *Self, args: Args, result: *Result) !void {
        const pageName = try args.string(1);
        const webview = try self.app.open(pageName);
        const id = webview.impl.getPageId();
        try result.commit(id);
    }
    pub fn close(self: *Self, args: Args, _: *Result) !void {
        const id = try args.uInteger(1);
        const w = try self.app.getWebview(id);
        w.close();
    }
    pub fn forceClose(self: *Self, args: Args, _: *Result) !void {
        const id = try args.uInteger(1);
        const w = try self.app.getWebview(id);
        w.forceClose();
    }
    pub fn show(self: *Self, args: Args, _: *Result) !void {
        const id = try args.uInteger(1);
        const w = try self.app.getWebview(id);
        w.show();
    }
    pub fn forceShow(self: *Self, args: Args, _: *Result) !void {
        const id = try args.uInteger(1);
        const w = try self.app.getWebview(id);
        w.forceShow();
    }
    pub fn hide(self: *Self, args: Args, _: *Result) !void {
        const id = try args.uInteger(1);
        const w = try self.app.getWebview(id);
        w.hide();
    }
    pub fn forceHide(self: *Self, args: Args, _: *Result) !void {
        const id = try args.uInteger(1);
        const w = try self.app.getWebview(id);
        w.forceHide();
    }
};
