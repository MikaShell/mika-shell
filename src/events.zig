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
pub const Tray = struct {
    pub const added = "tray-added";
    pub const removed = "tray-removed";
    pub const changed = "tray-changed";
};
