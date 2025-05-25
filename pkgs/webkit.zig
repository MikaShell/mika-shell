const c = @cImport({
    @cInclude("gtk/gtk.h");
    @cInclude("webkit/webkit.h");
});
const std = @import("std");
const gtk = @import("gtk");
usingnamespace @cImport({
    @cInclude("gtk/gtk.h");
    @cInclude("webkit/webkit.h");
    @cInclude("jsc/jsc.h");
});
const GCallback = ?*const fn () callconv(.c) void;
pub const GClosureNotify = ?*const fn (?*anyopaque, ?*anyopaque) callconv(.c) void;

extern fn g_signal_connect_data(
    instance: ?*anyopaque,
    detailed_signal: [*:0]const u8,
    c_handler: GCallback,
    data: ?*anyopaque,
    destroy_data: GClosureNotify,
    connect_flags: c_int,
) void;

pub const WebsiteDataManager = extern struct {
    const Self = @This();
    parent_instance: *anyopaque,
    extern fn webkit_website_data_manager_get_base_data_directory(self: *Self) [*:0]const u8;
    extern fn webkit_website_data_manager_is_ephemeral(self: *Self) gboolean;
    pub fn getBaseDataDirectory(self: *Self) [*:0]const u8 {
        return webkit_website_data_manager_get_base_data_directory(self);
    }
    pub fn isEphemeral(self: *Self) bool {
        return boolFromGboolean(webkit_website_data_manager_is_ephemeral(self));
    }
};
pub const NetworkSession = extern struct {
    const Self = @This();
    parent_instance: *anyopaque,
    extern fn webkit_network_session_is_ephemeral(self: *Self) gboolean;
    extern fn webkit_network_session_get_website_data_manager(self: *Self) ?*WebsiteDataManager;
    pub fn isEphemeral(self: *Self) bool {
        return boolFromGboolean(webkit_network_session_is_ephemeral(self));
    }
    pub const getWebsiteDataManager = webkit_network_session_get_website_data_manager;
};

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
    pub fn destroy(self: *Self) void {
        self.asWidget().destroy();
    }
    extern fn webkit_web_view_load_uri(*WebView, [*:0]const u8) void;
    extern fn webkit_web_view_load_html(*WebView, [*:0]u8, [*:0]const u8) void;
    extern fn webkit_web_view_get_settings(*WebView) ?*Settings;
    extern fn webkit_web_view_set_settings(*WebView, ?*Settings) void;
    extern fn webkit_web_view_get_user_content_manager(*WebView) ?*UserContentManager;
    extern fn webkit_web_view_get_network_session(self: *Self) ?*NetworkSession;
    extern fn webkit_web_view_get_page_id(self: *Self) c_ulong;
    extern fn webkit_web_view_get_title(self: *Self) [*:0]const u8;
    extern fn webkit_web_view_get_uri(self: *Self) [*:0]const u8;
    pub fn loadUri(self: *Self, uri: [*:0]const u8) void {
        webkit_web_view_load_uri(self, uri);
    }
    pub fn loadHtml(self: *Self, html: []u8, baseUrl: [*:0]const u8) void {
        webkit_web_view_load_html(self, @ptrCast(html.ptr), baseUrl);
    }
    pub const setSettings = webkit_web_view_set_settings;
    pub const getSettings = webkit_web_view_get_settings;
    pub const getUserContentManager = webkit_web_view_get_user_content_manager;
    pub const getNetworkSession = webkit_web_view_get_network_session;
    pub const getPageId = webkit_web_view_get_page_id;
    pub const getTitle = webkit_web_view_get_title;
    pub const getUri = webkit_web_view_get_uri;
};
pub const JSCContext = extern struct {
    const Self = @This();
    extern fn jsc_context_new() *JSCContext;
    extern fn jsc_value_new_undefined(self: *Self) *JSCValue;
    extern fn jsc_value_new_from_json(self: *Self, json: [*:0]const u8) *JSCValue;
    pub const newUndefined = jsc_value_new_undefined;
    pub const newFromJson = jsc_value_new_from_json;
    pub const new = jsc_context_new;
};
pub const gboolean = c_int;
fn boolFromGboolean(value: gboolean) bool {
    return value == 1;
}
pub const JSCValue = extern struct {
    const Self = @This();
    extern fn jsc_value_to_json(value: *Self, indent: c_uint) [*:0]u8;
    extern fn jsc_value_get_context(self: *Self) *JSCContext;
    pub const getContext = jsc_value_get_context;
    pub fn toJson(self: *Self, indent: u32) []const u8 {
        return std.mem.span(jsc_value_to_json(self, indent));
    }
};
pub const ScriptMessageReply = extern struct {
    const Self = @This();
    extern fn webkit_script_message_reply_return_value(script_message_reply: ?*ScriptMessageReply, reply_value: ?*JSCValue) void;
    extern fn webkit_script_message_reply_return_error_message(script_message_reply: ?*ScriptMessageReply, error_message: [*:0]const u8) void;
    pub fn value(self: *Self, value_: ?*JSCValue) void {
        webkit_script_message_reply_return_value(self, value_);
    }
    pub fn errorMessage(self: *Self, message: [*:0]const u8) void {
        webkit_script_message_reply_return_error_message(self, message);
    }
};
pub const UserContentManager = extern struct {
    const Self = @This();
    pub const Signal = enum {
        ScriptMessageReceived,
        ScriptMessageWithReplyReceived,
    };
    pub const Callback = struct {
        pub const ScriptMessageReceived = *const fn (self: *Self, value: *JSCValue, data: ?*anyopaque) callconv(.c) void;
        pub const ScriptMessageWithReplyReceived = *const fn (self: *Self, value: *JSCValue, reply: *ScriptMessageReply, data: ?*anyopaque) callconv(.c) c_int;
    };
    parent_instance: *anyopaque,
    extern fn webkit_user_content_manager_register_script_message_handler_with_reply(self: *Self, name: [*:0]const u8, world_name: ?[*:0]const u8) gboolean;
    extern fn webkit_user_content_manager_register_script_message_handler(self: *Self, name: [*:0]const u8, world_name: ?[*:0]const u8) gboolean;
    pub fn registerScriptMessageHandler(self: *Self, name: [*:0]const u8, world_name: ?[*:0]const u8) bool {
        return boolFromGboolean(webkit_user_content_manager_register_script_message_handler(self, name, world_name));
    }
    pub fn registerScriptMessageHandlerWithReply(self: *Self, name: [*:0]const u8, world_name: ?[*:0]const u8) bool {
        return boolFromGboolean(webkit_user_content_manager_register_script_message_handler_with_reply(self, name, world_name));
    }
    pub fn connect(
        self: *Self,
        comptime signal: Signal,
        name: []const u8,
        callback: switch (signal) {
            .ScriptMessageReceived => Callback.ScriptMessageReceived,
            .ScriptMessageWithReplyReceived => Callback.ScriptMessageWithReplyReceived,
        },
        data: ?*anyopaque,
    ) void {
        const allocator = std.heap.page_allocator;
        const s = switch (signal) {
            .ScriptMessageReceived => "script-message-received",
            .ScriptMessageWithReplyReceived => "script-message-with-reply-received",
        };
        const signal_ = std.fmt.allocPrint(allocator, "{s}::{s}", .{ s, name }) catch unreachable;
        defer allocator.free(signal_);
        g_signal_connect_data(@ptrCast(self), @ptrCast(signal_), @ptrCast(callback), data, null, 0);
    }
};
pub const HardwareAccelerationPolicy = enum(u8) {
    Always = 0,
    Never = 1,
};
pub const Settings = extern struct {
    const Self = @This();
    parent_instance: *anyopaque,
    extern fn webkit_settings_get_hardware_acceleration_policy(?*Settings) c.WebKitHardwareAccelerationPolicy;
    extern fn webkit_settings_set_hardware_acceleration_policy(?*Settings, c_uint) void;
    extern fn webkit_settings_set_enable_developer_extras(?*Settings, gboolean) void;
    extern fn webkit_settings_get_enable_developer_extras(?*Settings) gboolean;
    pub fn getHardwareAccelerationPolicy(self: *Self) HardwareAccelerationPolicy {
        return @enumFromInt(webkit_settings_get_hardware_acceleration_policy(self));
    }
    pub fn setHardwareAccelerationPolicy(self: *Self, policy: HardwareAccelerationPolicy) void {
        webkit_settings_set_hardware_acceleration_policy(self, @intFromEnum(policy));
    }
    pub fn setEnableDeveloperExtras(self: *Self, enable: bool) void {
        webkit_settings_set_enable_developer_extras(self, @intFromBool(enable));
    }
    pub fn getEnableDeveloperExtras(self: *Self) bool {
        return boolFromGboolean(webkit_settings_get_enable_developer_extras(self));
    }
    // webkit_website_data_manager_fetch(manager: ?*WebKitWebsiteDataManager, types: WebKitWebsiteDataTypes, cancellable: [*c]GCancellable, callback: GAsyncReadyCallback, user_data: gpointer)
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
    extern fn g_cancellable_is_cancelled(cancellable: *GCancellable) gboolean;
    pub fn isCancelled(self: *Self) bool {
        return boolFromGboolean(g_cancellable_is_cancelled(self));
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
    extern fn webkit_uri_scheme_request_get_uri(request: ?*URISchemeRequest) [*:0]const u8;
    extern fn webkit_uri_scheme_request_get_path(request: ?*URISchemeRequest) [*:0]const u8;
    extern fn webkit_uri_scheme_request_get_web_view(request: ?*URISchemeRequest) *WebView;
    extern fn webkit_uri_scheme_request_get_http_method(request: ?*URISchemeRequest) [*:0]const u8;
    extern fn webkit_uri_scheme_request_get_http_body(request: ?*URISchemeRequest) *GInputStream;
    extern fn webkit_uri_scheme_request_finish(request: ?*URISchemeRequest, stream: *GInputStream, stream_length: c_long, content_type: [*:0]const u8) void;
    extern fn webkit_uri_scheme_request_finish_with_response(request: ?*URISchemeRequest, response: ?*URISchemeResponse) void;
    extern fn webkit_uri_scheme_request_finish_error(request: ?*URISchemeRequest, @"error": *GError) void;
    pub const getScheme = webkit_uri_scheme_request_get_scheme;
    pub const getUri = webkit_uri_scheme_request_get_uri;
    pub const getPath = webkit_uri_scheme_request_get_path;
    pub const getWebView = webkit_uri_scheme_request_get_web_view;
    pub const getHttpMethod = webkit_uri_scheme_request_get_http_method;
    pub const getHttpBody = webkit_uri_scheme_request_get_http_body;
    pub const finish = webkit_uri_scheme_request_finish;
    pub const finishWithResponse = webkit_uri_scheme_request_finish_with_response;
    pub const finishError = webkit_uri_scheme_request_finish_error;
};
pub const Context = extern struct {
    const Self = @This();
    parent_instance: *anyopaque,
    pub fn free(self: *Self) void {
        g_object_unref(@ptrCast(self));
    }
    extern fn webkit_web_context_get_default() ?*Context;
    extern fn webkit_web_context_register_uri_scheme(
        ?*Context,
        name: [*:0]const u8,
        callback: ?*const fn (request: ?*URISchemeRequest, data: *anyopaque) callconv(.C) void,
        data: ?*anyopaque,
        destryCallback: ?*c.GDestroyNotify,
    ) void;
    pub const getDefault = webkit_web_context_get_default;
    pub const registerUriScheme = webkit_web_context_register_uri_scheme;
};
