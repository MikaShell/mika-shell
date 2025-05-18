const gtk = @import("gtk");
const webkit = @import("webkit");
const std = @import("std");
const c = @cImport({
    @cInclude("gtk/gtk.h");
});
pub fn main() !void {
    gtk.init();
    const window = gtk.Window.new();
    const webview = webkit.WebView.new();
    const settings = webview.getSettings() orelse return error.FailedToGetSettings;
    settings.setHardwareAccelerationPolicy(webkit.HardwareAccelerationPolicy.Never);
    webview.loadUri("https://www.google.com");
    window.setChild(webview.asWidget());
    window.present();
    while (true) {
        _ = gtk.mainIteration();
    }
}
