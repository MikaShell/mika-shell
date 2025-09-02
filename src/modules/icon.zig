const ini = @import("ini");
const std = @import("std");
const testing = std.testing;

const Allocator = std.mem.Allocator;

const Theme = struct {
    path: []const u8,
    name: []const u8,
    comment: []const u8,
    inherits: [][]const u8,
    directories: []Directory,
    fn init(allocator: Allocator, reader: anytype) !Theme {
        var theme: Theme = undefined;
        theme.directories = &.{};
        theme.comment = "";
        theme.name = "";
        theme.inherits = &.{};
        theme.path = "";
        var section: []const u8 = "";
        defer allocator.free(section);
        const eql = std.mem.eql;
        var dirs = std.ArrayList([]const u8).init(allocator);
        defer dirs.deinit();
        var index: usize = undefined;
        var parser = ini.parse(allocator, reader, ";#");
        defer parser.deinit();
        while (parser.next() catch null) |record| {
            switch (record) {
                .section => |heading| {
                    for (dirs.items, 0..) |dir, i| {
                        if (eql(u8, dir, heading)) {
                            index = i;
                            break;
                        }
                    }
                    allocator.free(section);
                    section = try allocator.dupe(u8, heading);
                },
                .property => |prop| {
                    if (eql(u8, section, "Icon Theme")) {
                        if (eql(u8, prop.key, "Name")) theme.name = try allocator.dupe(u8, prop.value);
                        if (eql(u8, prop.key, "Comment")) theme.comment = try allocator.dupe(u8, prop.value);
                        if (eql(u8, prop.key, "Inherits")) {
                            var iter = std.mem.splitAny(u8, prop.value, ",");
                            var parents = std.ArrayList([]const u8).init(allocator);
                            defer parents.deinit();
                            while (iter.next()) |parent| {
                                try parents.append(try allocator.dupe(u8, parent));
                            }
                            theme.inherits = try parents.toOwnedSlice();
                        }
                        if (eql(u8, prop.key, "Directories")) {
                            var iter = std.mem.splitAny(u8, prop.value, ",");
                            while (iter.next()) |dir| {
                                try dirs.append(try allocator.dupe(u8, dir));
                            }
                            theme.directories = try allocator.alloc(Directory, dirs.items.len);
                            for (theme.directories, 0..) |*dir, i| {
                                dir.name = dirs.items[i];
                                dir.context = "";
                                dir.maxSize = 0;
                                dir.minSize = 0;
                                dir.scale = 1;
                                dir.size = 0;
                                dir.threshold = 2;
                                dir.type = .threshold;
                                dir.entrys = &.{};
                            }
                        }
                        continue;
                    }
                    if (eql(u8, prop.key, "Size")) {
                        const size = try std.fmt.parseInt(u32, prop.value, 10);
                        theme.directories[index].size = size;
                        if (theme.directories[index].maxSize == 0) theme.directories[index].maxSize = size;
                        if (theme.directories[index].minSize == 0) theme.directories[index].minSize = size;
                    }
                    if (eql(u8, prop.key, "Type")) {
                        if (eql(u8, prop.value, "Fixed")) theme.directories[index].type = .fixed;
                        if (eql(u8, prop.value, "Scalable")) theme.directories[index].type = .scalable;
                        if (eql(u8, prop.value, "Threshold")) theme.directories[index].type = .threshold;
                    }
                    if (eql(u8, prop.key, "MinSize")) {
                        theme.directories[index].minSize = try std.fmt.parseInt(u32, prop.value, 10);
                    }
                    if (eql(u8, prop.key, "MaxSize")) {
                        theme.directories[index].maxSize = try std.fmt.parseInt(u32, prop.value, 10);
                    }
                    if (eql(u8, prop.key, "Context")) {
                        theme.directories[index].context = try allocator.dupe(u8, prop.value);
                    }
                    if (eql(u8, prop.key, "Scale")) {
                        theme.directories[index].scale = try std.fmt.parseInt(u32, prop.value, 10);
                    }
                    if (eql(u8, prop.key, "Threshold")) {
                        theme.directories[index].threshold = try std.fmt.parseInt(u32, prop.value, 10);
                    }
                },
                else => {},
            }
        }
        return theme;
    }
    fn deinit(theme: Theme, allocator: Allocator) void {
        allocator.free(theme.name);
        allocator.free(theme.comment);
        allocator.free(theme.path);
        for (theme.directories) |dir| {
            for (dir.entrys) |entry| {
                allocator.free(entry.name);
            }
            allocator.free(dir.entrys);
            allocator.free(dir.name);
            allocator.free(dir.context);
        }
        allocator.free(theme.directories);
        for (theme.inherits) |item| allocator.free(item);
        allocator.free(theme.inherits);
    }
};

const IconEntry = struct {
    name: []const u8,
    type: enum {
        svg,
        png,
    },
};
const Cache = struct {
    path: []const u8,
    type: enum {
        svg,
        png,
    },
    size: u32,
    minSize: u32,
    maxSize: u32,
    scale: u32,
    threshold: u32,
    context: []const u8,
};
fn buildCache(allocator: Allocator, theme: Theme) ![]Cache {
    var list = std.ArrayList(Cache).init(allocator);
    defer list.deinit();
    for (theme.directories) |*directory| {
        const path = try std.fs.path.join(allocator, &.{ theme.path, directory.name });
        defer allocator.free(path);
        var entryDir = std.fs.openDirAbsolute(path, .{ .iterate = true }) catch continue;
        defer entryDir.close();
        var iter = entryDir.iterate();
        while (try iter.next()) |file| {
            var cache: Cache = .{
                .context = try allocator.dupe(u8, directory.context),
                .minSize = directory.minSize,
                .maxSize = directory.maxSize,
                .scale = directory.scale,
                .threshold = directory.threshold,
                .size = directory.size,
                .path = try std.fs.path.join(allocator, &.{ directory.name, file.name }),
                .type = undefined,
            };
            if (std.mem.endsWith(u8, file.name, ".svg")) cache.type = .svg;
            if (std.mem.endsWith(u8, file.name, ".png")) cache.type = .png;
            try list.append(cache);
        }
    }
    return list.toOwnedSlice();
}
fn deinitCache(allocator: Allocator, cache: []Cache) void {
    for (cache) |item| {
        allocator.free(item.path);
        allocator.free(item.context);
    }
    allocator.free(cache);
}
const Directory = struct {
    name: []const u8,
    size: u32,
    type: enum {
        fixed,
        scalable,
        threshold,
    },
    minSize: u32,
    maxSize: u32,
    context: []const u8,
    scale: u32,
    threshold: u32,
    entrys: []IconEntry,
};
fn getGtkIconThemeName(allocator: Allocator) ![]const u8 {
    var theme = try allocator.dupe(u8, "Adwaita");
    const configHome = blk: {
        var env = try std.process.getEnvMap(allocator);
        defer env.deinit();
        if (env.get("XDG_CONFIG_HOME")) |xdgConfigHome| {
            break :blk try allocator.dupe(u8, xdgConfigHome);
        }
        if (env.get("HOME")) |home| {
            break :blk try std.fs.path.join(allocator, &.{ home, ".config" });
        }
        return error.HomeDirNotFound;
    };
    defer allocator.free(configHome);
    const gtkSettings = try std.fs.path.join(allocator, &.{ configHome, "gtk-4.0", "settings.ini" });
    defer allocator.free(gtkSettings);
    var file = try std.fs.openFileAbsolute(gtkSettings, .{ .mode = .read_only });
    defer file.close();
    const reader = file.reader();
    var iter = ini.parse(allocator, reader, ";#");
    defer iter.deinit();
    while (try iter.next()) |record| {
        switch (record) {
            .property => |prop| {
                if (std.mem.eql(u8, prop.key, "gtk-icon-theme-name")) {
                    allocator.free(theme);
                    theme = try allocator.dupe(u8, prop.value);
                    break;
                }
            },
            else => {},
        }
    }
    return theme;
}
fn getGtkIconTheme(allocator: Allocator, themeFolder: []const u8) !Theme {
    var searchDirs = std.ArrayList([]const u8).init(allocator);
    defer searchDirs.deinit();
    defer for (searchDirs.items) |path| allocator.free(path);
    var env = try std.process.getEnvMap(allocator);
    defer env.deinit();
    if (env.get("HOME")) |home| {
        try searchDirs.append(try std.fs.path.join(allocator, &.{ home, ".icons" }));
    }
    if (env.get("XDG_DATA_DIRS")) |dirs| {
        var iter = std.mem.splitAny(u8, dirs, ":");
        while (iter.next()) |dir| {
            try searchDirs.append(try std.fs.path.join(allocator, &.{ dir, "icons" }));
        }
    }
    try searchDirs.append(try allocator.dupe(u8, "/usr/share/pixmaps"));
    for (searchDirs.items) |path| {
        var dir = std.fs.openDirAbsolute(path, .{ .iterate = true }) catch continue;
        defer dir.close();
        const themes = findAllThemesInDir(allocator, dir) catch continue;
        defer allocator.free(themes);
        var target: ?usize = null;
        for (themes, 0..) |t, i| {
            if (std.mem.endsWith(u8, t.path, themeFolder)) {
                target = i;
            } else {
                t.deinit(allocator);
            }
        }
        if (target) |targ| return themes[targ];
    }
    return error.ThemeNotFound;
}
fn findAllThemesInDir(allocator: Allocator, dir: std.fs.Dir) ![]Theme {
    var themes = std.ArrayList(Theme).init(allocator);
    defer themes.deinit();
    errdefer for (themes.items) |t| t.deinit(allocator);
    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (!(entry.kind == .directory or entry.kind == .sym_link)) continue;
        var subDir = dir.openDir(entry.name, .{ .iterate = true }) catch continue;
        defer subDir.close();
        var theme = findIndexThemeInDir(allocator, subDir) catch {
            const ts = findAllThemesInDir(allocator, subDir) catch continue;
            defer allocator.free(ts);
            try themes.appendSlice(ts);
            continue;
        };
        errdefer theme.deinit(allocator);
        theme.path = try dir.realpathAlloc(allocator, entry.name);
        try themes.append(theme);
    }
    return themes.toOwnedSlice();
}
fn findIndexThemeInDir(allocator: Allocator, dir: std.fs.Dir) !Theme {
    var indexTheme = dir.openFile("index.theme", .{}) catch {
        return error.IndexThemeNotFound;
    };
    defer indexTheme.close();
    const t = try Theme.init(allocator, indexTheme.reader());
    return t;
}
test {
    const iniStr =
        \\ [Icon Theme]
        \\ Name=Birch
        \\ Name[sv]=Björk
        \\ Comment=Icon theme with a wooden look
        \\ Comment[sv]=Träinspirerat ikontema
        \\ Inherits=wood,default
        \\ Directories=48x48/apps,48x48@2/apps,48x48/mimetypes,32x32/apps,32x32@2/apps,scalable/apps,scalable/mimetypes
        \\ 
        \\ [scalable/apps]
        \\ Size=48
        \\ Type=Scalable
        \\ MinSize=1
        \\ MaxSize=256
        \\ Context=Applications
        \\ 
        \\ [scalable/mimetypes]
        \\ Size=48
        \\ Type=Scalable
        \\ MinSize=1
        \\ MaxSize=256
        \\ Context=MimeTypes
        \\ 
        \\ [32x32/apps]
        \\ Size=32
        \\ Type=Fixed
        \\ Context=Applications
        \\ 
        \\ [32x32@2/apps]
        \\ Size=32
        \\ Scale=2
        \\ Type=Fixed
        \\ Context=Applications
        \\ 
        \\ [48x48/apps]
        \\ Size=48
        \\ Type=Fixed
        \\ Context=Applications
        \\ 
        \\ [48x48@2/apps]
        \\ Size=48
        \\ Scale=2
        \\ Type=Fixed
        \\ Context=Applications
        \\ 
        \\ [48x48/mimetypes]
        \\ Size=48
        \\ Type=Fixed
        \\ Context=MimeTypes
    ;
    const allocato = testing.allocator;
    var stream = std.io.fixedBufferStream(iniStr);
    const reader = stream.reader();
    const theme = try Theme.init(allocato, reader);
    defer theme.deinit(allocato);
    try testing.expectEqualStrings("Birch", theme.name);
    try testing.expectEqualStrings("Icon theme with a wooden look", theme.comment);
    try testing.expectEqualStrings("wood", theme.inherits[0]);
    try testing.expectEqualStrings("default", theme.inherits[1]);
    try testing.expectEqual(7, theme.directories.len);
    try testing.expectEqualStrings("48x48/apps", theme.directories[0].name);
    try testing.expectEqual(48, theme.directories[0].size);
    try testing.expectEqual(48, theme.directories[0].minSize);
    try testing.expectEqual(48, theme.directories[0].maxSize);
    try testing.expectEqual(1, theme.directories[0].scale);
    try testing.expectEqual(2, theme.directories[0].threshold);
    try testing.expectEqual(.fixed, theme.directories[0].type);
    try testing.expectEqualStrings("48x48@2/apps", theme.directories[1].name);
    try testing.expectEqual(48, theme.directories[1].size);
    try testing.expectEqual(48, theme.directories[1].minSize);
    try testing.expectEqual(48, theme.directories[1].maxSize);
    try testing.expectEqual(2, theme.directories[1].scale);
    try testing.expectEqual(2, theme.directories[1].threshold);
    try testing.expectEqual(.fixed, theme.directories[1].type);
    try testing.expectEqualStrings("48x48/mimetypes", theme.directories[2].name);
    try testing.expectEqual(48, theme.directories[2].size);
    try testing.expectEqual(48, theme.directories[2].minSize);
    try testing.expectEqual(48, theme.directories[2].maxSize);
    try testing.expectEqual(1, theme.directories[2].scale);
    try testing.expectEqual(2, theme.directories[2].threshold);
    try testing.expectEqual(.fixed, theme.directories[2].type);
    try testing.expectEqualStrings("32x32/apps", theme.directories[3].name);
    try testing.expectEqual(32, theme.directories[3].size);
    try testing.expectEqual(32, theme.directories[3].minSize);
    try testing.expectEqual(32, theme.directories[3].maxSize);
    try testing.expectEqual(1, theme.directories[3].scale);
    try testing.expectEqual(2, theme.directories[3].threshold);
    try testing.expectEqual(.fixed, theme.directories[3].type);
    try testing.expectEqualStrings("32x32@2/apps", theme.directories[4].name);
    try testing.expectEqual(32, theme.directories[4].size);
    try testing.expectEqual(32, theme.directories[4].minSize);
    try testing.expectEqual(32, theme.directories[4].maxSize);
    try testing.expectEqual(2, theme.directories[4].scale);
    try testing.expectEqual(2, theme.directories[4].threshold);
    try testing.expectEqual(.fixed, theme.directories[4].type);
    try testing.expectEqualStrings("scalable/apps", theme.directories[5].name);
    try testing.expectEqual(48, theme.directories[5].size);
    try testing.expectEqual(1, theme.directories[5].minSize);
    try testing.expectEqual(256, theme.directories[5].maxSize);
    try testing.expectEqual(1, theme.directories[5].scale);
    try testing.expectEqual(2, theme.directories[5].threshold);
    try testing.expectEqual(.scalable, theme.directories[5].type);
    try testing.expectEqualStrings("scalable/mimetypes", theme.directories[6].name);
    try testing.expectEqual(48, theme.directories[6].size);
    try testing.expectEqual(1, theme.directories[6].minSize);
    try testing.expectEqual(256, theme.directories[6].maxSize);
    try testing.expectEqual(1, theme.directories[6].scale);
    try testing.expectEqual(2, theme.directories[6].threshold);
    try testing.expectEqual(.scalable, theme.directories[6].type);
}

// test {
//     const allocator = testing.allocator;
//     const themeName = try getGtkIconThemeName(allocator);
//     defer allocator.free(themeName);
//     const theme = try getGtkIconTheme(allocator, themeName);
//     defer theme.deinit(allocator);
//     const hicolor = try getGtkIconTheme(allocator, "hicolor");
//     defer hicolor.deinit(allocator);
//     const cache = try buildCache(allocator, theme);
//     defer deinitCache(allocator, cache);
//     const start = std.time.nanoTimestamp();
//     for (cache) |item| {
//         if (item.type == .svg) {}
//         if (item.type == .png) {}
//     }
//     const end = std.time.nanoTimestamp();
//     std.debug.print("Time elapsed: {}ns {d}\n", .{ end - start, cache.len });
// }
const gtk = @import("gtk");
const gdk = @import("gdk");
const glib = @import("glib");
const modules = @import("root.zig");
const Args = modules.Args;
const Context = modules.Context;
const InitContext = modules.InitContext;
const Registry = modules.Registry;
const App = @import("../app.zig").App;

pub const Icon = struct {
    const Self = @This();
    pub fn init(ctx: InitContext) !*Self {
        const self = try ctx.allocator.create(Self);
        return self;
    }
    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.destroy(self);
    }
    pub fn register() Registry(Self) {
        return .{
            .exports = &.{
                .{ "lookup", lookup },
            },
        };
    }

    // TODO: 替换成 zig 实现的 icon 查找器
    pub fn lookup(_: *Self, ctx: *Context) !void {
        const allocator = std.heap.page_allocator;
        const name = try ctx.args.string(0);
        const size = try ctx.args.integer(1);
        const scale = try ctx.args.integer(2);
        const img = lookupIcon(allocator, name, @intCast(size), @intCast(scale)) catch |err| blk: {
            if (!std.fs.path.isAbsolute(name)) return err;
            break :blk makeHtmlImg(allocator, name) catch return err;
        };
        defer allocator.free(img);
        ctx.commit(img);
    }
};
fn lookupIcon(allocator: Allocator, name: []const u8, size: i32, scale: i32) ![]const u8 {
    const theme = gtk.IconTheme.getForDisplay(gdk.Display.getDefault().?);
    const name_c = try allocator.dupeZ(u8, name);
    defer allocator.free(name_c);
    const icon = theme.lookupIcon(name_c, null, @intCast(size), @intCast(scale), .none, gtk.IconLookupFlags.flags_preload);
    defer icon.unref();
    const gotIconName_c = icon.getIconName() orelse return error.IconNotFound;
    const gotIconName = std.mem.span(gotIconName_c);
    if (std.mem.eql(u8, gotIconName, "image-missing")) {
        return error.IconNotFound;
    }
    const file = icon.getFile() orelse return error.IconNotSupported;
    defer file.unref();
    const path_c = file.getPath() orelse return error.IconMissing;
    defer glib.free(@ptrCast(path_c));
    const path = std.mem.span(path_c);
    return try makeHtmlImg(allocator, path);
}
fn makeHtmlImg(allocator: Allocator, filePath: []const u8) ![]const u8 {
    const f = try std.fs.openFileAbsolute(filePath, .{});
    defer f.close();
    if (std.mem.endsWith(u8, filePath, ".svg")) {
        const svg = try f.reader().readAllAlloc(allocator, std.math.maxInt(usize));
        defer allocator.free(svg);
        var uri = std.ArrayList(u8).init(allocator);
        defer uri.deinit();
        try std.Uri.Component.percentEncode(uri.writer(), svg, isValidcharhar);
        return try std.fmt.allocPrint(allocator, "data:image/svg+xml,{s}", .{uri.items});
    }
    if (std.mem.endsWith(u8, filePath, ".png")) {
        var base64 = std.ArrayList(u8).init(allocator);
        defer base64.deinit();
        try std.base64.standard.Encoder.encodeFromReaderToWriter(base64.writer(), f.reader());
        return try std.fmt.allocPrint(allocator, "data:image/png;base64,{s}", .{base64.items});
    }
    return error.IconNotSupported;
}
fn isValidcharhar(char: u8) bool {
    return (char >= 'a' and char <= 'z') or
        (char >= 'A' and char <= 'Z') or
        (char >= '0' and char <= '9') or
        char == '-' or char == '_' or char == '.' or char == '~';
}
