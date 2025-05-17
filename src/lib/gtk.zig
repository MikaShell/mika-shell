const c = @cImport({
    @cInclude("gtk/gtk.h");
});

pub fn init() void {
    c.gtk_init();
}
