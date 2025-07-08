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
    pub fn getInfo(self: *Self, _: Args, result: *Result) !void {
        const info = try Info.init(self.allocator);
        defer info.deinit(self.allocator);
        _ = try result.commit(info);
    }
    pub fn exec(self: *Self, args: Args, _: *Result) !void {
        const allocator = self.allocator;
        const argvJson = try args.value(1);
        var argv = try allocator.alloc([]const u8, argvJson.array.items.len);
        defer allocator.free(argv);
        for (argvJson.array.items, 0..) |item, i| {
            argv[i] = item.string;
        }
        var child = std.process.Child.init(argv, allocator);
        try child.spawn();
        try child.waitForSpawn();
    }
    pub fn execWithOutput(self: *Self, args: Args, result: *Result) !void {
        const allocator = self.allocator;
        const argvJson = try args.value(1);
        var argv = try allocator.alloc([]const u8, argvJson.array.items.len);
        defer allocator.free(argv);
        for (argvJson.array.items, 0..) |item, i| {
            argv[i] = item.string;
        }
        var child = std.process.Child.init(argv, allocator);
        child.stdout_behavior = .Pipe;
        defer child.stdout.?.close();
        try child.spawn();
        try child.waitForSpawn();
        const stdout = child.stdout.?.reader();
        const stdoutBuf = try stdout.readAllAlloc(allocator, 1024 * 1024);
        defer allocator.free(stdoutBuf);
        _ = try result.commit(stdoutBuf);
    }
};
const Allocator = std.mem.Allocator;
const Info = struct {
    name: []const u8,
    version: []const u8,
    prettyName: []const u8,
    logo: []const u8,
    arch: []const u8,
    uptime: u64,
    kernel: []const u8,
    cpu: []const u8,
    hostname: []const u8,
    pub fn init(allocator: Allocator) !Info {
        var info: Info = undefined;
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
    pub fn deinit(self: Info, allocator: Allocator) void {
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
    const info = try Info.init(allocator);
    defer info.deinit(allocator);
}
