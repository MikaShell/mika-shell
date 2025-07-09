const filenames = [_][]const u8{
    "mika-shell.json",
    "style.css",
    "index.html",
    "apps.html",
    "hyprland.html",
    "notifd.html",
    "tray.html",
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
        f[i].name = name;
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
        try dir.makePath(dirPath);
        dir = try fs.cwd().openDir(dirPath, .{});
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
