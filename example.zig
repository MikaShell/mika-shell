const prefix = "example/";
const filenames = [_][]const u8{
    "example/example/debug/apps.html",
    "example/example/debug/hyprland.html",
    "example/example/debug/index.html",
    "example/example/debug/network.html",
    "example/example/debug/notifd.html",
    "example/example/debug/screenshot.html",
    "example/example/debug/style.css",
    "example/example/debug/test-open.html",
    "example/example/debug/tray.html",
    "example/example/alias.json",
    "example/example/bar.html",
    "example/example/bongocat.html",
    "example/example/dock.html",
    "example/example/extra.js",
    "example/example/showkeys.html",
    "example/example/traymenu.html",
    "example/config.json",
    "example/notify.html",
};

const std = @import("std");
const fs = std.fs;
const File = struct {
    name: []const u8,
    bytes: []const u8,
};

pub const files = blk: {
    var f: [filenames.len]File = undefined;
    for (filenames, 0..) |name, i| {
        f[i].name = name[prefix.len..];
        f[i].bytes = @embedFile(name);
    }
    break :blk f;
};
fn writeFile(dir: fs.Dir, file: File) !void {
    if (fs.path.dirname(file.name)) |dirName| {
        try dir.makePath(dirName);
    }
    const f = try dir.createFile(file.name, .{});
    defer f.close();
    try f.writeAll(file.bytes);
}
pub fn write(dirPath: []const u8) !void {
    var dir: fs.Dir = undefined;
    if (fs.path.isAbsolute(dirPath)) {
        try mkdir(dirPath);
        dir = try fs.openDirAbsolute(dirPath, .{});
    } else {
        var cwd = fs.cwd();
        try cwd.makePath(dirPath);
        dir = try cwd.openDir(dirPath, .{});
    }
    defer dir.close();
    for (files) |file| {
        try writeFile(dir, file);
    }
}
fn mkdir(path: []const u8) !void {
    std.debug.assert(fs.path.isAbsolute(path));
    fs.accessAbsolute(path, .{}) catch {
        const dir = fs.path.dirname(path).?;
        try mkdir(dir);
        try fs.makeDirAbsolute(path);
        return;
    };
}
