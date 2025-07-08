const layershell = @import("layershell");
const Options = struct {
    anchor: []layershell.Edge,
    layer: layershell.Layers,
    keyboardMode: layershell.KeyboardMode,
    namespace: []const u8,
    margin: [4]i32, // 上右下左
    exclusiveZone: i32,
    autoExclusiveZone: bool,
    backgroundTransparent: bool,
    hidden: bool,
};

const std = @import("std");
const webkit = @import("webkit");
const modules = @import("modules.zig");
const Webview = @import("../app.zig").Webview;
const App = @import("../app.zig").App;
const Args = @import("modules.zig").Args;
const Result = @import("modules.zig").Result;
pub const Layer = struct {
    app: *App,
    const Self = @This();
    fn getWebview(self: *Self, args: Args) !*Webview {
        const id = args.uInteger(0) catch unreachable;
        const w = self.app.getWebview(id) catch unreachable;
        if (w.type != .Layer) {
            return error.WebviewIsNotALayer;
        }
        return w;
    }
    fn getLayer(self: *Self, args: Args) !layershell.Layer {
        const id = args.uInteger(0) catch unreachable;
        const w = self.app.getWebview(id) catch unreachable;
        if (w.type != .Layer) {
            return error.WebviewIsNotALayer;
        }
        const layer = layershell.Layer.init(w.container);
        return layer;
    }
    pub fn init(self: *Self, args: Args, _: *Result) !void {
        const id = args.uInteger(0) catch unreachable;
        const w = self.app.getWebview(id) catch unreachable;
        if (w.type == .Window) {
            // 已经被初始化为 Window, 无法再次初始化为 Layer
            return error.WebviewIsAlreadyAWindow;
        }
        const allocator = std.heap.page_allocator;
        const options = try std.json.parseFromValue(Options, allocator, try args.value(1), .{});
        defer options.deinit();
        const opt = options.value;
        const layer = layershell.Layer.init(w.container);
        w.type = .Layer;
        layer.resetAnchor();
        for (opt.anchor) |a| {
            layer.setAnchor(a, true);
        }
        layer.setLayer(opt.layer);
        layer.setKeyboardMode(opt.keyboardMode);
        layer.setNamespace(opt.namespace);
        layer.setMargin(layershell.Edge.Top, opt.margin[0]);
        layer.setMargin(layershell.Edge.Right, opt.margin[1]);
        layer.setMargin(layershell.Edge.Bottom, opt.margin[2]);
        layer.setMargin(layershell.Edge.Left, opt.margin[3]);
        if (opt.exclusiveZone > 0) {
            layer.setExclusiveZone(opt.exclusiveZone);
        } else if (opt.autoExclusiveZone) {
            layer.autoExclusiveZoneEnable();
        }
        if (opt.backgroundTransparent) {
            w.impl.setBackgroundColor(.{ .red = 1, .green = 1, .blue = 1, .alpha = 0 });
        } else {
            w.impl.setBackgroundColor(.{ .red = 1, .green = 1, .blue = 1, .alpha = 1 });
        }
        if (!opt.hidden) {
            w.container.asWidget().show();
        }
    }
    pub fn getId(_: *Self, args: Args, result: *Result) !void {
        const id = args.uInteger(0) catch unreachable;
        try result.commit(id);
    }
    pub fn show(self: *Self, args: Args, _: *Result) !void {
        const w = self.getWebview(args) catch unreachable;
        if (w.container.asWidget().getVisible()) return error.LayerIsAlreadyVisible;
        w.show();
    }
    pub fn hide(self: *Self, args: Args, _: *Result) !void {
        const w = self.getWebview(args) catch unreachable;
        if (!w.container.asWidget().getVisible()) return error.LayerIsAlreadyHidden;
        w.hide();
    }
    pub fn close(self: *Self, args: Args, _: *Result) !void {
        const w = self.getWebview(args) catch unreachable;
        w.close();
    }
    pub fn resetAnchor(self: *Self, args: Args, _: *Result) !void {
        const layer = try self.getLayer(args);
        layer.resetAnchor();
    }
    pub fn setAnchor(self: *Self, args: Args, _: *Result) !void {
        const layer = try self.getLayer(args);
        const edge = try args.integer(1);
        const anchor = try args.bool(2);
        layer.setAnchor(@enumFromInt(edge), anchor);
    }
    pub fn setLayer(self: *Self, args: Args, _: *Result) !void {
        const layer = try self.getLayer(args);
        const layer_type = try args.integer(1);
        layer.setLayer(@enumFromInt(layer_type));
    }
    pub fn setKeyboardMode(self: *Self, args: Args, _: *Result) !void {
        const layer = try self.getLayer(args);
        const mode = try args.integer(1);
        layer.setKeyboardMode(@enumFromInt(mode));
    }
    pub fn setNamespace(self: *Self, args: Args, _: *Result) !void {
        const layer = try self.getLayer(args);
        const namespace = try args.string(1);
        layer.setNamespace(namespace);
    }
    pub fn setMargin(self: *Self, args: Args, _: *Result) !void {
        const layer = try self.getLayer(args);
        const edge = try args.integer(1);
        const margin = try args.integer(2);
        layer.setMargin(@enumFromInt(edge), @intCast(margin));
    }
    pub fn setExclusiveZone(self: *Self, args: Args, _: *Result) !void {
        const layer = try self.getLayer(args);
        const exclusiveZone = try args.integer(1);
        layer.setExclusiveZone(@intCast(exclusiveZone));
    }
    pub fn autoExclusiveZoneEnable(self: *Self, args: Args, _: *Result) !void {
        const layer = try self.getLayer(args);
        layer.autoExclusiveZoneEnable();
    }
};
