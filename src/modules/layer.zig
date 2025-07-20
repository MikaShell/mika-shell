const layershell = @import("layershell");
pub const Options = struct {
    monitor: i32,
    anchor: []layershell.Edge,
    layer: layershell.Layers,
    keyboardMode: layershell.KeyboardMode,
    namespace: []const u8,
    margin: [4]i32, // 上右下左
    exclusiveZone: i32,
    autoExclusiveZone: bool,
    backgroundTransparent: bool,
    hidden: bool,
    width: i32,
    height: i32,
};

const std = @import("std");
const webkit = @import("webkit");
const Webview = @import("../app.zig").Webview;
const App = @import("../app.zig").App;
const modules = @import("modules.zig");
const Args = modules.Args;
const Result = modules.Result;
const Context = modules.Context;
const Registry = modules.Registry;
const Allocator = std.mem.Allocator;
pub const Layer = struct {
    app: *App,
    const Self = @This();
    pub fn init(ctx: Context) !*Self {
        const self = try ctx.allocator.create(Self);
        self.app = ctx.app;
        return self;
    }
    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.destroy(self);
    }
    pub fn register() Registry(Self) {
        return &.{
            .{ "init", initLayer },
            .{ "getId", getId },
            .{ "show", show },
            .{ "hide", hide },
            .{ "close", close },
            .{ "openDevTools", openDevTools },
            .{ "resetAnchor", resetAnchor },
            .{ "setAnchor", setAnchor },
            .{ "setLayer", setLayer },
            .{ "setKeyboardMode", setKeyboardMode },
            .{ "setNamespace", setNamespace },
            .{ "setMargin", setMargin },
            .{ "setExclusiveZone", setExclusiveZone },
            .{ "autoExclusiveZoneEnable", autoExclusiveZoneEnable },
            .{ "getSize", getSize },
            .{ "setSize", setSize },
        };
    }
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
    pub fn initLayer(self: *Self, args: Args, _: *Result) !void {
        const id = args.uInteger(0) catch unreachable;
        const w = self.app.getWebview(id) catch unreachable;

        const allocator = std.heap.page_allocator;
        const options = try std.json.parseFromValue(Options, allocator, try args.value(1), .{});
        defer options.deinit();
        const opt = options.value;
        if (w.type == .Window) {
            // 已经被初始化为 Window, 无法再次初始化为 Layer
            return error.WebviewIsAlreadyAWindow;
        }

        const layer = layershell.Layer.init(w.container);
        if (w.type == .None) {
            _ = layer.setMonitor(opt.monitor) catch {};
        }
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
        w.container.setDefaultSize(opt.width, opt.height);
        if (!opt.hidden) {
            w.show();
        }

        w.options = .{ .layer = opt };
    }
    pub fn getId(_: *Self, args: Args, result: *Result) !void {
        const id = args.uInteger(0) catch unreachable;
        result.commit(id);
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
    pub fn openDevTools(self: *Self, args: Args, _: *Result) !void {
        const w = try self.getWebview(args);
        w.impl.openDevTools();
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
    pub fn getSize(self: *Self, args: Args, result: *Result) !void {
        const w = try self.getWebview(args);
        var width: i32 = 0;
        var height: i32 = 0;
        w.container.getSize(&width, &height);
        result.commit(.{ .width = width, .height = height });
    }
    pub fn setSize(self: *Self, args: Args, _: *Result) !void {
        const w = try self.getWebview(args);
        const width = try args.integer(1);
        const height = try args.integer(2);
        w.container.setDefaultSize(@intCast(width), @intCast(height));
    }
};
