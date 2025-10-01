const std = @import("std");
const testing = std.testing;

pub const Type = enum {
    none,
    application,
    link,
    directory,
};
pub const Action = struct {
    id: []const u8,
    name: []const u8,
    icon: ?[]const u8,
    exec: ?[]const u8,
};
pub const Entry = struct {
    id: []const u8,
    dbusName: ?[]const u8,
    type: Type,
    version: ?[]const u8,
    name: []const u8,
    genericName: ?[]const u8,
    noDisplay: bool = false,
    comment: ?[]const u8,
    icon: ?[]const u8,
    hidden: bool = false,
    onlyShowIn: [][]const u8,
    notShowIn: [][]const u8,
    dbusActivatable: bool = false,
    tryExec: ?[]const u8,
    exec: ?[]const u8,
    path: ?[]const u8,
    terminal: bool = false,
    actions: []Action,
    mimeType: [][]const u8,
    categories: [][]const u8,
    implements: [][]const u8,
    keywords: [][]const u8,
    startupNotify: bool = false,
    startupWMClass: ?[]const u8,
    url: ?[]const u8,
    prefersNonDefaultGPU: bool = false,
    singleMainWindow: bool = false,
    // x: <key,value> // not supported
    fn deinit(e: *Entry, allocator: Allocator) void {
        allocator.free(e.id);
        if (e.dbusName) |dn| allocator.free(dn);
        if (e.version) |v| allocator.free(v);
        allocator.free(e.name);
        if (e.genericName) |gn| allocator.free(gn);
        if (e.comment) |c| allocator.free(c);
        if (e.icon) |i| allocator.free(i);
        for (e.onlyShowIn) |os| allocator.free(os);
        allocator.free(e.onlyShowIn);
        for (e.notShowIn) |ns| allocator.free(ns);
        allocator.free(e.notShowIn);
        for (e.actions) |a| {
            allocator.free(a.id);
            allocator.free(a.name);
            if (a.icon) |i| allocator.free(i);
            if (a.exec) |exec| allocator.free(exec);
        }
        if (e.tryExec) |te| allocator.free(te);
        if (e.exec) |exec| allocator.free(exec);
        if (e.path) |p| allocator.free(p);
        allocator.free(e.actions);
        for (e.mimeType) |m| allocator.free(m);
        allocator.free(e.mimeType);
        for (e.categories) |c| allocator.free(c);
        allocator.free(e.categories);
        for (e.implements) |i| allocator.free(i);
        allocator.free(e.implements);
        for (e.keywords) |k| allocator.free(k);
        allocator.free(e.keywords);
        if (e.startupWMClass) |swc| allocator.free(swc);
        if (e.url) |u| allocator.free(u);
    }
};

fn findApps(allocator: Allocator, dirPath: []const u8, locals: []const []const u8, usedID: []const []const u8) ![]Entry {
    const appPath = try std.fs.path.join(allocator, &.{ dirPath, "applications" });
    defer allocator.free(appPath);
    var dir = try std.fs.openDirAbsolute(appPath, .{ .iterate = true });
    defer dir.close();
    var iter = try dir.walk(allocator);
    defer iter.deinit();
    var result = std.ArrayList(Entry){};
    defer result.deinit(allocator);
    find: while (try iter.next()) |entry| {
        if (entry.kind == .directory) continue;
        if (!std.mem.endsWith(u8, entry.path, ".desktop")) continue;
        var id: []const u8 = undefined;
        const subDir = blk: {
            if (std.fs.path.dirname(entry.path)) |dirName| {
                break :blk dirName;
            } else {
                break :blk "";
            }
        };
        if (subDir.len > 0) {
            const base = std.fs.path.basename(entry.path);
            id = try std.fmt.allocPrint(allocator, "{s}-{s}", .{ subDir, base[0 .. base.len - 8] });
        } else {
            const base = std.fs.path.basename(entry.path);
            id = try allocator.dupe(u8, base[0 .. base.len - 8]);
        }
        for (usedID) |used| {
            if (std.mem.eql(u8, used, id)) {
                allocator.free(id);
                continue :find;
            }
        }
        const fullPath = try entry.dir.realpathAlloc(allocator, entry.path);
        defer allocator.free(fullPath);
        var e = try parseEntry(allocator, fullPath, locals);
        if (e.hidden) {
            allocator.free(id);
            e.deinit(allocator);
            continue;
        }
        e.id = id;
        if (e.dbusActivatable) {
            const base = std.fs.path.basename(entry.path);
            e.dbusName = try allocator.dupe(u8, base[0 .. base.len - 8]);
        } else {
            e.dbusName = null;
        }
        try result.append(allocator, e);
    }
    return try result.toOwnedSlice(allocator);
}
const ini = @import("ini");
fn parseLangCode(code: []const u8) []const u8 {
    // strip ".UTF-8" etc.
    if (std.mem.indexOf(u8, code, ".")) |i| {
        return code[0..i];
    }
    return code;
}
fn getPreferredLocales(allocator: Allocator) ![]const []const u8 {
    var env = std.process.getEnvMap(allocator) catch return &.{};
    defer env.deinit();
    if (env.get("LANGUAGE")) |lang_env| {
        var list = std.ArrayList([]const u8){};
        defer list.deinit(allocator);
        var iter = std.mem.splitAny(u8, lang_env, ":");
        while (iter.next()) |code| {
            try list.append(allocator, try allocator.dupe(u8, code));
        }
        return try list.toOwnedSlice(allocator);
    }

    var buf = std.ArrayList([]const u8){};
    defer buf.deinit(allocator);
    if (env.get("LC_MESSAGES")) |lc| {
        try buf.append(allocator, try allocator.dupe(u8, parseLangCode(lc)));
    } else if (env.get("LANG")) |l| {
        try buf.append(allocator, try allocator.dupe(u8, parseLangCode(l)));
    }

    return try buf.toOwnedSlice(allocator);
}

const Locale = struct {
    lang: []const u8,
    country: ?[]const u8,
    modifier: ?[]const u8,
};

fn parseLocale(locale: []const u8) Locale {
    var lang = locale;
    var country: ?[]const u8 = null;
    var modifier: ?[]const u8 = null;

    if (std.mem.indexOfScalar(u8, lang, '@')) |at| {
        modifier = lang[at + 1 ..];
        lang = lang[0..at];
    }
    if (std.mem.indexOfScalar(u8, lang, '_')) |under| {
        country = lang[under + 1 ..];
        lang = lang[0..under];
    }

    return .{
        .lang = lang,
        .country = country,
        .modifier = modifier,
    };
}

pub fn scoreLocaleMatch(lc_message: []const u8, preferred_locales: []const []const u8) i32 {
    const max_score = 100;
    const entry = parseLocale(lc_message);
    var best_score: i32 = 0;

    for (preferred_locales) |pref| {
        const p = parseLocale(pref);

        if (!std.mem.eql(u8, entry.lang, p.lang)) continue;

        var score: i32 = 70;

        if (entry.country) |ec| {
            if (p.country) |pc| {
                if (std.mem.eql(u8, ec, pc)) {
                    score = 90;
                }
            }
        }

        if (entry.modifier) |em| {
            if (p.modifier) |pm| {
                if (std.mem.eql(u8, em, pm)) {
                    score += 5;
                }
            }
        }

        if (score > best_score) {
            best_score = score;
            if (score == max_score) break;
        }
    }

    return best_score;
}
test "score-locale-match" {
    const preferred_locales: []const []const u8 = &.{
        "zh_CN@foo",
    };
    try testing.expectEqual(90, scoreLocaleMatch("zh_CN@bar", preferred_locales));
    try testing.expectEqual(95, scoreLocaleMatch("zh_CN@foo", preferred_locales));
    try testing.expectEqual(90, scoreLocaleMatch("zh_CN", preferred_locales));
    try testing.expectEqual(70, scoreLocaleMatch("zh", preferred_locales));
    try testing.expectEqual(0, scoreLocaleMatch("ru", preferred_locales));
    try testing.expectEqual(0, scoreLocaleMatch("ca", preferred_locales));
}
const StrAndScore = struct {
    str: []const u8,
    score: i32,
};
fn parseEntry(allocator: Allocator, path: []const u8, locals: []const []const u8) !Entry {
    var entry: Entry = .{
        .id = undefined,
        .dbusName = undefined,
        .type = .none,
        .version = null,
        .name = "",
        .genericName = null,
        .noDisplay = false,
        .comment = null,
        .icon = null,
        .hidden = false,
        .onlyShowIn = &.{},
        .notShowIn = &.{},
        .dbusActivatable = false,
        .tryExec = null,
        .exec = null,
        .path = null,
        .terminal = false,
        .actions = &.{},
        .mimeType = &.{},
        .categories = &.{},
        .implements = &.{},
        .keywords = &.{},
        .startupNotify = false,
        .startupWMClass = null,
        .url = null,
        .prefersNonDefaultGPU = false,
        .singleMainWindow = false,
    };
    const f = try std.fs.openFileAbsolute(path, .{});
    defer f.close();
    const reader = f.deprecatedReader();
    var iter = ini.parse(allocator, reader, ";#");
    defer iter.deinit();
    var section: ?[]const u8 = null;
    defer if (section) |s| allocator.free(s);
    var actionCount: u32 = 0;
    var names = std.ArrayList(StrAndScore){};
    defer {
        for (names.items) |n| allocator.free(n.str);
        names.deinit(allocator);
    }
    var comments = std.ArrayList(StrAndScore){};
    defer {
        for (comments.items) |c| allocator.free(c.str);
        comments.deinit(allocator);
    }
    var keywords = std.ArrayList(StrAndScore){};
    defer {
        for (keywords.items) |k| allocator.free(k.str);
        keywords.deinit(allocator);
    }
    var genericNames = std.ArrayList(StrAndScore){};
    defer {
        for (genericNames.items) |gn| allocator.free(gn.str);
        genericNames.deinit(allocator);
    }
    var actionNames: ?std.ArrayList(StrAndScore) = null;
    defer if (actionNames != null) {
        for (actionNames.?.items) |an| allocator.free(an.str);
        actionNames.?.deinit(allocator);
    };
    const lessThan = struct {
        fn lessThan(_: void, a: StrAndScore, b: StrAndScore) bool {
            return a.score > b.score;
        }
    }.lessThan;
    while (try iter.next()) |record| {
        if (record == .section) {
            if (section) |sec| allocator.free(sec);
            section = try allocator.dupe(u8, record.section);
            if (std.mem.startsWith(u8, section.?, "Desktop Action ")) {
                if (actionNames != null) {
                    std.sort.insertion(StrAndScore, actionNames.?.items, {}, lessThan);
                    if (actionNames.?.items.len > 0 and actionNames.?.items[0].score != 0) {
                        allocator.free(entry.actions[actionCount - 1].name);
                        entry.actions[actionCount - 1].name = try allocator.dupe(u8, actionNames.?.items[0].str);
                    }
                    for (actionNames.?.items) |a| {
                        allocator.free(a.str);
                    }
                    actionNames.?.deinit(allocator);
                    actionNames = null;
                }
                actionCount += 1;
                const old = entry.actions;
                defer allocator.free(old);
                entry.actions = try allocator.alloc(Action, actionCount);
                std.mem.copyForwards(Action, entry.actions[0 .. actionCount - 1], old[0 .. actionCount - 1]);
                entry.actions[actionCount - 1] = .{
                    .id = try allocator.dupe(u8, section.?[15..]),
                    .name = "",
                    .icon = null,
                    .exec = null,
                };
                actionNames = std.ArrayList(StrAndScore){};
            }
            continue;
        }
        if (record == .property) {
            const prop = record.property;
            if (section == null) continue;
            const sec = section.?;
            const eql = std.mem.eql;
            if (eql(u8, sec, "Desktop Entry")) {
                if (eql(u8, prop.key, "Type")) {
                    if (eql(u8, prop.value, "Application")) {
                        entry.type = .application;
                    } else if (eql(u8, prop.value, "Link")) {
                        entry.type = .link;
                    } else if (eql(u8, prop.value, "Directory")) {
                        entry.type = .directory;
                    } else {
                        entry.type = .none;
                    }
                    continue;
                }
                if (eql(u8, prop.key, "Version")) {
                    entry.version = try allocator.dupe(u8, prop.value);
                    continue;
                }
                if (eql(u8, prop.key, "Name")) {
                    entry.name = try allocator.dupe(u8, prop.value);
                    continue;
                }
                if (std.mem.startsWith(u8, prop.key, "Name[")) {
                    const lcMessage = prop.key[5 .. prop.key.len - 1];
                    const score = scoreLocaleMatch(lcMessage, locals);
                    try names.append(allocator, .{
                        .str = try allocator.dupe(u8, prop.value),
                        .score = score,
                    });

                    continue;
                }

                if (eql(u8, prop.key, "GenericName")) {
                    entry.genericName = try allocator.dupe(u8, prop.value);
                    continue;
                }
                if (std.mem.startsWith(u8, prop.key, "GenericName[")) {
                    const lcMessage = prop.key[12 .. prop.key.len - 1];
                    const score = scoreLocaleMatch(lcMessage, locals);
                    try genericNames.append(allocator, .{
                        .str = try allocator.dupe(u8, prop.value),
                        .score = score,
                    });
                    continue;
                }
                if (eql(u8, prop.key, "NoDisplay")) {
                    entry.noDisplay = prop.value.len > 0 and prop.value[0] == 't';
                    continue;
                }
                if (eql(u8, prop.key, "Comment")) {
                    entry.comment = try allocator.dupe(u8, prop.value);
                    continue;
                }
                if (std.mem.startsWith(u8, prop.key, "Comment[")) {
                    const lcMessage = prop.key[8 .. prop.key.len - 1];
                    const score = scoreLocaleMatch(lcMessage, locals);
                    try comments.append(allocator, .{
                        .str = try allocator.dupe(u8, prop.value),
                        .score = score,
                    });
                    continue;
                }
                if (eql(u8, prop.key, "Icon")) {
                    entry.icon = try allocator.dupe(u8, prop.value);
                    continue;
                }
                if (eql(u8, prop.key, "Hidden")) {
                    entry.hidden = prop.value.len > 0 and prop.value[0] == 't';
                    continue;
                }
                if (eql(u8, prop.key, "OnlyShowIn")) {
                    var onlyShowIn = std.ArrayList([]const u8){};
                    defer onlyShowIn.deinit(allocator);
                    var values = std.mem.splitAny(u8, prop.value, ";");
                    while (values.next()) |value| {
                        try onlyShowIn.append(allocator, try allocator.dupe(u8, value));
                    }
                    entry.onlyShowIn = try onlyShowIn.toOwnedSlice(allocator);
                    continue;
                }
                if (eql(u8, prop.key, "NotShowIn")) {
                    var notShowIn = std.ArrayList([]const u8){};
                    defer notShowIn.deinit(allocator);
                    var values = std.mem.splitAny(u8, prop.value, ";");
                    while (values.next()) |value| {
                        try notShowIn.append(allocator, try allocator.dupe(u8, value));
                    }
                    entry.notShowIn = try notShowIn.toOwnedSlice(allocator);
                    continue;
                }
                if (eql(u8, prop.key, "DBusActivatable")) {
                    entry.dbusActivatable = prop.value.len > 0 and prop.value[0] == 't';
                    continue;
                }
                if (eql(u8, prop.key, "TryExec")) {
                    entry.tryExec = try allocator.dupe(u8, prop.value);
                    continue;
                }
                if (eql(u8, prop.key, "Exec")) {
                    entry.exec = try allocator.dupe(u8, prop.value);
                    continue;
                }
                if (eql(u8, prop.key, "Path")) {
                    entry.path = try allocator.dupe(u8, prop.value);
                    continue;
                }
                if (eql(u8, prop.key, "Terminal")) {
                    entry.terminal = prop.value.len > 0 and prop.value[0] == 't';
                    continue;
                }
                if (eql(u8, prop.key, "MimeType")) {
                    var mimeTypes = std.ArrayList([]const u8){};
                    defer mimeTypes.deinit(allocator);
                    var values = std.mem.splitAny(u8, prop.value, ";");
                    while (values.next()) |value| {
                        try mimeTypes.append(allocator, try allocator.dupe(u8, value));
                    }
                    entry.mimeType = try mimeTypes.toOwnedSlice(allocator);
                    continue;
                }
                if (eql(u8, prop.key, "Categories")) {
                    var categories = std.ArrayList([]const u8){};
                    defer categories.deinit(allocator);
                    var values = std.mem.splitAny(u8, prop.value, ";");
                    while (values.next()) |value| {
                        try categories.append(allocator, try allocator.dupe(u8, value));
                    }
                    entry.categories = try categories.toOwnedSlice(allocator);
                    continue;
                }
                if (eql(u8, prop.key, "Implements")) {
                    var implements = std.ArrayList([]const u8){};
                    defer implements.deinit(allocator);
                    var values = std.mem.splitAny(u8, prop.value, ";");
                    while (values.next()) |value| {
                        try implements.append(allocator, try allocator.dupe(u8, value));
                    }
                    entry.implements = try implements.toOwnedSlice(allocator);
                    continue;
                }
                if (eql(u8, prop.key, "Keywords")) {
                    var kws = std.ArrayList([]const u8){};
                    defer kws.deinit(allocator);
                    var values = std.mem.splitAny(u8, prop.value, ";");
                    while (values.next()) |value| {
                        try kws.append(allocator, try allocator.dupe(u8, value));
                    }
                    entry.keywords = try kws.toOwnedSlice(allocator);
                    continue;
                }
                if (std.mem.startsWith(u8, prop.key, "Keywords[")) {
                    const lcMessage = prop.key[9 .. prop.key.len - 1];
                    const score = scoreLocaleMatch(lcMessage, locals);
                    try keywords.append(allocator, .{
                        .str = try allocator.dupe(u8, prop.value),
                        .score = score,
                    });
                    continue;
                }
                if (eql(u8, prop.key, "StartupNotify")) {
                    entry.startupNotify = prop.value.len > 0 and prop.value[0] == 't';
                    continue;
                }
                if (eql(u8, prop.key, "StartupWMClass")) {
                    entry.startupWMClass = try allocator.dupe(u8, prop.value);
                    continue;
                }
                if (eql(u8, prop.key, "URL")) {
                    entry.url = try allocator.dupe(u8, prop.value);
                    continue;
                }
                if (eql(u8, prop.key, "PrefersNonDefaultGPU")) {
                    entry.prefersNonDefaultGPU = prop.value.len > 0 and prop.value[0] == 't';
                    continue;
                }
                if (eql(u8, prop.key, "SingleMainWindow")) {
                    entry.singleMainWindow = prop.value.len > 0 and prop.value[0] == 't';
                    continue;
                }
                continue;
            }
            if (std.mem.startsWith(u8, sec, "Desktop Action ")) {
                if (eql(u8, prop.key, "Name")) {
                    entry.actions[actionCount - 1].name = try allocator.dupe(u8, prop.value);
                    continue;
                }
                if (std.mem.startsWith(u8, prop.key, "Name[")) {
                    const lcMessage = prop.key[5 .. prop.key.len - 1];
                    const score = scoreLocaleMatch(lcMessage, locals);
                    try actionNames.?.append(allocator, .{
                        .str = try allocator.dupe(u8, prop.value),
                        .score = score,
                    });
                    continue;
                }
                if (eql(u8, prop.key, "Icon")) {
                    entry.actions[actionCount - 1].icon = try allocator.dupe(u8, prop.value);
                    continue;
                }
                if (eql(u8, prop.key, "Exec")) {
                    entry.actions[actionCount - 1].exec = try allocator.dupe(u8, prop.value);
                    continue;
                }
            }
        }
    }

    std.sort.insertion(StrAndScore, names.items, {}, lessThan);
    if (names.items.len != 0 and names.items[0].score != 0) {
        if (entry.name.len != 0) allocator.free(entry.name);
        entry.name = allocator.dupe(u8, names.items[0].str) catch unreachable;
    }
    std.sort.insertion(StrAndScore, genericNames.items, {}, lessThan);
    if (genericNames.items.len != 0 and genericNames.items[0].score != 0) {
        if (entry.genericName != null and entry.genericName.?.len != 0) allocator.free(entry.genericName.?);
        entry.genericName = allocator.dupe(u8, genericNames.items[0].str) catch unreachable;
    }
    std.sort.insertion(StrAndScore, comments.items, {}, lessThan);
    if (comments.items.len != 0 and comments.items[0].score != 0) {
        if (entry.comment != null and entry.comment.?.len != 0) allocator.free(entry.comment.?);
        entry.comment = allocator.dupe(u8, comments.items[0].str) catch unreachable;
    }
    std.sort.insertion(StrAndScore, keywords.items, {}, lessThan);
    if (keywords.items.len != 0 and keywords.items[0].score != 0) {
        if (entry.keywords.len != 0) {
            for (entry.keywords) |kw| allocator.free(kw);
            allocator.free(entry.keywords);
        }
        var kws = std.ArrayList([]const u8){};
        defer kws.deinit(allocator);
        var it = std.mem.splitAny(u8, keywords.items[0].str, ";");
        while (it.next()) |kw| {
            try kws.append(allocator, try allocator.dupe(u8, kw));
        }
        entry.keywords = try kws.toOwnedSlice(allocator);
    }
    return entry;
}
const modules = @import("root.zig");
const Args = modules.Args;
const Context = modules.Context;
const InitContext = modules.InitContext;
const Registry = modules.Registry;
const Allocator = std.mem.Allocator;
const icon = @import("icon.zig");
const glib = @import("glib");
const gio = @import("gio");
const g = @import("gobject");
pub const Apps = struct {
    const Self = @This();
    allocator: Allocator,
    entrys: ?[]Entry = null,
    monitors: ?[]*gio.FileMonitor = null,
    needReload: bool = false,
    pub fn init(ctx: InitContext) !*Self {
        const self = try ctx.allocator.create(Self);
        self.* = Self{
            .allocator = ctx.allocator,
        };
        return self;
    }
    pub fn register() Registry(Self) {
        return .{
            .exports = &.{
                .{ "list", list },
                .{ "activate", activate },
            },
        };
    }
    pub fn list(self: *Self, ctx: *Context) !void {
        try self.setup();
        const allocator = self.allocator;
        if (self.needReload) {
            for (self.entrys.?) |*entry| entry.deinit(allocator);
            allocator.free(self.entrys.?);
            self.entrys = try listApps(allocator);
            self.needReload = false;
        }
        const entrys = self.entrys.?;
        ctx.commit(entrys);
    }
    fn setup(self: *Self) !void {
        const allocator = self.allocator;
        if (self.entrys == null) {
            self.entrys = try listApps(allocator);
            const xdgDataDirs = std.process.getEnvVarOwned(allocator, "XDG_DATA_DIRS") catch |err| {
                std.log.scoped(.apps).err("Failed to get XDG_DATA_DIRS: {t}", .{err});
                return err;
            };
            defer allocator.free(xdgDataDirs);
            var paths = std.mem.splitAny(u8, xdgDataDirs, ":");
            var monitors = std.ArrayList(*gio.FileMonitor){};
            defer monitors.deinit(allocator);
            errdefer for (monitors.items) |m| m.unref();
            while (paths.next()) |path| {
                const path_ = try allocator.dupeZ(u8, path);
                defer allocator.free(path_);
                const gfile = gio.File.newForPath(path_);
                defer gfile.unref();
                var err: ?*glib.Error = null;
                const monitor = gfile.monitorDirectory(gio.FileMonitorFlags.flags_none, null, &err);
                if (err) |e| {
                    std.log.err("Failed to monitor {s}: {s}", .{ path, e.f_message.? });
                    e.free();
                    continue;
                }
                _ = g.signalConnectData(@ptrCast(monitor), "changed", @ptrCast(&struct {
                    fn f(_: *gio.FileMonitor, _: ?*gio.File, _: ?*gio.File, _: gio.FileMonitorEvent, data: ?*anyopaque) void {
                        const flg: *bool = @ptrCast(@alignCast(data));
                        flg.* = true;
                    }
                }.f), &self.needReload, null, .flags_default);
                try monitors.append(allocator, monitor.?);
            }
            self.monitors = try monitors.toOwnedSlice(allocator);
        }
    }
    pub fn deinit(self: *Self, allocator: Allocator) void {
        if (self.entrys) |entrys| {
            for (entrys) |*e| e.deinit(self.allocator);
            self.allocator.free(entrys);
        }
        if (self.monitors) |monitors| {
            for (monitors) |m| m.unref();
            self.allocator.free(monitors);
        }
        allocator.destroy(self);
    }
    pub fn activate(self: *Self, ctx: *Context) !void {
        try self.setup();
        const allocator = self.allocator;
        const id = try ctx.args.string(0);
        const action_ = try ctx.args.string(1);
        const parsedUrls = try std.json.parseFromValue([]const []const u8, allocator, try ctx.args.value(2), .{});
        defer parsedUrls.deinit();
        const urls = parsedUrls.value;
        const entrys = self.entrys.?;
        const entry: Entry = blk: {
            for (entrys) |e| {
                if (std.mem.eql(u8, e.id, id)) break :blk e;
            }
            return error.AppNotFound;
        };
        var action: ?Action = null;
        if (action_.len > 0) {
            for (entry.actions) |act| {
                if (std.mem.eql(u8, act.id, action_)) {
                    action = act;
                    break;
                }
            }
            return error.ActionNotFound;
        }

        const dbusOk = blk: {
            if (entry.dbusActivatable) {
                activateAppWithDBus(allocator, entry, action, urls) catch break :blk false;
                break :blk true;
            } else break :blk false;
        };
        if (!dbusOk) try activateApp(allocator, entry, action, urls);
    }
};
const dbus = @import("dbus");
fn activateAppWithDBus(allocator: Allocator, entry: Entry, action: ?Action, urls: []const []const u8) !void {
    var err: dbus.Error = undefined;
    err.init();
    defer err.deinit();
    const conn = try dbus.Connection.get(.Session, &err);
    defer conn.close();
    const dbusName = try allocator.dupeZ(u8, entry.dbusName.?);
    defer allocator.free(dbusName);
    var path = std.ArrayList(u8){};
    defer path.deinit(allocator);
    var it = std.mem.splitAny(u8, entry.id, ".");
    while (it.next()) |part| {
        const p = try std.mem.replaceOwned(u8, allocator, part, "-", "_");
        defer allocator.free(p);
        try path.append(allocator, '/');
        try path.appendSlice(allocator, p);
    }
    try path.append(allocator, '\x00');
    if (action == null) {
        if (urls.len > 0) {
            const result = try dbus.call(
                allocator,
                conn,
                &err,
                dbusName,
                path.items,
                "org.freedesktop.Application",
                "Open",
                .{ dbus.Array(dbus.String), dbus.Dict(dbus.String, dbus.AnyVariant) },
                .{ urls, &.{} },
            );
            result.deinit();
        } else {
            const result = try dbus.call(
                allocator,
                conn,
                &err,
                dbusName,
                path.items,
                "org.freedesktop.Application",
                "Activate",
                .{dbus.Dict(dbus.String, dbus.AnyVariant)},
                .{&.{}},
            );
            result.deinit();
        }
    } else {
        const result = try dbus.call(
            allocator,
            conn,
            &err,
            dbusName,
            path.items,
            "org.freedesktop.Application",
            "ActivateAction",
            .{ dbus.String, dbus.Array(dbus.String), dbus.Dict(dbus.String, dbus.AnyVariant) },
            .{ action.?.name, urls, &.{} },
        );
        result.deinit();
    }
}
fn removeExecDeprecatedOptions(exec: []u8) []u8 {
    // remove deprecated options and %k
    var read_i: usize = 0;
    var write_i: usize = 0;
    while (read_i < exec.len) {
        if (exec[read_i] == '%' and read_i + 1 < exec.len) {
            switch (exec[read_i + 1]) {
                'd', 'D', 'n', 'N', 'v', 'm', 'k' => {
                    read_i += 2;
                    continue;
                },
                else => {},
            }
        }
        exec[write_i] = exec[read_i];
        write_i += 1;
        read_i += 1;
    }
    return exec[0..write_i];
}
test "removeExecDeprecatedOptions" {
    const allocator = std.testing.allocator;
    const cast = "%%%f %c %k %d %D %n %N %%v %m %U %u %i%% %c avvccc%v   %v %n";
    const buf = try allocator.alloc(u8, cast.len);
    defer allocator.free(buf);
    std.mem.copyForwards(u8, buf, cast);
    const expected = "%%%f %c      %  %U %u %i%% %c avvccc    ";
    const actual = removeExecDeprecatedOptions(buf);
    try std.testing.expectEqualStrings(expected, actual);
}

fn makeExecCommands(allocator: Allocator, exec: []const u8, urls: []const []const u8) ![][]const u8 {
    var result = std.ArrayList([]const u8){};
    defer result.deinit(allocator);
    var i: usize = 0;
    replace: while (i < exec.len) : (i += 1) {
        if (exec[i] == '%' and i + 1 < exec.len) {
            switch (exec[i + 1]) {
                'u' => {
                    if (urls.len == 0) {
                        try result.append(allocator, try std.fmt.allocPrint(allocator, "{s}{s}", .{ exec[0..i], exec[i + 2 ..] }));
                    } else {
                        for (urls) |url| {
                            const cmd = try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ exec[0..i], url, exec[i + 2 ..] });
                            try result.append(allocator, cmd);
                        }
                    }
                    break :replace;
                },
                'U' => {
                    const urls_str = try std.mem.join(allocator, " ", urls);
                    defer allocator.free(urls_str);
                    const cmd = try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ exec[0..i], urls_str, exec[i + 2 ..] });
                    try result.append(allocator, cmd);
                    break :replace;
                },
                'f' => {
                    var files = std.ArrayList([]const u8){};
                    defer files.deinit(allocator);
                    for (urls) |url| {
                        if (std.mem.startsWith(u8, url, "file://")) {
                            const file = url[7..];
                            try files.append(allocator, file);
                        }
                    }
                    if (files.items.len == 0) {
                        try result.append(allocator, try std.fmt.allocPrint(allocator, "{s}{s}", .{ exec[0..i], exec[i + 2 ..] }));
                    } else {
                        for (files.items) |file| {
                            const cmd = try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ exec[0..i], file, exec[i + 2 ..] });
                            try result.append(allocator, cmd);
                        }
                    }
                    break :replace;
                },
                'F' => {
                    var files = std.ArrayList([]const u8){};
                    defer files.deinit(allocator);
                    for (urls) |url| {
                        if (std.mem.startsWith(u8, url, "file://")) {
                            const file = url[7..];
                            try files.append(allocator, file);
                        }
                    }
                    const files_str = try std.mem.join(allocator, " ", files.items);
                    defer allocator.free(files_str);
                    const cmd = try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ exec[0..i], files_str, exec[i + 2 ..] });
                    try result.append(allocator, cmd);
                    break :replace;
                },
                '%' => {
                    i += 1;
                },
                else => {},
            }
        }
    }
    if (result.items.len == 0) {
        try result.append(allocator, try allocator.dupe(u8, exec));
    }
    return try result.toOwnedSlice(allocator);
}

test "makeExecCommands" {
    const allocator = std.testing.allocator;

    // 测试%f
    {
        const exec = "example %f";
        const urls: []const []const u8 = &.{"file:///path/to/file"};
        const commands = try makeExecCommands(allocator, exec, urls);
        defer allocator.free(commands);
        defer for (commands) |c| allocator.free(c);
        try std.testing.expectEqual(1, commands.len);
        try std.testing.expectEqualStrings("example /path/to/file", commands[0]);
    }

    // 测试%u
    {
        const exec = "example %u";
        const urls: []const []const u8 = &.{"http://example.com"};
        const commands = try makeExecCommands(allocator, exec, urls);
        defer allocator.free(commands);
        defer for (commands) |c| allocator.free(c);
        try std.testing.expectEqual(1, commands.len);
        try std.testing.expectEqualStrings("example http://example.com", commands[0]);
    }

    // 测试多个%f
    {
        const exec = "example %f";
        const urls: []const []const u8 = &.{ "file:///file1", "file:///file2" };
        const commands = try makeExecCommands(allocator, exec, urls);
        defer allocator.free(commands);
        defer for (commands) |c| allocator.free(c);
        try std.testing.expectEqual(2, commands.len);
        try std.testing.expectEqualStrings("example /file1", commands[0]);
        try std.testing.expectEqualStrings("example /file2", commands[1]);
    }

    // 测试%F
    {
        const exec = "example %F";
        const urls: []const []const u8 = &.{ "file:///file1", "file:///file2" };
        const commands = try makeExecCommands(allocator, exec, urls);
        defer allocator.free(commands);
        defer for (commands) |c| allocator.free(c);
        try std.testing.expectEqual(1, commands.len);
        try std.testing.expectEqualStrings("example /file1 /file2", commands[0]);
    }

    // 测试没有匹配的URLs时%f
    {
        const exec = "example %f";
        const urls: []const []const u8 = &.{};
        const commands = try makeExecCommands(allocator, exec, urls);
        defer allocator.free(commands);
        defer for (commands) |c| allocator.free(c);
        try std.testing.expectEqual(1, commands.len);
        try std.testing.expectEqualStrings("example ", commands[0]);
    }

    // 测试没有占位符
    {
        const exec = "example";
        const urls: []const []const u8 = &.{"http://example.com"};
        const commands = try makeExecCommands(allocator, exec, urls);
        defer allocator.free(commands);
        defer for (commands) |c| allocator.free(c);
        try std.testing.expectEqual(1, commands.len);
        try std.testing.expectEqualStrings("example", commands[0]);
    }

    // 测试占位符优先级
    {
        const exec = "example %u %F";
        const urls: []const []const u8 = &.{ "http://example.com", "file:///path/to/file" };
        const commands = try makeExecCommands(allocator, exec, urls);
        defer allocator.free(commands);
        defer for (commands) |c| allocator.free(c);
        try std.testing.expectEqual(2, commands.len);
        try std.testing.expectEqualStrings("example http://example.com %F", commands[0]);
        try std.testing.expectEqualStrings("example file:///path/to/file %F", commands[1]);
    }
}
fn replaceExecIconAndName(allocator: Allocator, exec: []const u8, icon_: ?[]const u8, name: []const u8) ![]u8 {
    var newExec = std.ArrayList(u8){};
    defer newExec.deinit(allocator);
    var i: usize = 0;
    while (i < exec.len) : (i += 1) {
        if (exec[i] == '%' and i + 1 < exec.len) {
            switch (exec[i + 1]) {
                'i' => {
                    if (icon_) |ico| {
                        try newExec.appendSlice(allocator, "--icon ");
                        try newExec.appendSlice(allocator, ico);
                        i += 1;
                    } else {}
                },
                'c' => {
                    try newExec.appendSlice(allocator, name);
                    i += 1;
                },
                '%' => {
                    try newExec.append(allocator, exec[i]);
                    try newExec.append(allocator, exec[i + 1]);
                    i += 1;
                },
                else => {
                    try newExec.append(allocator, exec[i]);
                },
            }
        } else {
            try newExec.append(allocator, exec[i]);
        }
    }
    return try newExec.toOwnedSlice(allocator);
}
test "replaceExecIconAndName" {
    const allocator = std.testing.allocator;
    const exec = "%i example %%%%f %f %U %K %k zz \\ \\// %i %c%cc %%%i %%%%i";
    const excepted = "--icon imIcon example %%%%f %f %U %K %k zz \\ \\// --icon imIcon 名称名称c %%--icon imIcon %%%%i";
    const actual = try replaceExecIconAndName(allocator, exec, "imIcon", "名称");
    defer allocator.free(actual);
    try std.testing.expectEqualStrings(excepted, actual);
}
/// str 中不应该包含没有转义的空格, 未转义的空格会被直接删除
fn unescape(allocator: Allocator, str: []const u8) ![]u8 {
    var newExec = std.ArrayList(u8){};
    defer newExec.deinit(allocator);
    var i: usize = 0;
    // 空格、制表符、换行、"、'、\、>、<、~、|、&、;、$、*、?、#、(、)、`。
    while (i < str.len) : (i += 1) {
        if (str[i] == '\\' and i + 1 < str.len) {
            switch (str[i + 1]) {
                ' ' => {
                    try newExec.append(allocator, ' ');
                    i += 1;
                },
                't' => {
                    try newExec.append(allocator, '\t');
                    i += 1;
                },
                'n' => {
                    try newExec.append(allocator, '\n');
                    i += 1;
                },
                '"' => {
                    try newExec.append(allocator, '"');
                    i += 1;
                },
                '\'' => {
                    try newExec.append(allocator, '\'');
                    i += 1;
                },
                '\\' => {
                    try newExec.append(allocator, '\\');
                    i += 1;
                },
                '>' => {
                    try newExec.append(allocator, '>');
                    i += 1;
                },
                '<' => {
                    try newExec.append(allocator, '<');
                    i += 1;
                },
                '~' => {
                    try newExec.append(allocator, '~');
                    i += 1;
                },
                '|' => {
                    try newExec.append(allocator, '|');
                    i += 1;
                },
                '&' => {
                    try newExec.append(allocator, '&');
                    i += 1;
                },
                ';' => {
                    try newExec.append(allocator, ';');
                    i += 1;
                },
                '$' => {
                    try newExec.append(allocator, '$');
                    i += 1;
                },
                '*' => {
                    try newExec.append(allocator, '*');
                    i += 1;
                },
                '?' => {
                    try newExec.append(allocator, '?');
                    i += 1;
                },
                '#' => {
                    try newExec.append(allocator, '#');
                    i += 1;
                },
                '(' => {
                    try newExec.append(allocator, '(');
                    i += 1;
                },
                ')' => {
                    try newExec.append(allocator, ')');
                    i += 1;
                },
                '`' => {
                    try newExec.append(allocator, '`');
                    i += 1;
                },
                else => {
                    try newExec.append(allocator, str[i]);
                },
            }
        } else if (str[i] == '%' and i + 1 < str.len) {
            if (str[i + 1] == '%') {
                try newExec.append(allocator, '%');
                i += 1;
            } else {
                i += 1;
            }
        } else if (str[i] == ' ') {
            i += 1;
        } else {
            try newExec.append(allocator, str[i]);
        }
    }
    return try newExec.toOwnedSlice(allocator);
}
test "unescapeExec" {
    const allocator = std.testing.allocator;
    {
        const exec =
            \\\t\"\    \*
        ;
        const expected = "\t\" *";
        const actual = try unescape(allocator, exec);
        defer allocator.free(actual);
        try std.testing.expectEqualStrings(expected, actual);
    }
    {
        const exec =
            \\%%f%t\ 
        ;
        const expected = "%f ";
        const actual = try unescape(allocator, exec);
        defer allocator.free(actual);
        try std.testing.expectEqualStrings(expected, actual);
    }
}
fn commandToArgv(allocator: Allocator, command: []const u8) ![]const []const u8 {
    var args = std.ArrayList([]const u8){};
    defer args.deinit(allocator);
    var arg = std.ArrayList(u8){};
    defer arg.deinit(allocator);
    var i: usize = 0;
    while (i < command.len) : (i += 1) {
        if (command[i] == '\\' and i + 1 < command.len) {
            try arg.append(allocator, command[i]);
            try arg.append(allocator, command[i + 1]);
            i += 1;
        } else if (command[i] == ' ') {
            if (arg.items.len > 0) {
                const arg_ = try unescape(allocator, arg.items);
                try args.append(allocator, arg_);
                arg.items.len = 0;
            }
        } else {
            try arg.append(allocator, command[i]);
        }
    }
    if (arg.items.len > 0) {
        const arg_ = try unescape(allocator, arg.items);
        try args.append(allocator, arg_);
    }
    return try args.toOwnedSlice(allocator);
}
test "commandToArgv" {
    const allocator = std.testing.allocator;
    {
        const command = "example arg1 arg2 arg3";
        const expected: []const []const u8 = &.{ "example", "arg1", "arg2", "arg3" };
        const actual = try commandToArgv(allocator, command);
        defer allocator.free(actual);
        defer for (actual) |a| allocator.free(a);
        try testing.expectEqual(expected.len, actual.len);
        for (expected, 0..) |e, i| {
            try testing.expectEqualStrings(e, actual[i]);
        }
    }
    {
        const command = "example arg1\\\" arg2\\* arg3\\ ";
        const expected: []const []const u8 = &.{ "example", "arg1\"", "arg2*", "arg3 " };
        const actual = try commandToArgv(allocator, command);
        defer allocator.free(actual);
        defer for (actual) |a| allocator.free(a);
        try testing.expectEqual(expected.len, actual.len);
        for (expected, 0..) |e, i| {
            try testing.expectEqualStrings(e, actual[i]);
        }
    }
}
fn activateApp(allocator: Allocator, entry: Entry, action: ?Action, urls: []const []const u8) !void {
    var exec: []u8 = undefined;
    defer allocator.free(exec);
    if (action) |act| {
        if (act.exec) |e| {
            exec = try allocator.dupe(u8, e);
        } else {
            return error.ActionHasNoExecKey;
        }
    } else {
        if (entry.exec) |e| {
            exec = try allocator.dupe(u8, e);
        } else {
            return error.AppHasNoExecKey;
        }
    }

    exec = removeExecDeprecatedOptions(exec);
    const newExec = try replaceExecIconAndName(allocator, exec, entry.icon, entry.name);
    allocator.free(exec);
    exec = newExec;
    const cmds = try makeExecCommands(allocator, exec, urls);
    defer allocator.free(cmds);
    defer for (cmds) |c| allocator.free(c);
    for (cmds) |cmd| {
        const argv = blk: {
            const args = try commandToArgv(allocator, cmd);
            if (!entry.terminal) {
                break :blk args;
            } else {
                defer allocator.free(args);
                const terminal = std.process.getEnvVarOwned(allocator, "TERMINAL") catch {
                    return error.TERMINAL_EnvVarCannotBeFound;
                };
                if (terminal.len == 0) return error.TERMINAL_EnvVarCannotBeFound;
                var args_ = try allocator.alloc([]const u8, args.len + 1);
                args_[0] = terminal;
                std.mem.copyForwards([]const u8, args_[1..], args);
                break :blk args_;
            }
        };
        defer allocator.free(argv);
        defer for (argv) |arg| allocator.free(arg);

        var child = std.process.Child.init(argv, allocator);
        child.stderr_behavior = .Ignore;
        child.stdin_behavior = .Ignore;
        child.stdout_behavior = .Ignore;
        const home = std.process.getEnvVarOwned(allocator, "HOME") catch null;
        defer if (home) |h| allocator.free(h);
        child.cwd = home;
        try child.spawn();
        try child.waitForSpawn();
        {
            const child_ = try child.allocator.create(std.process.Child);
            child_.* = child;
            _ = glib.childWatchAdd(child.id, struct {
                fn f(_: glib.Pid, _: c_int, data: ?*anyopaque) callconv(.c) void {
                    const c: *std.process.Child = @ptrCast(@alignCast(data));
                    const a = c.allocator;
                    _ = c.kill() catch {};
                    a.destroy(c);
                }
            }.f, child_);
        }
    }
}
fn listApps(allocator: Allocator) ![]Entry {
    var entrys = std.ArrayList(Entry){};
    defer entrys.deinit(allocator);
    const xdgDataDirs = std.process.getEnvVarOwned(allocator, "XDG_DATA_DIRS") catch |err| {
        std.log.scoped(.apps).err("Failed to get XDG_DATA_DIRS: {t}", .{err});
        return err;
    };
    defer allocator.free(xdgDataDirs);
    var paths = std.mem.splitAny(u8, xdgDataDirs, ":");
    const locals = try getPreferredLocales(allocator);
    defer allocator.free(locals);
    defer for (locals) |l| allocator.free(l);
    var usedID = std.ArrayList([]const u8){};
    defer usedID.deinit(allocator);
    while (paths.next()) |dirPath| {
        const apps = findApps(allocator, dirPath, locals, usedID.items) catch continue;
        defer allocator.free(apps);
        try entrys.appendSlice(allocator, apps);
        for (apps) |app| {
            try usedID.append(allocator, app.id);
        }
    }
    return try entrys.toOwnedSlice(allocator);
}
test {
    const allocator = std.testing.allocator;
    const entrys = try listApps(allocator);
    defer allocator.free(entrys);
    defer for (entrys) |*e| e.deinit(allocator);
}
