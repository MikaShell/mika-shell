const std = @import("std");
const webkit = @import("webkit");
const gtk = @import("gtk");
const WebviewType = enum {
    Window,
    Layer,
};
const WebviewOption = struct {
    type: WebviewType,
    url: []u8,
};
