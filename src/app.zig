const std = @import("std");
const webkit = @import("webkit");
const WebviewType = enum {
    Window,
    Layer,
};
const WebviewOption = struct {
    type: WebviewType,
};
const Application = struct {
    _allocator: std.mem.Allocator,
    _webviewsOption: std.ArrayList(WebviewOption),
    _webviews: std.ArrayList(webkit.WebView),
    isRunnning: bool = false,
    pub fn init(allocator: std.mem.Allocator) !*Application {
        const app = try allocator.create(Application);
        app.* = Application{
            ._allocator = allocator,
            ._webviewsOption = std.ArrayList(WebviewOption).init(allocator),
            ._webviews = std.ArrayList(webkit.WebView).init(allocator),
        };
        return app;
    }
    pub fn deinit(app: *Application) void {
        app._webviewsOption.deinit();
        app._webviews.deinit();
        app.allocator.destroy(app);
    }
};
