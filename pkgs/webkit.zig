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
    extern fn webkit_web_view_load_html(*WebView, [*:0]u8, [*:0]const u8) void;
    pub const loadHtml = webkit_web_view_load_html;
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
    extern fn webkit_settings_set_enable_developer_extras(?*Settings, c_int) void;
    pub fn setEnableDeveloperExtras(self: ?*Self, enable: bool) void {
        webkit_settings_set_enable_developer_extras(self, @intFromBool(enable));
    }
    extern fn webkit_settings_get_enable_developer_extras(?*Settings) c_int;
    pub fn getEnableDeveloperExtras(self: ?*Self) bool {
        return webkit_settings_get_enable_developer_extras(self) == 1;
    }
};
extern fn g_object_unref(object: ?*anyopaque) void;
pub const GCancellable = extern struct {
    const Self = @This();
    parent_instance: *anyopaque,
    pub fn free(self: *Self) void {
        g_object_unref(@ptrCast(self));
    }

    extern fn g_cancellable_new() *GCancellable;
    pub fn new() *GCancellable {
        return g_cancellable_new();
    }
    extern fn g_cancellable_is_cancelled(cancellable: *GCancellable) c_int;
    pub fn isCancelled(self: *Self) bool {
        return g_cancellable_is_cancelled(self) == 1;
    }
    // extern fn g_cancellable_set_error_if_cancelled(cancellable: *GCancellable, @"error": **GError) c_int;
    // extern fn g_cancellable_get_fd(cancellable: *GCancellable) c_int;
    // extern fn g_cancellable_make_pollfd(cancellable: *GCancellable, pollfd: *GPollFD) gboolean;
    // extern fn g_cancellable_release_fd(cancellable: *GCancellable) void;
    // extern fn g_cancellable_source_new(cancellable: *GCancellable) *GSource;
    // extern fn g_cancellable_get_current() *GCancellable;
    // extern fn g_cancellable_push_current(cancellable: *GCancellable) void;
    // extern fn g_cancellable_pop_current(cancellable: *GCancellable) void;
    // extern fn g_cancellable_reset(cancellable: *GCancellable) void;
    // extern fn g_cancellable_connect(cancellable: *GCancellable, callback: GCallback, data: gpointer, data_destroy_func: GDestroyNotify) gulong;
    // extern fn g_cancellable_disconnect(cancellable: *GCancellable, handler_id: gulong) void;
    extern fn g_cancellable_cancel(cancellable: *GCancellable) void;
    pub const cancel = g_cancellable_cancel;
};
pub const GInputStream = extern struct {
    const Self = @This();
    parent_instance: *anyopaque,
    pub fn free(self: *Self) void {
        g_object_unref(@ptrCast(self));
    }
    extern fn g_input_stream_read(stream: *GInputStream, buffer: ?*anyopaque, count: c_ulong, cancellable: *GCancellable, @"error": **GError) c_long;
    pub fn read(self: *Self, buffer: []u8, cancellable: *GCancellable, @"error": **GError) c_long {
        return g_input_stream_read(self, buffer.ptr, buffer.len, cancellable, @"error");
    }
    extern fn g_input_stream_read_all(stream: *GInputStream, buffer: ?*anyopaque, count: c_ulong, bytes_read: *c_ulong, cancellable: *GCancellable, @"error": **GError) c.gboolean;
    pub fn readAll(self: *Self, buffer: []u8, bytes_read: *c_ulong, cancellable: *GCancellable, @"error": **GError) bool {
        return g_input_stream_read_all(self, buffer.ptr, buffer.len, bytes_read, cancellable, @"error") == 1;
    }
    // extern fn g_input_stream_read_bytes(stream: *GInputStream, count: c_ulong, cancellable: *GCancellable, @"error": **GError) ?*GBytes;
    extern fn g_input_stream_skip(stream: *GInputStream, count: c_ulong, cancellable: *GCancellable, @"error": **GError) c_long;
    pub const skip = g_input_stream_skip;
    extern fn g_input_stream_close(stream: *GInputStream, cancellable: *GCancellable, @"error": **GError) c_int;
    pub const close = g_input_stream_close;
    // extern fn g_input_stream_read_async(stream: *GInputStream, buffer: ?*anyopaque, count: c_ulong, io_priority: c_int, cancellable: *GCancellable, callback: GAsyncReadyCallback, user_data: gpointer) void;
    // extern fn g_input_stream_read_finish(stream: *GInputStream, result: ?*GAsyncResult, @"error": **GError) c_long;
    // extern fn g_input_stream_read_all_async(stream: *GInputStream, buffer: ?*anyopaque, count: c_ulong, io_priority: c_int, cancellable: *GCancellable, callback: GAsyncReadyCallback, user_data: gpointer) void;
    // extern fn g_input_stream_read_all_finish(stream: *GInputStream, result: ?*GAsyncResult, bytes_read: *c_ulong, @"error": **GError) c_int;
    // extern fn g_input_stream_read_bytes_async(stream: *GInputStream, count: c_ulong, io_priority: c_int, cancellable: *GCancellable, callback: GAsyncReadyCallback, user_data: gpointer) void;
    // extern fn g_input_stream_read_bytes_finish(stream: *GInputStream, result: ?*GAsyncResult, @"error": **GError) ?*GBytes;
    // extern fn g_input_stream_skip_async(stream: *GInputStream, count: c_ulong, io_priority: c_int, cancellable: *GCancellable, callback: GAsyncReadyCallback, user_data: gpointer) void;
    // extern fn g_input_stream_skip_finish(stream: *GInputStream, result: ?*GAsyncResult, @"error": **GError) c_long;
    // extern fn g_input_stream_close_async(stream: *GInputStream, io_priority: c_int, cancellable: *GCancellable, callback: GAsyncReadyCallback, user_data: gpointer) void;
    // extern fn g_input_stream_close_finish(stream: *GInputStream, result: ?*GAsyncResult, @"error": **GError) c_int;
    // extern fn g_input_stream_is_closed(stream: *GInputStream) c_int;
    // extern fn g_input_stream_has_pending(stream: *GInputStream) c_int;
    // extern fn g_input_stream_set_pending(stream: *GInputStream, @"error": **GError) c_int;
    // extern fn g_input_stream_clear_pending(stream: *GInputStream) void;
};
pub const GError = extern struct {
    extern fn g_error_free(@"error": *GError) void;
    pub const free = g_error_free;
};
pub const URISchemeResponse = extern struct {
    const Self = @This();
    pub fn free(self: *Self) void {
        g_object_unref(@ptrCast(self));
    }
    extern fn webkit_uri_scheme_response_new(input_stream: *GInputStream, stream_length: c_long) ?*URISchemeResponse;
    pub const new = webkit_uri_scheme_response_new;
    extern fn webkit_uri_scheme_response_set_status(response: ?*URISchemeResponse, status_code: c_uint, reason_phrase: [*:0]const u8) void;
    pub const setStatus = webkit_uri_scheme_response_set_status;
    extern fn webkit_uri_scheme_response_set_content_type(response: ?*URISchemeResponse, content_type: [*:0]const u8) void;
    pub const setContentType = webkit_uri_scheme_response_set_content_type;
    // extern fn webkit_uri_scheme_response_set_http_headers(response: ?*URISchemeResponse, headers: ?*SoupMessageHeaders) void;
};
pub const URISchemeRequest = extern struct {
    const Self = @This();
    pub fn free(self: *Self) void {
        g_object_unref(@ptrCast(self));
    }
    extern fn webkit_uri_scheme_request_get_scheme(request: ?*URISchemeRequest) [*:0]const u8;
    pub const getScheme = webkit_uri_scheme_request_get_scheme;
    extern fn webkit_uri_scheme_request_get_uri(request: ?*URISchemeRequest) [*:0]const u8;
    pub const getUri = webkit_uri_scheme_request_get_uri;
    extern fn webkit_uri_scheme_request_get_path(request: ?*URISchemeRequest) [*:0]const u8;
    pub const getPath = webkit_uri_scheme_request_get_path;
    extern fn webkit_uri_scheme_request_get_web_view(request: ?*URISchemeRequest) *WebView;
    pub const getWebView = webkit_uri_scheme_request_get_web_view;
    extern fn webkit_uri_scheme_request_get_http_method(request: ?*URISchemeRequest) [*:0]const u8;
    pub const getHttpMethod = webkit_uri_scheme_request_get_http_method;
    extern fn webkit_uri_scheme_request_get_http_body(request: ?*URISchemeRequest) *GInputStream;
    pub const getHttpBody = webkit_uri_scheme_request_get_http_body;
    extern fn webkit_uri_scheme_request_finish(request: ?*URISchemeRequest, stream: *GInputStream, stream_length: c_long, content_type: [*:0]const u8) void;
    pub const finish = webkit_uri_scheme_request_finish;
    pub extern fn webkit_uri_scheme_request_finish_with_response(request: ?*URISchemeRequest, response: ?*URISchemeResponse) void;
    pub const finishWithResponse = webkit_uri_scheme_request_finish_with_response;
    extern fn webkit_uri_scheme_request_finish_error(request: ?*URISchemeRequest, @"error": *GError) void;
    pub const finishError = webkit_uri_scheme_request_finish_error;
};
pub const Context = extern struct {
    const Self = @This();
    parent_instance: *anyopaque,
    pub fn free(self: *Self) void {
        g_object_unref(@ptrCast(self));
    }
    extern fn webkit_web_context_get_default() ?*Context;
    pub const getDefault = webkit_web_context_get_default;
    extern fn webkit_web_context_register_uri_scheme(
        ?*Context,
        name: [*:0]const u8,
        callback: ?*const fn (request: ?*URISchemeRequest, data: *anyopaque) callconv(.C) void,
        data: ?*anyopaque,
        destryCallback: ?*c.GDestroyNotify,
    ) void;
    pub const registerUriScheme = webkit_web_context_register_uri_scheme;
};
