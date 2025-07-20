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
        return &.{
            .{ "init", initWindow },
            .{ "show", show },
            .{ "hide", hide },
            .{ "getId", getId },
            .{ "openDevTools", openDevTools },
            .{ "setTitle", setTitle },
            .{ "close", close },
            .{ "setSize", setSize },
            .{ "getSize", getSize },
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
        const ownedClass = try std.heap.page_allocator.dupeZ(u8, opt.class);
        if (w.type == .None) {
            // 这个回调只会执行一次
            w.container.asWidget().connect(.map, struct {
                fn f(widget: *gtk.Widget, data: ?*anyopaque) callconv(.c) void {
                    const class: [*:0]const u8 = @ptrCast(data);
                    const class_ = std.mem.span(class);
                    defer std.heap.page_allocator.free(class_);
                    widget.as(gtk.Window).setClass(class_);
                }
            }.f, @ptrCast(ownedClass.ptr));
        }
        if (w.type == .Window) {
            w.container.setClass(opt.class);
        }
        w.type = .Window;
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
        w.container.setDefaultSize(opt.width, opt.height);
        w.options = .{ .window = opt };
    }
    pub fn openDevTools(self: *Self, args: Args, _: *Result) !void {
        const w = try self.getWindow(args);
        w.impl.openDevTools();
    }
    pub fn setTitle(self: *Self, args: Args, _: *Result) !void {
        const w = try self.getWindow(args);
        const title = try args.string(1);
        w.container.setTitle(title);
    }
    pub fn getId(_: *Self, args: Args, result: *Result) !void {
        const id = args.uInteger(0) catch unreachable;
        result.commit(id);
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
    pub fn setSize(self: *Self, args: Args, result: *Result) !void {
        const w = try self.getWindow(args);
        if (w.options.window.resizable) {
            return result.errors("setSize is not allowed for resizable window", .{});
        }
        const width = try args.integer(1);
        const height = try args.integer(2);
        w.container.setDefaultSize(@intCast(width), @intCast(height));
    }
    pub fn getSize(self: *Self, args: Args, result: *Result) !void {
        const w = try self.getWindow(args);
        var width: i32 = undefined;
        var height: i32 = undefined;
        w.container.getSize(&width, &height);
        result.commit(.{ .width = width, .height = height });
    }
};
