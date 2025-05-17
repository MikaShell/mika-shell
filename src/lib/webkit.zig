const c = @cImport({
    @cInclude("webkit/webkit.h");
});

pub fn version() u32 {
    return @intCast(c.webkit_get_major_version());
}
