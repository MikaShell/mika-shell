const std = @import("std");
const webkit = @import("webkit");
const modules = @import("root.zig");
const Context = modules.InitContext;
const Registry = modules.Registry;
const CallContext = modules.Context;
const Allocator = std.mem.Allocator;
const App = @import("../app.zig").App;
const Webview = @import("../app.zig").Webview;
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
                .{ "list", list },
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
    pub fn getConfigDir(self: *Self, ctx: *CallContext) !void {
        ctx.commit(self.app.configDir);
    }
    pub fn subscribe(self: *Self, ctx: *CallContext) !void {
        const event = try ctx.args.uInteger(0);
        try self.app.emitter.subscribe(ctx.caller, @enumFromInt(event));
    }
    pub fn unsubcribe(self: *Self, ctx: *CallContext) !void {
        const event = try ctx.args.uInteger(0);
        try self.app.emitter.unsubscribe(ctx.caller, @enumFromInt(event));
    }
    pub fn getId(_: *Self, ctx: *CallContext) !void {
        ctx.commit(ctx.caller);
    }
    pub fn open(self: *Self, ctx: *CallContext) !void {
        const pageName = try ctx.args.string(0);
        const webview = try self.app.open(pageName);
        ctx.commit(webview.id);
    }
    pub fn close(self: *Self, ctx: *CallContext) !void {
        var id = try ctx.args.uInteger(0);
        if (id == 0) id = ctx.caller;
        const w = try self.app.getWebview(id);
        self.app.closeRequest(w);
    }
    pub fn forceClose(self: *Self, ctx: *CallContext) !void {
        var id = try ctx.args.uInteger(0);
        if (id == 0) id = ctx.caller;
        const w = try self.app.getWebview(id);
        w.forceClose();
    }
    pub fn show(self: *Self, ctx: *CallContext) !void {
        var id = try ctx.args.uInteger(0);
        if (id == 0) id = ctx.caller;
        const w = try self.app.getWebview(id);
        self.app.showRequest(w);
    }
    pub fn forceShow(self: *Self, ctx: *CallContext) !void {
        var id = try ctx.args.uInteger(0);
        if (id == 0) id = ctx.caller;
        const w = try self.app.getWebview(id);
        w.forceShow();
    }
    pub fn hide(self: *Self, ctx: *CallContext) !void {
        var id = try ctx.args.uInteger(0);
        if (id == 0) id = ctx.caller;
        const w = try self.app.getWebview(id);
        self.app.hideRequest(w);
    }
    pub fn forceHide(self: *Self, ctx: *CallContext) !void {
        var id = try ctx.args.uInteger(0);
        if (id == 0) id = ctx.caller;
        const w = try self.app.getWebview(id);
        w.forceHide();
    }
    pub fn list(self: *Self, ctx: *CallContext) !void {
        const infos = try self.app.allocator.alloc(Webview.Info, self.app.webviews.items.len);
        defer self.app.allocator.free(infos);
        for (self.app.webviews.items, 0..) |w, i| {
            infos[i] = w.getInfo();
        }
        ctx.commit(infos);
    }
};
