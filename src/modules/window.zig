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
                .{ "openDevTools", openDevTools },
                .{ "setTitle", setTitle },
                .{ "setSize", setSize },
                .{ "getSize", getSize },
                .{ "getScaleFactor", getScale },
                .{ "setInputRegion", setInputRegion },
            },
        };
    }
    fn getWindow(self: *Self, ctx: *Context) !*Webview {
        const w = self.app.getWebview(ctx.caller) catch unreachable;
        if (w.type != .Window) {
            return error.WebviewIsNotAWindow;
        }
        return w;
    }
    // TODO: window 和 layer 增加 background-color 选项
    pub fn initWindow(self: *Self, ctx: *Context) !void {
        defer ctx.commit(null);
        const id = ctx.caller;
        const w = self.app.getWebview(id) catch unreachable;
        if (w.type == .Layer) {
            // 已经被初始化为 Layer, 无法再次初始化为 Window
            return error.WebviewIsAlreadyAWindow;
        }
        const allocator = std.heap.page_allocator;
        const options = try std.json.parseFromValue(Options, allocator, try ctx.args.value(0), .{});
        defer options.deinit();
        const opt = options.value;
        const onMapContext = struct {
            id: c_ulong,
            class: []const u8,
            resizable: bool,
        };
        const onMap = &struct {
            fn f(widget: *gtk.Widget, data: ?*anyopaque) callconv(.c) void {
                const ctx_: *onMapContext = @alignCast(@ptrCast(data));
                g.signalHandlerDisconnect(widget.as(g.Object), ctx_.id);
                const window = g.ext.cast(gtk.Window, widget).?;
                setClass(window, ctx_.class) catch unreachable;
                std.heap.page_allocator.free(ctx_.class);
                std.heap.page_allocator.destroy(ctx_);
            }
        }.f;

        if (w.type == .None) {
            // 这个回调只会执行一次
            const ctx_ = try std.heap.page_allocator.create(onMapContext);
            const id_ = g.signalConnectData(w.container.as(g.Object), "map", @ptrCast(onMap), ctx_, null, .flags_default);
            ctx_.* = .{
                .id = id_,
                .class = std.heap.page_allocator.dupe(u8, opt.class) catch unreachable,
                .resizable = opt.resizable,
            };
        }
        if (w.type == .Window) {
            setClass(w.container, opt.class) catch unreachable;
        }
        w.type = .Window;
        const title_ = try allocator.dupeZ(u8, opt.title);
        defer allocator.free(title_);
        w.container.setTitle(title_);
        if (opt.backgroundTransparent) {
            w.impl.setBackgroundColor(&.{ .f_red = 1, .f_green = 1, .f_blue = 1, .f_alpha = 0 });
        } else {
            w.impl.setBackgroundColor(&.{ .f_red = 1, .f_green = 1, .f_blue = 1, .f_alpha = 1 });
        }
        if (!opt.hidden) {
            self.app.showRequest(w);
        }
        w.container.setDefaultSize(opt.width, opt.height);
        w.container.setResizable(if (opt.resizable) 1 else 0);
    }
    pub fn openDevTools(self: *Self, ctx: *Context) !void {
        const w = try self.getWindow(ctx);
        w.impl.getInspector().show();
    }
    pub fn setTitle(self: *Self, ctx: *Context) !void {
        const w = try self.getWindow(ctx);
        const title = try ctx.args.string(1);
        const allocator = std.heap.page_allocator;
        const title_ = try allocator.dupeZ(u8, title);
        defer allocator.free(title_);
        w.container.setTitle(title_);
    }
    pub fn setSize(self: *Self, ctx: *Context) !void {
        const w = try self.getWindow(ctx);
        if (w.container.getResizable() == 1) {
            return ctx.errors("setSize is not allowed for resizable window", .{});
        }
        const width = try ctx.args.integer(1);
        const height = try ctx.args.integer(2);
        w.container.setDefaultSize(@intCast(width), @intCast(height));
    }
    pub fn getSize(self: *Self, ctx: *Context) !void {
        const w = try self.getWindow(ctx);
        const surface = w.container.as(gtk.Native).getSurface();
        if (surface == null) {
            return ctx.errors("you should call this function after the window is realized", .{});
        }
        ctx.commit(.{ .width = surface.?.getWidth(), .height = surface.?.getHeight() });
    }
    pub fn getScale(self: *Self, ctx: *Context) !void {
        const w = try self.getWindow(ctx);
        const surface = w.container.as(gtk.Native).getSurface();
        if (surface == null) {
            return ctx.errors("you should call this function after the window is realized", .{});
        }
        ctx.commit(surface.?.getScale());
    }
    pub fn setInputRegion(self: *Self, ctx: *Context) !void {
        const w = try self.getWindow(ctx);
        const surface = w.container.as(gtk.Native).getSurface();
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
