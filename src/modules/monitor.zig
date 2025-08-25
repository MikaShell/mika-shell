const std = @import("std");
const modules = @import("modules.zig");
const Args = modules.Args;
const Result = modules.Result;
const Context = modules.Context;
const Registry = modules.Registry;
const Allocator = std.mem.Allocator;
const App = @import("../app.zig").App;
const gtk = @import("gtk");
pub const Monitor = struct {
    const Self = @This();
    allocator: Allocator,
    app: *App,
    pub fn init(ctx: Context) !*Self {
        const self = try ctx.allocator.create(Self);
        self.allocator = ctx.allocator;
        self.app = ctx.app;
        return self;
    }
    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.destroy(self);
    }
    pub fn register() Registry(Self) {
        return .{
            .exports = &.{
                .{ "list", list },
                .{ "get", get },
            },
        };
    }
    pub fn list(self: *Self, _: Args, result: *Result) !void {
        const allocator = self.allocator;
        const monitors = try Monitor_.list(allocator);
        defer allocator.free(monitors);
        defer for (monitors) |monitor| monitor.deinit();
        result.commit(monitors);
    }
    pub fn get(self: *Self, args: Args, result: *Result) !void {
        const id = args.uInteger(0) catch unreachable;
        const w = try self.app.getWebview(id);
        const display = gdk.Display.getDefault().?;
        const surface = w.container.as(gtk.Native).getSurface();
        if (surface == null) {
            @panic("you should call this function after the window is realized");
        }
        const monitor = gdk.Display.getMonitorAtSurface(display, surface.?);
        if (monitor == null) {
            @panic("you should call this function after the window is realized");
        }
        const m = try Monitor_.init(monitor.?);
        defer m.deinit();
        result.commit(m);
    }
};
const gdk = @import("gdk");
const glib = @import("zglib");
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
