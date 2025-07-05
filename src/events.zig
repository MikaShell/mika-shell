const std = @import("std");

pub const Mika = struct {
    pub const Open = "mika-open";
    pub const Close = "mika-close";
    pub const Show = "mika-show";
    pub const Hide = "mika-hide";
};
pub const Tray = struct {
    pub const Added = "tray-added";
    pub const Removed = "tray-removed";
    pub const Changed = "tray-changed";
};
