const c = @cImport({
    @cInclude("gtk/gtk.h");
    @cInclude("webkit/webkit.h");
});
const std = @import("std");
const gtk = @import("gtk");
usingnamespace @cImport({
    @cInclude("gtk/gtk.h");
    @cInclude("webkit/webkit.h");
});
pub const WebView = extern struct {
    const Self = @This();
    parent_instance: *anyopaque,
    pub fn asWidget(self: *Self) *gtk.Widget {
        return @ptrCast(self);
    }
    extern fn webkit_web_view_new() *gtk.Widget;
    pub fn new() *WebView {
        return @ptrCast(webkit_web_view_new());
    }
    pub extern fn webkit_web_view_load_uri(*WebView, [*:0]const u8) void;
    pub const loadUri = webkit_web_view_load_uri;
    extern fn webkit_web_view_get_settings(*WebView) ?*Settings;
    pub const getSettings = webkit_web_view_get_settings;
    extern fn webkit_web_view_set_settings(*WebView, ?*Settings) void;
    pub const setSettings = webkit_web_view_set_settings;
};
pub const HardwareAccelerationPolicy = enum(u8) {
    Always = 0,
    Never = 1,
};
pub const Settings = extern struct {
    const Self = @This();
    parent_instance: *anyopaque,
    extern fn webkit_settings_get_hardware_acceleration_policy(?*Settings) c.WebKitHardwareAccelerationPolicy;
    pub fn getHardwareAccelerationPolicy(self: ?*Self) HardwareAccelerationPolicy {
        return @enumFromInt(webkit_settings_get_hardware_acceleration_policy(self));
    }
    extern fn webkit_settings_set_hardware_acceleration_policy(?*Settings, c_uint) void;
    pub fn setHardwareAccelerationPolicy(self: ?*Self, policy: HardwareAccelerationPolicy) void {
        webkit_settings_set_hardware_acceleration_policy(self, @intFromEnum(policy));
    }
};
