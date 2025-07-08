const modules = @import("modules.zig");
const Args = modules.Args;
const Result = modules.Result;
const App = @import("../app.zig").App;
const std = @import("std");
pub const OS = struct {
    const Self = @This();
    allocator: Allocator,
    pub fn getEnv(self: *Self, args: Args, result: *Result) !void {
        const key = try args.string(1);
        const allocator = self.allocator;
        const value = try std.process.getEnvVarOwned(allocator, key);
        defer allocator.free(value);
        _ = try result.commit(value);
    }
    pub fn getSystemInfo(self: *Self, _: Args, result: *Result) !void {
        const info = try SystemInfo.init(self.allocator);
        defer info.deinit(self.allocator);
        _ = try result.commit(info);
    }
    pub fn getUserInfo(self: *Self, _: Args, result: *Result) !void {
        const info = try UserInfo.init(self.allocator);
        defer info.deinit(self.allocator);
        _ = try result.commit(info);
    }
    pub fn exec(self: *Self, args: Args, result: *Result) !void {
        const allocator = self.allocator;
        const argvJson = try args.value(1);
        switch (argvJson) {
            .array => {},
            else => return error.InvalidArgs,
        }
        var argv = try allocator.alloc([]const u8, argvJson.array.items.len);
        defer allocator.free(argv);
        for (argvJson.array.items, 0..) |item, i| {
            argv[i] = item.string;
        }
        const needOutput = try args.bool(2);
        var child = std.process.Child.init(argv, allocator);
        child.stderr_behavior = .Ignore;
        child.stdin_behavior = .Ignore;
        child.stdout_behavior = if (needOutput) .Pipe else .Ignore;
        try child.spawn();
        try child.waitForSpawn();
        if (child.stdout) |stdout| {
            defer stdout.close();
            const stdoutBuf = try stdout.reader().readAllAlloc(allocator, 1024 * 1024);
            defer allocator.free(stdoutBuf);
            _ = try result.commit(stdoutBuf);
        }
    }
};
const Allocator = std.mem.Allocator;
const SystemInfo = struct {
    name: []const u8,
    version: []const u8,
    prettyName: []const u8,
    logo: []const u8,
    arch: []const u8,
    uptime: u64,
    kernel: []const u8,
    cpu: []const u8,
    hostname: []const u8,
    pub fn init(allocator: Allocator) !SystemInfo {
        var info: SystemInfo = undefined;
        {
            var osRelease = std.fs.openFileAbsolute("/etc/os-release", .{}) catch try std.fs.openFileAbsolute("/usr/lib/os-release", .{});
            defer osRelease.close();
            const osReleaseBuf = try osRelease.readToEndAlloc(allocator, 1024 * 1024);
            defer allocator.free(osReleaseBuf);
            const eql = std.mem.eql;
            var lines = std.mem.splitScalar(u8, osReleaseBuf, '\n');
            while (lines.next()) |line| {
                var parts = std.mem.splitScalar(u8, line, '=');
                if (parts.next()) |key| {
                    const value = std.mem.trim(u8, parts.next() orelse "", "\"");
                    if (eql(u8, key, "NAME")) {
                        info.name = try allocator.dupe(u8, value);
                        continue;
                    }
                    if (eql(u8, key, "VERSION")) {
                        info.version = try allocator.dupe(u8, value);
                        continue;
                    }
                    if (eql(u8, key, "PRETTY_NAME")) {
                        info.prettyName = try allocator.dupe(u8, value);
                        continue;
                    }
                    if (eql(u8, key, "LOGO")) {
                        info.logo = try allocator.dupe(u8, value);
                        continue;
                    }
                }
            }
        }
        info.arch = try allocator.dupe(u8, @tagName(@import("builtin").cpu.arch));
        {
            const cpuInfo = try std.fs.openFileAbsolute("/proc/cpuinfo", .{});
            defer cpuInfo.close();
            var buffered = std.io.bufferedReader(cpuInfo.reader());
            var reader = buffered.reader();
            while (true) {
                const line = reader.readUntilDelimiterAlloc(allocator, '\n', 1024 * 1024) catch |err| {
                    if (err == error.EndOfStream) break;
                    return err;
                };
                defer allocator.free(line);
                if (std.mem.startsWith(u8, line, "model name")) {
                    const i = std.mem.indexOf(u8, line, ":").?;
                    info.cpu = try allocator.dupe(u8, line[i + 2 ..]);
                    break;
                }
            }
        }
        {
            const sysinfo = std.posix.uname();
            info.kernel = try std.fmt.allocPrint(allocator, "{s} {s}", .{ std.mem.sliceTo(&sysinfo.sysname, 0), std.mem.sliceTo(&sysinfo.release, 0) });
        }
        {
            const uptime = try std.fs.openFileAbsolute("/proc/uptime", .{});
            defer uptime.close();
            const buf = try uptime.reader().readAllAlloc(allocator, 1024);
            defer allocator.free(buf);
            var fields = std.mem.splitScalar(u8, buf, ' ');
            const uptime_seconds = std.fmt.parseFloat(f64, fields.next().?) catch 0;
            info.uptime = @intFromFloat(uptime_seconds);
        }
        {
            var buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
            const hostname = try std.posix.gethostname(&buf);
            info.hostname = try allocator.dupe(u8, hostname);
        }
        return info;
    }
    pub fn deinit(self: SystemInfo, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.version);
        allocator.free(self.prettyName);
        allocator.free(self.logo);
        allocator.free(self.arch);
        allocator.free(self.kernel);
        allocator.free(self.cpu);
        allocator.free(self.hostname);
    }
};
test {
    const allocator = std.testing.allocator;
    const info = try SystemInfo.init(allocator);
    defer info.deinit(allocator);
}

const UserInfo = struct {
    const c = @cImport({
        @cInclude("unistd.h");
        @cInclude("pwd.h");
    });
    name: []const u8,
    home: []const u8,
    shell: []const u8,
    gecos: []const u8,
    uid: u32,
    gid: u32,
    avatar: ?[]const u8,
    pub fn init(allocator: Allocator) !UserInfo {
        var info: UserInfo = undefined;
        info.avatar = null;
        info.uid = c.getuid();
        info.gid = c.getgid();
        const pw = c.getpwuid(info.uid) orelse return error.InvalidUid;
        info.name = try allocator.dupe(u8, std.mem.sliceTo(pw.*.pw_name, 0));
        info.home = try allocator.dupe(u8, std.mem.sliceTo(pw.*.pw_dir, 0));
        info.shell = try allocator.dupe(u8, std.mem.sliceTo(pw.*.pw_shell, 0));
        info.gecos = try allocator.dupe(u8, std.mem.sliceTo(pw.*.pw_gecos, 0));

        const iconPath1 = try std.fmt.allocPrint(allocator, "/var/lib/AccountsService/icons/{s}", .{info.name});
        const iconPath2 = try std.fmt.allocPrint(allocator, "{s}/.face", .{info.home});
        defer allocator.free(iconPath1);
        defer allocator.free(iconPath2);
        const paths = [_][]const u8{ iconPath1, iconPath2 };
        for (paths) |path| {
            const file = std.fs.openFileAbsolute(path, .{}) catch continue;
            defer file.close();
            var base64 = std.ArrayList(u8).init(allocator);
            defer base64.deinit();
            try std.base64.standard.Encoder.encodeFromReaderToWriter(base64.writer(), file.reader());
            info.avatar = try std.fmt.allocPrint(allocator, "data:image/png;base64,{s}", .{base64.items});
            break;
        }

        return info;
    }
    pub fn deinit(self: UserInfo, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.home);
        allocator.free(self.shell);
        allocator.free(self.gecos);
        if (self.avatar) |icon| allocator.free(icon);
    }
};
test {
    const allocator = std.testing.allocator;
    const info = try UserInfo.init(allocator);
    defer info.deinit(allocator);
}
