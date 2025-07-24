const c = @cImport({
    @cInclude("gtk/gtk.h");
    @cInclude("gdk/wayland/gdkwayland.h");
});
const std = @import("std");
extern fn gtk_init() void;

pub const init = gtk_init;
pub const StyleContext = extern struct {
    const Self = @This();
    parent_instance: *anyopaque,

    extern fn gtk_style_context_add_provider(context: *StyleContext, provider: ?*CssProvider, priority: c_uint) void;
    pub fn addCssProvider(
        self: *Self,
        provider: *CssProvider,
    ) void {
        gtk_style_context_add_provider(self, provider, c.GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    }
};
pub const Widget = extern struct {
    const Self = @This();
    parent_instance: *anyopaque,
    pub const Signal = enum {
        destroy,
        hide,
        show,
        map,
    };
    extern fn gtk_widget_show(widget: *Widget) void;
    extern fn gtk_widget_hide(widget: *Widget) void;
    extern fn gtk_widget_get_style_context(widget: *Widget) *StyleContext;
    extern fn gtk_widget_get_visible(widget: *Widget) c.gboolean;
    extern fn gtk_widget_get_first_child(widget: *Widget) ?*Widget;
    extern fn gtk_widget_get_last_child(widget: *Widget) ?*Widget;
    pub fn show(self: *Self) void {
        gtk_widget_show(self);
    }
    pub fn hide(self: *Self) void {
        gtk_widget_hide(self);
    }
    pub fn getFirstChild(self: *Self) ?*Widget {
        return gtk_widget_get_first_child(self);
    }
    pub fn getLastChild(self: *Self) ?*Widget {
        return gtk_widget_get_last_child(self);
    }
    pub fn as(self: *Self, comptime T: type) *T {
        return @ptrCast(self);
    }
    pub fn getStyleContext(self: *Self) *StyleContext {
        return gtk_widget_get_style_context(self);
    }
    pub fn getVisible(self: *Self) bool {
        return gtk_widget_get_visible(self) == 1;
    }
    pub fn connect(
        self: *Self,
        comptime signal: Signal,
        callback: *const fn (widget: *Self, data: ?*anyopaque) callconv(.c) void,
        data: ?*anyopaque,
    ) void {
        _ = c.g_signal_connect_data(@ptrCast(self), @ptrCast(@tagName(signal)), @ptrCast(callback), data, null, 0);
    }
    // pub fn disconnect(self: *Self, id: c_ulong) void {
    //     c.g_signal_handler_disconnect(@ptrCast(self), id);
    // }
};
pub const CssProvider = extern struct {
    const Self = @This();
    parent_instance: *anyopaque,
    extern fn gtk_css_provider_new() *CssProvider;
    extern fn gtk_css_provider_load_from_string(css_provider: *CssProvider, string: [*c]const u8) void;
    pub fn new() *CssProvider {
        return @ptrCast(gtk_css_provider_new());
    }
    pub fn loadFromString(self: *Self, string: []const u8) void {
        gtk_css_provider_load_from_string(self, string.ptr);
    }
    pub fn free(self: *Self) void {
        c.g_object_unref(self);
    }
};
pub const Window = extern struct {
    const Self = @This();
    pub const Signal = enum {
        closeRequest,
    };
    pub const Callback = struct {
        pub const CloseRequest = *const fn (widget: *Self, data: ?*anyopaque) callconv(.c) c_int;
    };
    parent_instance: *anyopaque,
    extern fn gtk_window_new() *Widget;
    extern fn gtk_window_present(window: *Window) void;
    extern fn gtk_window_destroy(window: *Window) void;
    extern fn gtk_window_set_child(window: *Window, child: *Widget) void;
    extern fn gtk_window_set_title(window: *Window, title: [*c]const u8) void;
    extern fn gtk_window_set_resizable(window: *Window, resizable: c_int) void;
    extern fn gtk_window_set_focus_visible(window: *Window, setting: c_int) void;
    pub fn getMonitor(self: *Self, allocator: std.mem.Allocator) !Monitor {
        const display = c.gdk_display_get_default();
        const surface = c.gtk_native_get_surface(@ptrCast(self));
        if (surface == null) {
            @panic("you should call this function after the window is realized");
        }
        const monitor = c.gdk_display_get_monitor_at_surface(display, surface);
        if (monitor == null) {
            @panic("you should call this function after the window is realized");
        }
        return Monitor.init(monitor.?, allocator);
    }
    pub fn setFocusVisible(self: *Self, setting: bool) void {
        gtk_window_set_focus_visible(self, @intFromBool(setting));
    }
    pub fn setInputRegion(self: *Self, region: ?*c.cairo_region_t) void {
        // TODO: 支持自定义输入区域
        if (region != null) @panic("not implemented");
        const surface = c.gtk_native_get_surface(@ptrCast(self));
        if (surface == null) {
            @panic("you should call this function after the window is realized");
        }
        const region_ = c.cairo_region_create();
        defer c.cairo_region_destroy(region_);
        c.gdk_surface_set_input_region(surface, region_);
    }
    pub fn getScale(self: *Self) f64 {
        const surface = c.gtk_native_get_surface(@ptrCast(self));
        if (surface == null) {
            @panic("you should call this function after the window is realized");
        }
        return c.gdk_surface_get_scale(surface);
    }
    pub const setChild = gtk_window_set_child;
    pub fn new() *Window {
        return @ptrCast(gtk_window_new());
    }
    pub fn asWidget(self: *Self) *Widget {
        return @ptrCast(self);
    }
    pub fn setClass(self: *Self, name: []const u8) void {
        const surface = c.gtk_native_get_surface(@ptrCast(self));
        if (surface == null) {
            @panic("you should call this function after the window is realized");
        }
        c.gdk_wayland_toplevel_set_application_id(c.GDK_TOPLEVEL(surface), name.ptr);
    }
    pub fn present(self: *Self) void {
        gtk_window_present(self);
    }
    pub fn destroy(self: *Self) void {
        gtk_window_destroy(self);
    }
    pub fn setTitle(self: *Self, title: []const u8) void {
        gtk_window_set_title(self, title.ptr);
    }
    pub fn setResizable(self: *Self, resizable: bool) void {
        gtk_window_set_resizable(self, @intFromBool(resizable));
    }
    pub fn setDefaultSize(self: *Self, width: i32, height: i32) void {
        c.gtk_window_set_default_size(@ptrCast(self), @intCast(width), @intCast(height));
    }
    pub fn setSize(self: *Self, width: i32, height: i32) void {
        c.gtk_widget_set_size_request(@ptrCast(self.asWidget()), @intCast(width), @intCast(height));
    }
    pub fn getSize(self: *Self, width: *i32, height: *i32) void {
        const surface = c.gtk_native_get_surface(@ptrCast(self));
        if (surface == null) {
            @panic("you should call this function after the window is realized");
        }
        width.* = @intCast(c.gdk_surface_get_width(surface));
        height.* = @intCast(c.gdk_surface_get_height(surface));
    }
    pub fn connect(
        self: *Self,
        comptime signal: Signal,
        callback: switch (signal) {
            .closeRequest => Callback.CloseRequest,
        },
        data: ?*anyopaque,
    ) void {
        const s = switch (signal) {
            .closeRequest => "close-request",
        };
        _ = c.g_signal_connect_data(@ptrCast(self), @ptrCast(s), @ptrCast(callback), data, null, 0);
    }
};
pub const Monitor = struct {
    scale: f64,
    width: i32,
    height: i32,
    widthMm: i32,
    heightMm: i32,
    connector: []const u8,
    description: []const u8,
    model: []const u8,
    refreshRate: f64,
    fn init(monitor: *c.GdkMonitor, allocator: std.mem.Allocator) !Monitor {
        var rect: c.GdkRectangle = undefined;
        c.gdk_monitor_get_geometry(monitor, &rect);
        const scale = c.gdk_monitor_get_scale(monitor);
        const connector = c.gdk_monitor_get_connector(monitor);
        const desc = c.gdk_monitor_get_description(monitor);
        const width_mm = c.gdk_monitor_get_height_mm(monitor);
        const height_mm = c.gdk_monitor_get_width_mm(monitor);
        const model = c.gdk_monitor_get_model(monitor);
        const refresh_rate = c.gdk_monitor_get_refresh_rate(monitor);

        return Monitor{
            .scale = scale,
            .width = @intCast(rect.width),
            .height = @intCast(rect.height),
            .widthMm = @intCast(width_mm),
            .heightMm = @intCast(height_mm),
            .connector = try allocator.dupe(u8, std.mem.span(connector)),
            .description = try allocator.dupe(u8, std.mem.span(desc)),
            .model = try allocator.dupe(u8, std.mem.span(model)),
            .refreshRate = @as(f64, @floatFromInt(refresh_rate)) / 1000.0,
        };
    }
    pub fn deinit(self: Monitor, allocator: std.mem.Allocator) void {
        allocator.free(self.connector);
        allocator.free(self.description);
        allocator.free(self.model);
    }
    pub fn list(allocator: std.mem.Allocator) ![]Monitor {
        const monitors = c.gdk_display_get_monitors(c.gdk_display_get_default());
        const len = c.g_list_model_get_n_items(monitors);
        var result = try allocator.alloc(Monitor, len);
        for (0..len) |i| {
            const monitor: *c.GdkMonitor = @ptrCast(c.g_list_model_get_item(monitors, @intCast(i)));
            result[i] = try Monitor.init(monitor, allocator);
        }
        return result;
    }
};
