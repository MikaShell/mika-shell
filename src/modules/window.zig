pub const Options = struct {
    title: []const u8,
    class: []const u8,
    resizable: bool,
    hidden: bool,
    backgroundTransparent: bool,
    width: i32,
    height: i32,
};

const std = @import("std");
const webkit = @import("webkit");
const App = @import("../app.zig").App;
const Webview = @import("../app.zig").Webview;
const events = @import("../events.zig");
const modules = @import("root.zig");
const Args = modules.Args;
const InitContext = modules.InitContext;
const Context = modules.Context;
const Registry = modules.Registry;
const Allocator = std.mem.Allocator;
const gtk = @import("gtk");
const g = @import("gobject");
pub const Window = struct {
    const Self = @This();
    app: *App,
    pub fn init(ctx: InitContext) !*Self {
        const self = try ctx.allocator.create(Self);
        self.* = Self{
            .app = ctx.app,
        };
        return self;
    }
    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.destroy(self);
    }
    pub fn register() Registry(Self) {
        return .{
            .exports = &.{
                .{ "init", initWindow },
                .{ "setTitle", setTitle },
                .{ "setSize", setSize },
                .{ "getSize", getSize },
                .{ "getScaleFactor", getScale },
                .{ "setInputRegion", setInputRegion },
            },
        };
    }
    fn getWebview(self: *Self, ctx: *Context) !*Webview {
        const w = self.app.getWebviewWithId(ctx.caller) catch unreachable;
        if (w.container != .window) {
            return error.WebviewIsNotAWindow;
        }
        return w;
    }
    // TODO: window 和 layer 增加 background-color 选项
    pub fn initWindow(self: *Self, ctx: *Context) !void {
        const allocator = std.heap.page_allocator;
        const options = try std.json.parseFromValue(Options, allocator, try ctx.args.value(0), .{});
        defer options.deinit();
        const opt = options.value;
        const onMapContext = struct {
            id: c_ulong,
            class: [:0]const u8,
            resizable: bool,
        };
        const onMap = &struct {
            fn f(o: *g.Object, ctx_: *onMapContext) callconv(.c) void {
                const widget = g.ext.cast(gtk.Widget, o).?;
                g.signalHandlerDisconnect(widget.as(g.Object), ctx_.id);
                const window = g.ext.cast(gtk.Window, o).?;
                setClass(window, ctx_.class) catch unreachable;
                std.heap.page_allocator.free(ctx_.class);
                std.heap.page_allocator.destroy(ctx_);
            }
        }.f;

        const webview = self.app.getWebviewWithId(ctx.caller) catch unreachable;
        switch (webview.container) {
            .none => {
                self.app.setupContianer(webview, .window);
                // 这个回调只会执行一次
                const ctx_ = try std.heap.page_allocator.create(onMapContext);
                const id_ = g.signalConnectData(webview.container.window.as(g.Object), "map", @ptrCast(onMap), ctx_, null, .flags_default);
                ctx_.* = .{
                    .id = id_,
                    .class = std.heap.page_allocator.dupeZ(u8, opt.class) catch unreachable,
                    .resizable = opt.resizable,
                };
            },
            .layer, .popover => {
                return error.WebviewAlreadyInitializedAsOtherType;
            },
            .window => {
                setClass(webview.container.window, opt.class) catch unreachable;
            },
        }

        const window = webview.container.window;
        const widget = window.as(gtk.Widget);

        const title_ = try allocator.dupeZ(u8, opt.title);
        defer allocator.free(title_);
        window.setTitle(title_);
        if (opt.backgroundTransparent) {
            webview.impl.setBackgroundColor(&.{ .f_red = 1, .f_green = 1, .f_blue = 1, .f_alpha = 0 });
        } else {
            webview.impl.setBackgroundColor(&.{ .f_red = 1, .f_green = 1, .f_blue = 1, .f_alpha = 1 });
        }
        if (!opt.hidden) {
            self.app.showRequest(webview);
        }
        window.setDefaultSize(opt.width, opt.height);
        window.setResizable(if (opt.resizable) 1 else 0);
        if (widget.getVisible() == 1) window.present();
    }
    pub fn setTitle(self: *Self, ctx: *Context) !void {
        const w = try self.getWebview(ctx);
        const title = try ctx.args.string(1);
        const allocator = std.heap.page_allocator;
        const title_ = try allocator.dupeZ(u8, title);
        defer allocator.free(title_);
        w.container.window.setTitle(title_);
    }
    pub fn setSize(self: *Self, ctx: *Context) !void {
        const w = try self.getWebview(ctx);
        if (w.container.window.getResizable() == 1) {
            return ctx.errors("setSize is not allowed for resizable window", .{});
        }
        const width = try ctx.args.integer(1);
        const height = try ctx.args.integer(2);
        w.container.window.setDefaultSize(@intCast(width), @intCast(height));
    }
    pub fn getSize(self: *Self, ctx: *Context) !void {
        const w = try self.getWebview(ctx);
        const surface = w.container.window.as(gtk.Native).getSurface();
        if (surface == null) {
            return ctx.errors("you should call this function after the window is realized", .{});
        }
        ctx.commit(.{ .width = surface.?.getWidth(), .height = surface.?.getHeight() });
    }
    pub fn getScale(self: *Self, ctx: *Context) !void {
        const w = try self.getWebview(ctx);
        const surface = w.container.window.as(gtk.Native).getSurface();
        if (surface == null) {
            return ctx.errors("you should call this function after the window is realized", .{});
        }
        ctx.commit(surface.?.getScale());
    }
    pub fn setInputRegion(self: *Self, ctx: *Context) !void {
        const w = try self.getWebview(ctx);
        const surface = w.container.window.as(gtk.Native).getSurface();
        if (surface == null) {
            return ctx.errors("you should call this function after the window is realized", .{});
        }
        const cairo = @import("cairo");
        const region = cairo.Region.create();
        defer region.destroy();
        surface.?.setInputRegion(region);
    }
};
const gdk = @import("gdk");
fn setClass(window: *gtk.Window, class: []const u8) !void {
    const surface = window.as(gtk.Native).getSurface();
    if (surface == null) {
        return error.CanNotGetSurface;
    }
    const gdkWayland = @import("gdk-wayland");
    const toplevel = g.ext.cast(gdkWayland.WaylandToplevel, surface.?).?;
    const allocator = std.heap.page_allocator;
    const class_ = allocator.dupeZ(u8, class) catch unreachable;
    defer allocator.free(class_);
    toplevel.setApplicationId(class_);
}
