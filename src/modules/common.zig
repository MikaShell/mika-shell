const gtk = @import("gtk");
const gdk = @import("gdk");
pub fn getSurface(window: *gtk.Window) *gdk.Surface {
    const surface = window.as(gtk.Native).getSurface();
    if (surface == null) {
        @panic("you should call this function after the window is realized");
    }
    return surface.?;
}
