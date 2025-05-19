usingnamespace @cImport({
    @cInclude("gtk/gtk.h");
});
const c = @cImport({
    @cInclude("gtk/gtk.h");
});
const std = @import("std");
extern fn gtk_init() void;

pub fn mainIteration() bool {
    return c.g_main_context_iteration(null, 0) == 1;
}
pub const init = gtk_init;
pub const Widget = extern struct {
    const Self = @This();
    parent_instance: *anyopaque,
    extern fn gtk_widget_show(widget: *Widget) void;
    pub fn show(self: *Self) void {
        gtk_widget_show(self);
    }
    extern fn gtk_widget_hide(widget: *Widget) void;
    pub fn hide(self: *Self) void {
        c.gtk_widget_hide(self);
    }
    pub fn as(self: *Self, comptime T: type) *T {
        return @ptrCast(self);
    }
};
pub const Window = extern struct {
    const Self = @This();
    parent_instance: *anyopaque,
    extern fn gtk_window_new() *Widget;
    pub fn new() *Window {
        return @ptrCast(gtk_window_new());
    }
    pub fn asWidget(self: *Self) *Widget {
        return @ptrCast(self);
    }
    extern fn gtk_window_present(window: *Window) void;
    pub fn present(self: *Self) void {
        gtk_window_present(self);
    }
    pub fn destroy(self: *Self) void {
        c.gtk_window_destroy(self);
    }
    pub fn close(self: *Self) void {
        c.gtk_window_close(self);
    }
    extern fn gtk_window_set_child(window: *Window, child: *Widget) void;
    pub const setChild = gtk_window_set_child;
};
