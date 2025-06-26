const std = @import("std");

pub const Mikami = struct {
    pub const Open = "mikami-open";
    pub const Close = "mikami-close";
    pub const Show = "mikami-show";
    pub const Hide = "mikami-hide";
};
pub const Tray = struct {
    pub const Added = "tray-added";
    pub const Removed = "tray-removed";
    pub const Changed = "tray-changed";
};
