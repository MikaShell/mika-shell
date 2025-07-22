const std = @import("std");

pub const Mika = struct {
    pub const open = "mika-open";
    pub const close = "mika-close";
    pub const show = "mika-show";
    pub const hide = "mika-hide";
    pub const tryClose = "mika-try-close";
    pub const tryShow = "mika-try-show";
    pub const tryHide = "mika-try-hide";
};
pub const Window = struct {
    pub const show = "window-show";
    pub const hide = "window-hide";
};
pub const Layer = struct {
    pub const show = "layer-show";
    pub const hide = "layer-hide";
};
pub const Tray = struct {
    pub const added = "tray-added";
    pub const removed = "tray-removed";
    pub const changed = "tray-changed";
};
pub const Notifd = struct {
    pub const added = "notifd-added";
    pub const removed = "notifd-removed";
};
pub const Dock = struct {
    pub const added = "dock-added";
    pub const changed = "dock-changed";
    pub const closed = "dock-closed";
    pub const enter = "dock-entered";
    pub const leave = "dock-left";
    pub const activated = "dock-activated";
};
