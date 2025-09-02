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
const modules = @import("root.zig");
const gtk = @import("gtk");
const Args = modules.Args;
const Context = modules.InitContext;
const CallContext = modules.Context;
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
        return .{
            .exports = &.{
                .{ "init", initLayer },
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
                .{ "setInputRegion", setInputRegion },
                .{ "getScale", getScale },
            },
        };
    }
    fn getWebview(self: *Self, ctx: *CallContext) !*Webview {
        const w = self.app.getWebview(ctx.caller) catch unreachable;
        if (w.type != .Layer) {
            return error.WebviewIsNotALayer;
        }
        return w;
    }
    fn getLayer(self: *Self, ctx: *CallContext) !layershell.Layer {
        const w = self.app.getWebview(ctx.caller) catch unreachable;
        if (w.type != .Layer) {
            return error.WebviewIsNotALayer;
        }
        const layer = layershell.Layer.init(w.container);
        return layer;
    }
    pub fn initLayer(self: *Self, ctx: *CallContext) !void {
        const w = self.app.getWebview(ctx.caller) catch unreachable;

        const allocator = std.heap.page_allocator;
        const options = try std.json.parseFromValue(Options, allocator, try ctx.args.value(0), .{});
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
        layer.setExclusiveZone(opt.exclusiveZone);
        if (opt.autoExclusiveZone) {
            layer.autoExclusiveZoneEnable();
        }
        if (opt.backgroundTransparent) {
            w.impl.setBackgroundColor(&.{ .f_red = 1, .f_green = 1, .f_blue = 1, .f_alpha = 0 });
        } else {
            w.impl.setBackgroundColor(&.{ .f_red = 1, .f_green = 1, .f_blue = 1, .f_alpha = 1 });
        }
        w.container.setDefaultSize(@intCast(opt.width), @intCast(opt.height));
        if (!opt.hidden) {
            self.app.showRequest(w);
        }
    }
    pub fn openDevTools(self: *Self, ctx: *CallContext) !void {
        const w = try self.getWebview(ctx);
        w.impl.getInspector().show();
    }
    pub fn resetAnchor(self: *Self, ctx: *CallContext) !void {
        const layer = try self.getLayer(ctx);
        layer.resetAnchor();
    }
    pub fn setAnchor(self: *Self, ctx: *CallContext) !void {
        const layer = try self.getLayer(ctx);
        const edge = try ctx.args.integer(0);
        const anchor = try ctx.args.bool(1);
        layer.setAnchor(@enumFromInt(edge), anchor);
    }
    pub fn setLayer(self: *Self, ctx: *CallContext) !void {
        const layer = try self.getLayer(ctx);
        const layer_type = try ctx.args.integer(0);
        layer.setLayer(@enumFromInt(layer_type));
    }
    pub fn setKeyboardMode(self: *Self, ctx: *CallContext) !void {
        const layer = try self.getLayer(ctx);
        const mode = try ctx.args.integer(0);
        layer.setKeyboardMode(@enumFromInt(mode));
    }
    pub fn setNamespace(self: *Self, ctx: *CallContext) !void {
        const layer = try self.getLayer(ctx);
        const namespace = try ctx.args.string(0);
        layer.setNamespace(namespace);
    }
    pub fn setMargin(self: *Self, ctx: *CallContext) !void {
        const layer = try self.getLayer(ctx);
        const edge = try ctx.args.integer(0);
        const margin = try ctx.args.integer(1);
        layer.setMargin(@enumFromInt(edge), @intCast(margin));
    }
    pub fn setExclusiveZone(self: *Self, ctx: *CallContext) !void {
        const layer = try self.getLayer(ctx);
        const exclusiveZone = try ctx.args.integer(0);
        layer.setExclusiveZone(@intCast(exclusiveZone));
    }
    pub fn autoExclusiveZoneEnable(self: *Self, ctx: *CallContext) !void {
        const layer = try self.getLayer(ctx);
        layer.autoExclusiveZoneEnable();
    }
    pub fn getSize(self: *Self, ctx: *CallContext) !void {
        const w = try self.getWebview(ctx);
        const surface = w.container.as(gtk.Native).getSurface();
        if (surface == null) {
            ctx.errors("you should call this function after the window is realized", .{});
            return;
        }
        ctx.commit(.{ .width = surface.?.getWidth(), .height = surface.?.getHeight() });
    }
    pub fn setSize(self: *Self, ctx: *CallContext) !void {
        const w = try self.getWebview(ctx);
        const width = try ctx.args.integer(0);
        const height = try ctx.args.integer(1);
        w.container.setDefaultSize(@intCast(width), @intCast(height));
    }
    pub fn getScale(self: *Self, ctx: *CallContext) !void {
        const w = try self.getWebview(ctx);
        const surface = w.container.as(gtk.Native).getSurface();
        if (surface == null) {
            ctx.errors("you should call this function after the window is realized", .{});
            return;
        }
        ctx.commit(surface.?.getScale());
    }
    pub fn setInputRegion(self: *Self, ctx: *CallContext) !void {
        const w = try self.getWebview(ctx);
        const surface = w.container.as(gtk.Native).getSurface();
        if (surface == null) {
            ctx.errors("you should call this function after the window is realized", .{});
            return;
        }
        const cairo = @import("cairo");
        const region = cairo.Region.create();
        defer region.destroy();
        surface.?.setInputRegion(region);
    }
};
