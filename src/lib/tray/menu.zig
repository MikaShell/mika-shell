const std = @import("std");
const dbus = @import("dbus");
const testing = std.testing;
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const DBusNode = dbus.Struct(.{
    dbus.Int32,
    DBusProperties,
    dbus.Array(dbus.AnyVariant),
});
const DBusProperties = dbus.Dict(dbus.String, dbus.AnyVariant);
const Node = struct {
    id: i32,
    properties: Properties,
    children: []const Node,
    fn init(allocator: Allocator, dbusValue: DBusNode.Type) !Node {
        return .{
            .id = dbusValue[0],
            .properties = try Properties.init(allocator, dbusValue[1]),
            .children = blk: {
                const children = try allocator.alloc(Node, dbusValue[2].len);
                for (children, 0..) |*child, i| {
                    child.* = try Node.init(allocator, dbusValue[2][i].as(DBusNode));
                }
                break :blk children;
            },
        };
    }
    pub fn deinit(self: Node, allocator: Allocator) void {
        self.properties.deinit(allocator);
        for (self.children) |child| {
            child.deinit(allocator);
        }
        allocator.free(self.children);
    }
};
const ToggleType = enum {
    checkmark,
    radio,
};
const ToggleState = enum {
    unchecked,
    checked,
    indeterminate,
};
const Properties = struct {
    label: ?[]const u8 = null,
    visible: bool = true,
    enabled: bool = true,
    iconName: ?[]const u8 = null,
    iconData: ?[]const u8 = null,
    iconSize: ?i32 = null,
    childrenDisplay: ?[]const u8 = null,
    toggleType: ?ToggleType = null,
    toggleState: ?ToggleState = null,
    group: ?[]const u8 = null,
    shortcut: ?[]const []const u8 = null,
    shortcutLabel: ?[]const u8 = null,
    tooltip: ?[]const u8 = null,
    type: ?[]const u8 = null,
    childrenTypes: ?[]const []const u8 = null,
    action: ?[]const u8 = null,
    fn init(allocator: Allocator, props: DBusProperties.Type) !Properties {
        var self: Properties = .{};
        const eql = std.mem.eql;
        for (props) |v| {
            const value: dbus.AnyVariant.Type = v.value;
            if (eql(u8, v.key, "label")) {
                self.label = try allocator.dupe(u8, value.as(dbus.String));
                continue;
            }
            if (eql(u8, v.key, "visible")) {
                self.visible = value.as(dbus.Boolean);
                continue;
            }
            if (eql(u8, v.key, "enabled")) {
                self.enabled = value.as(dbus.Boolean);
                continue;
            }
            if (eql(u8, v.key, "icon-name")) {
                self.iconName = try allocator.dupe(u8, value.as(dbus.String));
                continue;
            }
            if (eql(u8, v.key, "icon-data")) {
                // TODO: 尝试解析其他格式的 icon-data
                if (value.tag != .string) @panic("icon-data must be a string, other types not supported");
                self.iconData = try allocator.dupe(u8, value.as(dbus.String));
                continue;
            }
            if (eql(u8, v.key, "icon-size")) {
                self.iconSize = value.as(dbus.Int32);
                continue;
            }
            if (eql(u8, v.key, "children-display")) {
                self.childrenDisplay = try allocator.dupe(u8, value.as(dbus.String));
                continue;
            }
            if (eql(u8, v.key, "toggle-type")) {
                const t = value.as(dbus.String);
                if (eql(u8, t, "checkmark")) {
                    self.toggleType = .checkmark;
                } else if (eql(u8, t, "radio")) {
                    self.toggleType = .radio;
                }
                continue;
            }
            if (eql(u8, v.key, "toggle-state")) {
                const t = value.as(dbus.Int32);
                if (t == 0) {
                    self.toggleState = .unchecked;
                } else if (t == 1) {
                    self.toggleState = .checked;
                } else if (t == 2) {
                    self.toggleState = .indeterminate;
                }
                continue;
            }
            if (eql(u8, v.key, "group")) {
                self.group = try allocator.dupe(u8, value.as(dbus.String));
                continue;
            }
            if (eql(u8, v.key, "shortcut")) {
                const shortcut = value.as(dbus.Array(dbus.String));
                const st = try allocator.alloc([]const u8, shortcut.len);
                for (st, 0..) |*s, i| {
                    s.* = try allocator.dupe(u8, shortcut[i]);
                }
                self.shortcut = st;
                continue;
            }
            if (eql(u8, v.key, "shortcut-label")) {
                self.shortcutLabel = try allocator.dupe(u8, value.as(dbus.String));
                continue;
            }
            if (eql(u8, v.key, "tooltip")) {
                self.tooltip = try allocator.dupe(u8, value.as(dbus.String));
                continue;
            }
            if (eql(u8, v.key, "type")) {
                self.type = try allocator.dupe(u8, value.as(dbus.String));
                continue;
            }
            if (eql(u8, v.key, "children-types")) {
                const types = value.as(dbus.Array(dbus.String));
                const ct = try allocator.alloc([]const u8, types.len);
                for (ct, 0..) |*t, i| {
                    t.* = try allocator.dupe(u8, types[i]);
                }
                self.childrenTypes = ct;
                continue;
            }
            if (eql(u8, v.key, "action")) {
                self.action = try allocator.dupe(u8, value.as(dbus.String));
                continue;
            }
        }
        return self;
    }
    fn deinit(self: Properties, allocator: Allocator) void {
        if (self.label) |label| allocator.free(label);
        if (self.iconName) |iconName| allocator.free(iconName);
        if (self.iconData) |iconData| allocator.free(iconData);
        if (self.childrenDisplay) |childrenDisplay| allocator.free(childrenDisplay);
        if (self.group) |group| allocator.free(group);
        if (self.shortcut) |shortcut| {
            for (shortcut) |s| allocator.free(s);
            allocator.free(shortcut);
        }
        if (self.shortcutLabel) |shortcutLabel| allocator.free(shortcutLabel);
        if (self.tooltip) |tooltip| allocator.free(tooltip);
        if (self.type) |t| allocator.free(t);
        if (self.childrenTypes) |childrenTypes| {
            for (childrenTypes) |t| allocator.free(t);
            allocator.free(childrenTypes);
        }
        if (self.action) |action| allocator.free(action);
    }
};
// test {
//     const allocator = testing.allocator;
//     const bus = try dbus.Bus.init(allocator, .Session);
//     defer bus.deinit();
//     const menu = try new(allocator, bus, ":1.1198", "/MenuBar");
//     defer menu.deinit(allocator);
//     const json = try std.json.Stringify.valueAlloc(allocator, menu, .{ .whitespace = .indent_4 });
//     defer allocator.free(json);
//     print("Menu:{s}\n", .{json});
//     try activate(allocator, bus, ":1.1198", "/MenuBar", 201);
// }
pub fn new(allocator: Allocator, bus: *dbus.Bus, owner: []const u8, path: []const u8) !Node {
    const result = try dbus.call(
        allocator,
        bus.conn,
        bus.err,
        owner,
        path,
        "com.canonical.dbusmenu",
        "GetLayout",
        .{ dbus.Int32, dbus.Int32, dbus.Array(dbus.String) },
        .{ 0, -1, &.{} },
    );

    defer result.deinit();
    return try Node.init(allocator, result.as(.{ dbus.UInt32, DBusNode })[1]);
}
pub fn activate(allocator: Allocator, bus: *dbus.Bus, owner: []const u8, path: []const u8, id: i32) !void {
    var err: dbus.Error = undefined;
    err.init();
    defer err.deinit();
    const Variant = dbus.Variant(dbus.Dict(dbus.String, dbus.AnyVariant));
    const result = try dbus.call(
        allocator,
        bus.conn,
        &err,
        owner,
        path,
        "com.canonical.dbusmenu",
        "Event",
        .{ dbus.Int32, dbus.String, Variant, dbus.UInt32 },
        .{ id, "clicked", Variant.init(&&.{}), 0 },
    );
    defer result.deinit();
}
