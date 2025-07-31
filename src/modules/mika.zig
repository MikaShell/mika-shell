const std = @import("std");
const webkit = @import("webkit");
const modules = @import("modules.zig");
const Args = modules.Args;
const Result = modules.Result;
const Context = modules.Context;
const Registry = modules.Registry;
const Allocator = std.mem.Allocator;
const App = @import("../app.zig").App;
const events = @import("../events.zig");
pub const Mika = struct {
    app: *App,
    const Self = @This();
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
                .{ "getId", getId },
                .{ "open", open },
                .{ "close", close },
                .{ "forceClose", forceClose },
                .{ "show", show },
                .{ "forceShow", forceShow },
                .{ "hide", hide },
                .{ "forceHide", forceHide },
                .{ "subscribe", subscribe },
                .{ "unsubscribe", unsubcribe },
                .{ "getConfigDir", getConfigDir },
            },
            .events = &.{
                .mika_close_request,
                .mika_show_request,
                .mika_hide_request,
                .mika_open,
                .mika_close,
                .mika_show,
                .mika_hide,
            },
        };
    }
    pub fn getConfigDir(self: *Self, _: Args, result: *Result) !void {
        result.commit(self.app.configDir);
    }
    pub fn subscribe(self: *Self, args: Args, _: *Result) !void {
        const event = try args.uInteger(1);
        try self.app.emitter.subscribe(args, @enumFromInt(event));
    }
    pub fn unsubcribe(self: *Self, args: Args, _: *Result) !void {
        const event = try args.uInteger(1);
        try self.app.emitter.unsubscribe(args, @enumFromInt(event));
    }
    pub fn getId(_: *Self, args: Args, result: *Result) !void {
        const id = args.uInteger(0) catch unreachable;
        result.commit(id);
    }
    pub fn open(self: *Self, args: Args, result: *Result) !void {
        const pageName = try args.string(1);
        const webview = try self.app.open(pageName);
        result.commit(webview.id);
    }
    pub fn close(self: *Self, args: Args, _: *Result) !void {
        var id = try args.uInteger(1);
        if (id == 0) id = args.uInteger(0) catch unreachable;
        const w = try self.app.getWebview(id);
        self.app.closeRequest(w);
    }
    pub fn forceClose(self: *Self, args: Args, _: *Result) !void {
        var id = try args.uInteger(1);
        if (id == 0) id = args.uInteger(0) catch unreachable;
        const w = try self.app.getWebview(id);
        w.forceClose();
    }
    pub fn show(self: *Self, args: Args, _: *Result) !void {
        var id = try args.uInteger(1);
        if (id == 0) id = args.uInteger(0) catch unreachable;
        const w = try self.app.getWebview(id);
        self.app.showRequest(w);
    }
    pub fn forceShow(self: *Self, args: Args, _: *Result) !void {
        var id = try args.uInteger(1);
        if (id == 0) id = args.uInteger(0) catch unreachable;
        const w = try self.app.getWebview(id);
        w.forceShow();
    }
    pub fn hide(self: *Self, args: Args, _: *Result) !void {
        var id = try args.uInteger(1);
        if (id == 0) id = args.uInteger(0) catch unreachable;
        const w = try self.app.getWebview(id);
        self.app.hideRequest(w);
    }
    pub fn forceHide(self: *Self, args: Args, _: *Result) !void {
        var id = try args.uInteger(1);
        if (id == 0) id = args.uInteger(0) catch unreachable;
        const w = try self.app.getWebview(id);
        w.forceHide();
    }
};
