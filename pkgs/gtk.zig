const c = @cImport({
    @cInclude("gtk/gtk.h");
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
        Destroy,
    };
    pub const Callback = struct {
        pub const Destroy = *const fn (widget: *Self, data: ?*anyopaque) callconv(.c) void;
    };
    extern fn gtk_widget_show(widget: *Widget) void;
    extern fn gtk_widget_hide(widget: *Widget) void;
    extern fn gtk_widget_get_style_context(widget: *Widget) *StyleContext;
    extern fn gtk_widget_get_visible(widget: *Widget) c.gboolean;
    pub fn show(self: *Self) void {
        gtk_widget_show(self);
    }
    pub fn hide(self: *Self) void {
        gtk_widget_hide(self);
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
        callback: switch (signal) {
            .Destroy => Callback.Destroy,
        },
        data: ?*anyopaque,
    ) void {
        const s = switch (signal) {
            .Destroy => "destroy",
        };
        _ = c.g_signal_connect_data(@ptrCast(self), @ptrCast(s), @ptrCast(callback), data, null, 0);
    }
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
    parent_instance: *anyopaque,
    extern fn gtk_window_new() *Widget;
    extern fn gtk_window_present(window: *Window) void;
    extern fn gtk_window_destroy(window: *Window) void;
    extern fn gtk_window_set_child(window: *Window, child: *Widget) void;
    extern fn gtk_window_set_title(window: *Window, title: [*c]const u8) void;
    extern fn gtk_window_set_resizable(window: *Window, resizable: c_int) void;
    pub const setChild = gtk_window_set_child;
    pub fn new() *Window {
        return @ptrCast(gtk_window_new());
    }
    pub fn asWidget(self: *Self) *Widget {
        return @ptrCast(self);
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
};
