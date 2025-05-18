const c = @cImport({
    @cInclude("gtk/gtk.h");
    @cInclude("webkit/webkit.h");
});

pub const Webview = c.WebKitWebView;
const gtk = @import("gtk");

pub fn createWebview(app: *gtk.Application, url: []const u8) *Webview {
    const gtk_app: *c.GtkApplication = @ptrCast(app.gtk_app);
    const window: *c.GtkWindow = @ptrCast(c.gtk_application_window_new(gtk_app));
    const webview = c.webkit_web_view_new();

    c.gtk_window_set_default_size(@ptrCast(window), 800, 600);

    const settings = c.webkit_web_view_get_settings(@ptrCast(webview));
    c.webkit_settings_set_enable_developer_extras(settings, 1);
    c.webkit_settings_set_hardware_acceleration_policy(settings, c.WEBKIT_HARDWARE_ACCELERATION_POLICY_NEVER);
    c.webkit_web_view_load_uri(@ptrCast(webview), @ptrCast(url));

    c.gtk_window_set_child(window, webview);
    c.gtk_window_present(window);

    return @ptrCast(webview);
}
