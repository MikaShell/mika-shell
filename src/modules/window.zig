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
const modules = @import("modules.zig");
const Args = modules.Args;
const Result = modules.Result;
const Context = modules.Context;
const Registry = modules.Registry;
const Allocator = std.mem.Allocator;
const gtk = @import("gtk");
const g = @import("gobject");
pub const Window = struct {
    const Self = @This();
    app: *App,
    pub fn init(ctx: Context) !*Self {
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
    fn getWindow(self: *Self, args: Args) !*Webview {
        const id = args.uInteger(0) catch unreachable;
        const w = self.app.getWebview(id) catch unreachable;
        if (w.type != .Window) {
            return error.WebviewIsNotAWindow;
        }
        return w;
    }
    // TODO: window 和 layer 增加 background-color 选项
    pub fn initWindow(self: *Self, args: Args, _: *Result) !void {
        const id = args.uInteger(0) catch unreachable;
        const w = self.app.getWebview(id) catch unreachable;
        if (w.type == .Layer) {
            // 已经被初始化为 Layer, 无法再次初始化为 Window
            return error.WebviewIsAlreadyAWindow;
        }
        const allocator = std.heap.page_allocator;
        const options = try std.json.parseFromValue(Options, allocator, try args.value(1), .{});
        defer options.deinit();
        const opt = options.value;
        const onMapContext = struct {
            id: c_ulong,
            class: []const u8,
            resizable: bool,
        };
        const onMap = &struct {
            fn f(widget: *gtk.Widget, data: ?*anyopaque) callconv(.c) void {
                const ctx: *onMapContext = @alignCast(@ptrCast(data));
                g.signalHandlerDisconnect(widget.as(g.Object), ctx.id);
                const window = g.ext.cast(gtk.Window, widget).?;
                setClass(window, ctx.class);
                std.heap.page_allocator.free(ctx.class);
                std.heap.page_allocator.destroy(ctx);
            }
        }.f;

        if (w.type == .None) {
            // 这个回调只会执行一次
            const ctx = try std.heap.page_allocator.create(onMapContext);
            const id_ = g.signalConnectData(w.container.as(g.Object), "map", @ptrCast(onMap), ctx, null, .flags_default);
            ctx.* = .{
                .id = id_,
                .class = std.heap.page_allocator.dupe(u8, opt.class) catch unreachable,
                .resizable = opt.resizable,
            };
        }
        if (w.type == .Window) {
            setClass(w.container, opt.class);
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
    pub fn openDevTools(self: *Self, args: Args, _: *Result) !void {
        const w = try self.getWindow(args);
        w.impl.getInspector().show();
    }
    pub fn setTitle(self: *Self, args: Args, _: *Result) !void {
        const w = try self.getWindow(args);
        const title = try args.string(1);
        const allocator = std.heap.page_allocator;
        const title_ = try allocator.dupeZ(u8, title);
        defer allocator.free(title_);
        w.container.setTitle(title_);
    }
    pub fn setSize(self: *Self, args: Args, result: *Result) !void {
        const w = try self.getWindow(args);
        if (w.container.getResizable() == 1) {
            return result.errors("setSize is not allowed for resizable window", .{});
        }
        const width = try args.integer(1);
        const height = try args.integer(2);
        w.container.setDefaultSize(@intCast(width), @intCast(height));
    }
    pub fn getSize(self: *Self, args: Args, result: *Result) !void {
        const w = try self.getWindow(args);
        const surface = common.getSurface(w.container);
        result.commit(.{ .width = surface.getWidth(), .height = surface.getHeight() });
    }
    pub fn getScale(self: *Self, args: Args, result: *Result) !void {
        const w = try self.getWindow(args);
        const surface = common.getSurface(w.container);
        result.commit(surface.getScale());
    }
    pub fn setInputRegion(self: *Self, args: Args, _: *Result) !void {
        const w = try self.getWindow(args);
        const surface = common.getSurface(w.container);
        const cairo = @import("cairo");
        const region = cairo.Region.create();
        defer region.destroy();
        surface.setInputRegion(region);
    }
};
const common = @import("common.zig");
const gdk = @import("gdk");
fn setClass(window: *gtk.Window, class: []const u8) void {
    const surface = common.getSurface(window);
    const gdkWayland = @import("gdk-wayland");
    const toplevel = g.ext.cast(gdkWayland.WaylandToplevel, surface).?;
    const allocator = std.heap.page_allocator;
    const class_ = allocator.dupeZ(u8, class) catch unreachable;
    defer allocator.free(class_);
    toplevel.setApplicationId(class_);
}
