const Options = struct {
    title: []const u8,
    resizable: bool,
    hidden: bool,
    backgroundTransparent: bool,
};

const std = @import("std");
const webkit = @import("webkit");
const modules = @import("modules.zig");
const App = @import("../app.zig").App;
const Webview = @import("../app.zig").Webview;
pub const Window = struct {
    app: *App,
    const Self = @This();
    fn getWindow(self: *Self, args: modules.Args) !*Webview {
        const id = try args.uInteger(0);
        const w = self.app.getWebview(id).?;
        if (w.type != .Window) {
            return error.WebviewIsNotAWindow;
        }
        return w;
    }
    pub fn init(self: *Self, args: modules.Args, _: *modules.Result) !void {
        const id = try args.uInteger(0);
        const w = self.app.getWebview(id).?;
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
    pub fn show(self: *Self, args: modules.Args, _: *modules.Result) !void {
        const w = try self.getWindow(args);
        w.container.present();
    }
    pub fn hide(self: *Self, args: modules.Args, _: *modules.Result) !void {
        const w = try self.getWindow(args);
        w.container.asWidget().hide();
    }
};
