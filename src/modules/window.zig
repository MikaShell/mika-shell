const Options = struct {
    title: []const u8,
    resizable: bool,
    hidden: bool,
    backgroundTransparent: bool,
};

const std = @import("std");
const webkit = @import("webkit");
const App = @import("../app.zig").App;
const Webview = @import("../app.zig").Webview;
const events = @import("../events.zig");
const Args = @import("modules.zig").Args;
const Result = @import("modules.zig").Result;
pub const Window = struct {
    app: *App,
    const Self = @This();
    fn getWindow(self: *Self, args: Args) !*Webview {
        const id = args.uInteger(0) catch unreachable;
        const w = self.app.getWebview(id) catch unreachable;
        if (w.type != .Window) {
            return error.WebviewIsNotAWindow;
        }
        return w;
    }
    pub fn init(self: *Self, args: Args, _: *Result) !void {
        const id = args.uInteger(0) catch unreachable;
        const w = self.app.getWebview(id) catch unreachable;
        if (w.type == .Layer) {
            // 已经被初始化为 Layer, 无法再次初始化为 Window
            return error.WebviewIsAlreadyAWindow;
        }
        w.type = .Window;
        const allocator = std.heap.page_allocator;
        const options = try std.json.parseFromValue(Options, allocator, try args.value(1), .{});
        defer options.deinit();
        const opt = options.value;
        w.container.setTitle(opt.title);
        w.container.setResizable(opt.resizable);
        if (opt.backgroundTransparent) {
            w.impl.setBackgroundColor(.{ .red = 1, .green = 1, .blue = 1, .alpha = 0 });
        } else {
            w.impl.setBackgroundColor(.{ .red = 1, .green = 1, .blue = 1, .alpha = 1 });
        }
        if (!opt.hidden) {
            w.container.present();
        }
    }
    pub fn getId(_: *Self, args: Args, result: *Result) !void {
        const id = args.uInteger(0) catch unreachable;
        try result.commit(id);
    }
    pub fn show(self: *Self, args: Args, _: *Result) !void {
        const w = try self.getWindow(args);
        w.show();
    }
    pub fn hide(self: *Self, args: Args, _: *Result) !void {
        const w = try self.getWindow(args);
        w.hide();
    }
    pub fn close(self: *Self, args: Args, _: *Result) !void {
        const w = try self.getWindow(args);
        w.close();
    }
};
