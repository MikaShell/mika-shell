const std = @import("std");

pub const Edge = enum(c_int) {
    left,
    right,
    top,
    bottom,
};
pub const Layers = enum(c_int) {
    background,
    bottom,
    top,
    overlay,
};

pub const KeyboardMode = enum(c_int) {
    none,
    exclusive,
    onDemand,
};
extern fn gtk_layer_set_monitor(window: *gtk.Window, monitor: *gdk.Monitor) void;
extern fn gtk_layer_init_for_window(window: *gtk.Window) void;
extern fn gtk_layer_is_layer_window(window: *gtk.Window) c_int;
extern fn gtk_layer_set_namespace(window: *gtk.Window, name_space: [*c]const u8) void;
extern fn gtk_layer_get_namespace(window: *gtk.Window) [*c]const u8;
extern fn gtk_layer_set_layer(window: *gtk.Window, layer: Layers) void;
extern fn gtk_layer_get_layer(window: *gtk.Window) Layers;
extern fn gtk_layer_set_anchor(window: *gtk.Window, edge: Edge, anchor_to_edge: c_int) void;
extern fn gtk_layer_get_anchor(window: *gtk.Window, edge: Edge) c_int;
extern fn gtk_layer_set_margin(window: *gtk.Window, edge: Edge, margin_size: c_int) void;
extern fn gtk_layer_get_margin(window: *gtk.Window, edge: Edge) c_int;
extern fn gtk_layer_set_exclusive_zone(window: *gtk.Window, exclusive_zone: c_int) void;
extern fn gtk_layer_get_exclusive_zone(window: *gtk.Window) c_int;
extern fn gtk_layer_auto_exclusive_zone_enable(window: *gtk.Window) void;
extern fn gtk_layer_auto_exclusive_zone_is_enabled(window: *gtk.Window) c_int;
extern fn gtk_layer_set_keyboard_mode(window: *gtk.Window, mode: KeyboardMode) void;
extern fn gtk_layer_get_keyboard_mode(window: *gtk.Window) KeyboardMode;

const initForWindow = gtk_layer_init_for_window;
const gtk = @import("gtk");
const gdk = @import("gdk");
pub const Layer = struct {
    inner: *gtk.Window,
    pub fn init(window: *gtk.Window) Layer {
        const l = Layer{
            .inner = window,
        };
        if (!l.isLayer()) {
            gtk_layer_init_for_window(l.inner);
        }
        return l;
    }
    pub fn isLayer(self: Layer) bool {
        return gtk_layer_is_layer_window(self.inner) == 1;
    }
    pub fn setMonitor(self: Layer, index: i32) !void {
        const list = gdk.Display.getDefault().?.getMonitors();
        const len = list.getNItems();
        if (index < 0 or index >= len) {
            return error.CanNotFindMonitor;
        }
        const monitor = list.getItem(@intCast(index));
        gtk_layer_set_monitor(self.inner, @ptrCast(monitor));
    }
    pub fn setNamespace(self: Layer, namespace: []const u8) void {
        gtk_layer_set_namespace(self.inner, namespace.ptr);
    }
    pub fn getNamespace(self: Layer) []const u8 {
        return std.mem.span(gtk_layer_get_namespace(self.inner));
    }
    pub fn setLayer(self: Layer, layer: Layers) void {
        gtk_layer_set_layer(self.inner, layer);
    }
    pub fn getLayer(self: Layer) Layers {
        return gtk_layer_get_layer(self.inner);
    }
    pub fn setAnchor(self: Layer, edge: Edge, anchorToEdge: bool) void {
        gtk_layer_set_anchor(self.inner, edge, @intFromBool(anchorToEdge));
    }
    pub fn getAnchor(self: Layer, edge: Edge) bool {
        return gtk_layer_get_anchor(self.inner, edge) == 1;
    }
    pub fn resetAnchor(self: Layer) void {
        for (std.enums.values(Edge)) |e| {
            self.setAnchor(e, false);
        }
    }
    pub fn setMargin(self: Layer, edge: Edge, marginSize: i32) void {
        gtk_layer_set_margin(self.inner, edge, marginSize);
    }
    pub fn getMargin(self: Layer, edge: Edge) i32 {
        return gtk_layer_get_margin(self.inner, edge);
    }
    pub fn setExclusiveZone(self: Layer, exclusiveZone: i32) void {
        gtk_layer_set_exclusive_zone(self.inner, exclusiveZone);
    }
    pub fn getExclusiveZone(self: Layer) i32 {
        return gtk_layer_get_exclusive_zone(self.inner);
    }
    pub fn autoExclusiveZoneEnable(self: Layer) void {
        gtk_layer_auto_exclusive_zone_enable(self.inner);
    }
    pub fn autoExclusiveZoneIsEnabled(self: Layer) bool {
        return gtk_layer_auto_exclusive_zone_is_enabled(self.inner) == 1;
    }
    pub fn setKeyboardMode(self: Layer, mode: KeyboardMode) void {
        gtk_layer_set_keyboard_mode(self.inner, mode);
    }
    pub fn getKeyboardMode(self: Layer) KeyboardMode {
        return gtk_layer_get_keyboard_mode(self.inner);
    }
};
