const std = @import("std");
const modules = @import("root.zig");
const Args = modules.Args;
const Context = modules.Context;
const InitContext = modules.InitContext;
const Registry = modules.Registry;
const Allocator = std.mem.Allocator;
const App = @import("../app.zig").App;
const gtk = @import("gtk");
const Screencopy = @import("wayland").Screencopy;
pub const Monitor = struct {
    const Self = @This();
    allocator: Allocator,
    app: *App,
    screencopy: ?*Screencopy.Manager,
    pub fn init(ctx: InitContext) !*Self {
        const self = try ctx.allocator.create(Self);
        self.allocator = ctx.allocator;
        self.app = ctx.app;
        self.screencopy = null;
        return self;
    }
    pub fn deinit(self: *Self, allocator: Allocator) void {
        if (self.screencopy) |screencopy| screencopy.deinit();
        allocator.destroy(self);
    }
    pub fn register() Registry(Self) {
        return .{
            .exports = &.{
                .{ "list", list },
                .{ "get", get },
                .{ "capture", capture },
            },
        };
    }
    pub fn capture(self: *Self, ctx: *Context) !void {
        const output = try ctx.args.integer(0);
        if (output < 0) {
            ctx.errors("Invalid output index, should be a positive integer", .{});
            return;
        }

        const quality: f32 = blk: {
            const i: ?i64 = ctx.args.integer(1) catch null;
            if (i == null) {
                break :blk @floatCast(try ctx.args.float(1));
            } else {
                break :blk @floatFromInt(i.?);
            }
        };
        if (quality > 100 or quality < 0) {
            ctx.errors("Invalid quality, should be a number between 0 and 100", .{});
            return;
        }
        const overlayCursor = try ctx.args.bool(2);

        const x = try ctx.args.integer(3);
        const y = try ctx.args.integer(4);
        const w = try ctx.args.integer(5);
        const h = try ctx.args.integer(6);
        if (x < 0 or y < 0 or w < 0 or h < 0) {
            ctx.errors("Invalid coordinates, should be positive integers", .{});
            return;
        }
        const Ctx = struct {
            result: modules.Async,
            allocator: Allocator,
        };
        if (self.screencopy == null) {
            self.screencopy = try Screencopy.Manager.init(self.allocator);
        }
        const ctx_ = try self.allocator.create(Ctx);
        ctx_.* = .{
            .result = ctx.@"async"(),
            .allocator = self.allocator,
        };
        const screencopy = self.screencopy.?;
        try screencopy.capture(struct {
            fn cb(err: ?anyerror, result: ?[]u8, data: ?*anyopaque) void {
                const ctx__: *Ctx = @alignCast(@ptrCast(data));
                defer ctx__.allocator.destroy(ctx__);
                if (err) |e| {
                    ctx__.result.errors("Error while capturing screen: {}", .{e});
                    return;
                }
                const allocator = ctx__.allocator;
                const base64 = webpToBase64(allocator, result.?) catch |e| {
                    ctx__.result.errors("Error while capturing screen: {}", .{e});
                    return;
                };
                defer allocator.free(base64);
                ctx__.result.commit(base64);
            }
        }.cb, ctx_, .{
            .output = @intCast(output),
            .overlayCursor = overlayCursor,
            .x = @intCast(x),
            .y = @intCast(y),
            .w = @intCast(w),
            .h = @intCast(h),
            .quality = @floatCast(quality),
        });
    }
    fn webpToBase64(allocator: std.mem.Allocator, webp: []const u8) ![]u8 {
        const encoder = std.base64.standard.Encoder;
        const base64 = try allocator.alloc(u8, encoder.calcSize(webp.len));
        defer allocator.free(base64);
        return try std.fmt.allocPrint(allocator, "data:image/webp;base64,{s}", .{encoder.encode(base64, webp)});
    }
    pub fn list(self: *Self, ctx: *Context) !void {
        const allocator = self.allocator;
        const monitors = try Monitor_.list(allocator);
        defer allocator.free(monitors);
        defer for (monitors) |monitor| monitor.deinit();
        ctx.commit(monitors);
    }
    pub fn get(self: *Self, ctx: *Context) !void {
        const w = try self.app.getWebview(ctx.caller);
        const display = gdk.Display.getDefault().?;
        const surface = w.container.as(gtk.Native).getSurface();
        if (surface == null) {
            return ctx.errors("you should call this function after the window is realized", .{});
        }
        const monitor = gdk.Display.getMonitorAtSurface(display, surface.?);
        if (monitor == null) {
            return ctx.errors("can't get monitor from surface", .{});
        }
        const m = try Monitor_.init(monitor.?);
        defer m.deinit();
        ctx.commit(m);
    }
};
const gdk = @import("gdk");
const glib = @import("glib");
const mem = std.mem;
const g = @import("gobject");
const Monitor_ = struct {
    const Self = @This();
    scale: f64,
    width: i32,
    height: i32,
    widthMm: i32,
    heightMm: i32,
    connector: ?[:0]const u8,
    description: ?[:0]const u8,
    model: ?[:0]const u8,
    refreshRate: f64,
    fn init(monitor: *gdk.Monitor) !Self {
        var rect: gdk.Rectangle = undefined;
        gdk.Monitor.getGeometry(monitor, &rect);
        const scale = gdk.Monitor.getScale(monitor);
        const connector = gdk.Monitor.getConnector(monitor);
        const desc = gdk.Monitor.getDescription(monitor);
        const width_mm = gdk.Monitor.getHeightMm(monitor);
        const height_mm = gdk.Monitor.getWidthMm(monitor);
        const model = gdk.Monitor.getModel(monitor);
        const refresh_rate = gdk.Monitor.getRefreshRate(monitor);

        return Self{
            .scale = scale,
            .width = @intCast(rect.f_width),
            .height = @intCast(rect.f_height),
            .widthMm = @intCast(width_mm),
            .heightMm = @intCast(height_mm),
            .connector = mem.span(connector),
            .description = mem.span(desc),
            .model = mem.span(model),
            .refreshRate = @as(f64, @floatFromInt(refresh_rate)) / 1000.0,
        };
    }
    pub fn deinit(self: Self) void {
        _ = self;
        // if (self.connector) |s| glib.free(@ptrCast(@constCast(s.ptr)));
        // if (self.description) |s| glib.free(@ptrCast(@constCast(s.ptr)));
        // if (self.model) |s| glib.free(@ptrCast(@constCast(s.ptr)));
    }
    pub fn list(allocator: mem.Allocator) ![]Self {
        const monitors = gdk.Display.getDefault().?.getMonitors();
        const len = monitors.getNItems();
        var result = try allocator.alloc(Self, @intCast(len));
        for (0..len) |i| {
            const monitor: *gdk.Monitor = @ptrCast(monitors.getItem(@intCast(i)));
            result[i] = try Self.init(monitor);
        }
        return result;
    }
};
