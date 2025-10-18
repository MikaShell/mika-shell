const modules = @import("root.zig");
const Args = modules.Args;
const Context = modules.Context;
const InitContext = modules.InitContext;
const Registry = modules.Registry;
const App = @import("../app.zig").App;
const std = @import("std");
pub const OS = struct {
    const Self = @This();
    allocator: Allocator,
    pub fn init(ctx: InitContext) !*Self {
        const self = try ctx.allocator.create(Self);
        self.allocator = ctx.allocator;
        return self;
    }
    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.destroy(self);
    }
    pub fn register() Registry(Self) {
        return .{
            .exports = &.{
                .{ "getEnv", getEnv },
                .{ "getSystemInfo", getSystemInfo },
                .{ "getUserInfo", getUserInfo },
                .{ "exec", exec },
                .{ "execAsync", execAsync },
                .{ "write", write },
                .{ "read", read },
            },
        };
    }
    pub fn getEnv(self: *Self, ctx: *Context) !void {
        const key = try ctx.args.string(0);
        const allocator = self.allocator;
        const value: []const u8 = std.process.getEnvVarOwned(allocator, key) catch {
            ctx.commit(null);
            return;
        };
        defer allocator.free(value);
        ctx.commit(value);
    }
    pub fn getSystemInfo(self: *Self, ctx: *Context) !void {
        const info = try SystemInfo.init(self.allocator);
        defer info.deinit(self.allocator);
        ctx.commit(info);
    }
    pub fn getUserInfo(self: *Self, ctx: *Context) !void {
        const uid = try ctx.args.integer(0);
        const info = try UserInfo.init(self.allocator, if (uid <= 0) null else @intCast(uid));
        defer info.deinit(self.allocator);
        ctx.commit(info);
    }
    const Options = struct {
        needOutput: bool,
        block: bool,
        base64Output: bool,
    };
    const glib = @import("glib");
    pub fn exec(self: *Self, ctx: *Context) !void {
        const allocator = self.allocator;
        const argvJson = try ctx.args.value(0);
        if (argvJson != .array) {
            return error.InvalidArgs;
        }
        var argv = try allocator.alloc([]const u8, argvJson.array.items.len);
        defer allocator.free(argv);
        for (argvJson.array.items, 0..) |item, i| {
            argv[i] = item.string;
        }
        const output_str: []const u8 = try ctx.args.string(1);
        const eql = std.mem.eql;
        if (!(eql(u8, output_str, "base64") or eql(u8, output_str, "string") or eql(u8, output_str, "ignore"))) {
            ctx.errors("Invalid output option: {s}, expected 'base64','string' or 'ignore'", .{output_str});
            return;
        }
        const inheritStderr = try ctx.args.bool(2);

        var child = std.process.Child.init(argv, allocator);
        const home = std.process.getEnvVarOwned(allocator, "HOME") catch null;
        defer if (home) |h| allocator.free(h);
        child.cwd = home;
        child.stderr_behavior = if (inheritStderr) .Inherit else .Ignore;
        child.stdin_behavior = .Ignore;
        child.stdout_behavior = if (!eql(u8, output_str, "ignore")) .Pipe else .Ignore;
        try child.spawn();
        try child.waitForSpawn();
        const Ctx = struct {
            child: std.process.Child,
            base64Output: bool,
            result: modules.Async,
            allocator: Allocator,
        };
        const ctx_ = try allocator.create(Ctx);
        ctx_.* = .{
            .child = child,
            .base64Output = eql(u8, output_str, "base64"),
            .result = ctx.async(),
            .allocator = allocator,
        };
        _ = glib.childWatchAdd(child.id, struct {
            fn f(_: glib.Pid, _: c_int, data: ?*anyopaque) callconv(.c) void {
                const c: *Ctx = @ptrCast(@alignCast(data));
                const alloc = c.allocator;
                if (c.child.stdout) |stdout| {
                    defer stdout.close();
                    var buf: [512]u8 = undefined;
                    var reader = stdout.reader(&buf);
                    const stdoutBuf: []const u8 = reader.interface.allocRemaining(alloc, .limited(1024 * 1024 * 10)) catch |err| {
                        c.result.errors("Failed to read stdout: {t}", .{err});
                        return;
                    };
                    defer alloc.free(stdoutBuf);
                    if (c.base64Output) {
                        const base64 = std.fmt.allocPrint(alloc, "{b64}", .{stdoutBuf}) catch |err| {
                            c.result.errors("Failed to encode stdout: {t}", .{err});
                            return;
                        };
                        defer alloc.free(base64);
                        c.result.commit(base64);
                    } else {
                        c.result.commit(stdoutBuf);
                    }
                } else {
                    c.result.commit({});
                }
                _ = c.child.kill() catch {};
                alloc.destroy(c);
            }
        }.f, ctx_);
    }
    pub fn execAsync(self: *Self, ctx: *Context) !void {
        const allocator = self.allocator;
        const argvJson = try ctx.args.value(0);
        if (argvJson != .array) {
            return error.InvalidArgs;
        }
        const inheritStderr = try ctx.args.bool(1);
        var argv = try allocator.alloc([]const u8, argvJson.array.items.len);
        defer allocator.free(argv);
        for (argvJson.array.items, 0..) |item, i| {
            argv[i] = item.string;
        }
        var child = std.process.Child.init(argv, allocator);
        const home = std.process.getEnvVarOwned(allocator, "HOME") catch null;
        defer if (home) |h| allocator.free(h);
        child.cwd = home;
        child.stderr_behavior = if (inheritStderr) .Inherit else .Ignore;
        child.stdin_behavior = .Ignore;
        child.stdout_behavior = .Ignore;
        try child.spawn();
        try child.waitForSpawn();
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

        ctx.commit(child.id);
    }

    pub fn write(self: *Self, ctx: *Context) !void {
        const path = try ctx.args.string(0);
        const base64 = try ctx.args.string(1);
        const decoder = std.base64.standard.Decoder;
        const data = try self.allocator.alloc(u8, try decoder.calcSizeForSlice(base64));
        defer self.allocator.free(data);
        try decoder.decode(data, base64);
        var file: std.fs.File = undefined;
        if (std.fs.path.isAbsolute(path)) {
            file = try std.fs.createFileAbsolute(path, .{});
        } else {
            file = try std.fs.cwd().createFile(path, .{});
        }
        defer file.close();
        try file.writeAll(data);
    }
    pub fn read(self: *Self, ctx: *Context) !void {
        const path = try ctx.args.string(0);
        var file: std.fs.File = undefined;
        if (std.fs.path.isAbsolute(path)) {
            file = try std.fs.openFileAbsolute(path, .{});
        } else {
            file = try std.fs.cwd().openFile(path, .{});
        }
        defer file.close();
        var buf: [512]u8 = undefined;
        var reader = file.reader(&buf);
        var r = &reader.interface;
        const data = try r.allocRemaining(self.allocator, .limited(1024 * 1024 * 10));
        defer self.allocator.free(data);
        const base64 = try std.fmt.allocPrint(self.allocator, "{b64}", .{data});
        defer self.allocator.free(base64);
        ctx.commit(base64);
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
        var info: SystemInfo = .{
            .name = "",
            .version = "",
            .prettyName = "",
            .logo = "",
            .arch = "",
            .uptime = 0,
            .kernel = "",
            .cpu = "",
            .hostname = "",
        };
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
            var buf: [512]u8 = undefined;
            var reader = cpuInfo.reader(&buf);
            var r = &reader.interface;
            while (true) {
                const line = r.takeDelimiterExclusive('\n') catch |err| {
                    if (err == error.EndOfStream) break;
                    return err;
                };
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
            var sysinfo: std.os.linux.Sysinfo = undefined;
            if (std.os.linux.sysinfo(&sysinfo) == 0) {
                info.uptime = @intCast(sysinfo.uptime);
            }
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
    pub fn init(allocator: Allocator, uid: ?u32) !UserInfo {
        var info: UserInfo = undefined;
        info.avatar = null;
        info.uid = uid orelse c.getuid();
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
            var buf: [512]u8 = undefined;
            var reader = file.reader(&buf);
            var r = &reader.interface;
            const payload = try r.allocRemaining(allocator, .limited(1024 * 1024 * 10));
            defer allocator.free(payload);
            info.avatar = try std.fmt.allocPrint(allocator, "data:image/png;base64,{b64}", .{payload});
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
