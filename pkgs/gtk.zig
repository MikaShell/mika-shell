const c = @cImport({
    @cInclude("gtk/gtk.h");
});
const std = @import("std");
fn on_activate(_: *c.GtkApplication, data: c.gpointer) callconv(.C) void {
    const app: *Application = @ptrCast(@alignCast(data));
    if (app.onActivate) |callback| {
        callback(app);
    }
}
pub const Application = struct {
    allocator: std.mem.Allocator,
    gtk_app: *c.GtkApplication,
    onActivate: ?*const fn (*@This()) void = null,
    pub fn init(allocator: std.mem.Allocator, id: []const u8) !*@This() {
        const gtk_app = c.gtk_application_new(@ptrCast(id), c.G_APPLICATION_FLAGS_NONE);
        const app = try allocator.create(Application);
        app.* = Application{
            .allocator = allocator,
            .gtk_app = gtk_app,
        };
        return app;
    }
    pub fn deinit(self: *@This()) void {
        c.g_object_unref(self.gtk_app);
        self.allocator.destroy(self);
    }

    pub fn run(self: *@This()) i32 {
        _ = c.g_signal_connect_data(
            @ptrCast(self.gtk_app),
            "activate",
            @ptrCast(&on_activate),
            self,
            null,
            0,
        );
        const state = c.g_application_run(@ptrCast(self.gtk_app), 0, null);
        return state;
    }
};
