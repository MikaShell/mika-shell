pub const Options = struct {
    parent: u32,
    hidden: bool,
    width: i32,
    height: i32,
    offsetX: i32,
    offsetY: i32,
    autoHide: bool,
    position: gtk.PositionType,
    positionTo: struct {
        x: i32,
        y: i32,
        w: i32,
        h: i32,
    },
    cascadePopdown: bool,
    backgroundTransparent: bool,
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
pub const Popover = struct {
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
                .{ "init", initPopover },
                .{ "getSize", getSize },
                .{ "setSize", setSize },
                .{ "getPosition", getPosition },
                .{ "setPosition", setPosition },
                .{ "getOffset", getOffset },
                .{ "setOffset", setOffset },
                .{ "getPositionTo", getPositionTo },
                .{ "setPositionTo", setPositionTo },
            },
        };
    }
    fn getWebview(self: *Self, ctx: *Context) !*Webview {
        const w = self.app.getWebviewWithId(ctx.caller) catch unreachable;
        if (w.container != .popover) {
            return error.WebviewIsNotAWindow;
        }
        return w;
    }
    pub fn initPopover(self: *Self, ctx: *Context) !void {
        const options = try std.json.parseFromValue(Options, ctx.arena, try ctx.args.value(0), .{});
        defer options.deinit();
        const opt = options.value;
        const parent = self.app.getWebviewWithId(opt.parent) catch {
            ctx.errors("Invalid parent webview id: {}", .{opt.parent});
            return;
        };
        switch (parent.container) {
            .none => {
                ctx.errors("Parent webview is not initialized, id: {}", .{parent.id});
            },
            else => {},
        }
        const webview = self.app.getWebviewWithId(ctx.caller) catch unreachable;
        switch (webview.container) {
            .none => {
                self.app.setupContianer(webview, .popover);
                const widget = webview.container.popover.as(gtk.Widget);
                switch (parent.container) {
                    .window => |w| widget.setParent(w.as(gtk.Widget)),
                    .layer => |l| widget.setParent(l.inner.as(gtk.Widget)),
                    else => unreachable,
                }
            },
            .layer, .window => {
                return error.WebviewAlreadyInitializedAsOtherType;
            },
            .popover => {},
        }
        if (opt.backgroundTransparent) {
            webview.impl.setBackgroundColor(&.{ .f_red = 1, .f_green = 1, .f_blue = 1, .f_alpha = 0 });
        } else {
            webview.impl.setBackgroundColor(&.{ .f_red = 1, .f_green = 1, .f_blue = 1, .f_alpha = 1 });
        }
        const popover = webview.container.popover;
        const widget = popover.as(gtk.Widget);
        widget.setSizeRequest(opt.width, opt.height);
        popover.setCascadePopdown(@intFromBool(opt.cascadePopdown));
        if (opt.positionTo.w != -1 or opt.positionTo.h != -1) {
            popover.setPointingTo(&.{
                .f_x = opt.positionTo.x,
                .f_y = opt.positionTo.y,
                .f_width = opt.positionTo.w,
                .f_height = opt.positionTo.h,
            });
        }
        popover.setPosition(opt.position);
        popover.setOffset(opt.offsetX, opt.offsetY);
        popover.setAutohide(@intFromBool(opt.autoHide));
        if (!opt.hidden) {
            self.app.showRequest(webview);
        }
    }
    pub fn getSize(self: *Self, ctx: *Context) !void {
        const webview = try self.getWebview(ctx);
        const surface = webview.container.popover.as(gtk.Native).getSurface();
        if (surface == null) {
            ctx.errors("you should call this function after the window is realized", .{});
            return;
        }
        ctx.commit(.{ .width = surface.?.getWidth(), .height = surface.?.getHeight() });
    }
    pub fn setSize(self: *Self, ctx: *Context) !void {
        const webview = try self.getWebview(ctx);
        const width = try ctx.args.integer(0);
        const height = try ctx.args.integer(1);
        const widget = webview.container.popover.as(gtk.Widget);
        widget.setSizeRequest(@intCast(width), @intCast(height));
    }
    pub fn getPosition(self: *Self, ctx: *Context) !void {
        const webview = try self.getWebview(ctx);
        const position = webview.container.popover.getPosition();
        ctx.commit(@as(i32, @intFromEnum(position)));
    }
    pub fn setPosition(self: *Self, ctx: *Context) !void {
        const webview = try self.getWebview(ctx);
        const position = try ctx.args.integer(0);
        if (position < 0 or position > 3) {
            ctx.errors("Invalid position value: {}", .{position});
            return;
        }
        webview.container.popover.setPosition(@enumFromInt(position));
    }
    pub fn getOffset(self: *Self, ctx: *Context) !void {
        const webview = try self.getWebview(ctx);
        var x: c_int = undefined;
        var y: c_int = undefined;
        webview.container.popover.getOffset(&x, &y);
        ctx.commit(.{ .x = x, .y = y });
    }
    pub fn setOffset(self: *Self, ctx: *Context) !void {
        const webview = try self.getWebview(ctx);
        const offsetX = try ctx.args.integer(0);
        const offsetY = try ctx.args.integer(1);
        webview.container.popover.setOffset(@intCast(offsetX), @intCast(offsetY));
    }
    pub fn getPositionTo(self: *Self, ctx: *Context) !void {
        const webview = try self.getWebview(ctx);
        var rect: @import("gdk").Rectangle = undefined;
        const ret = webview.container.popover.getPointingTo(&rect);
        if (ret == 0) {
            ctx.errors("Rect is not set", .{});
            return;
        }
        ctx.commit(.{ .x = rect.f_x, .y = rect.f_y, .w = rect.f_width, .h = rect.f_height });
    }
    pub fn setPositionTo(self: *Self, ctx: *Context) !void {
        const webview = try self.getWebview(ctx);
        const x = try ctx.args.integer(0);
        const y = try ctx.args.integer(1);
        const w = try ctx.args.integer(2);
        const h = try ctx.args.integer(3);
        webview.container.popover.setPointingTo(&.{
            .f_x = @intCast(x),
            .f_y = @intCast(y),
            .f_width = @intCast(w),
            .f_height = @intCast(h),
        });
    }
};
