const dbus = @import("dbus");
const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
fn getSessionID(allocator: Allocator) ![]const u8 {
    return std.process.getEnvVarOwned(allocator, "XDG_SESSION_ID") catch {
        return error.FailedToGetSessionID;
    };
}
fn registerAgent(bus: *dbus.Bus, locale: []const u8, path: []const u8) !void {
    if (bus.type != .System) {
        return error.DBusNotSystemBus;
    }
    const allocator = bus.allocator;
    const id = try getSessionID(allocator);
    defer allocator.free(id);
    const ArgsType = .{
        dbus.Struct(.{
            dbus.String,
            dbus.Dict(dbus.String, dbus.AnyVariant),
        }),
        dbus.String,
        dbus.String,
    };
    std.debug.print("Registering agent: {s}\n", .{id});
    const result = bus.call(
        "org.freedesktop.PolicyKit1",
        "/org/freedesktop/PolicyKit1/Authority",
        "org.freedesktop.PolicyKit1.Authority",
        "RegisterAuthenticationAgent",
        ArgsType,
        .{
            .{
                "unix-session",
                &.{.{ .key = "session-id", .value = dbus.Variant(dbus.String).init(&id) }},
            },
            locale,
            path,
        },
    ) catch {
        return error.FailedToRegisterAgent;
    };

    defer result.deinit();
}
fn unregisterAgent(allocator: Allocator, conn: *dbus.Connection, path: []const u8) !void {
    var err: dbus.Error = undefined;
    err.init();
    defer err.deinit();
    const id = try getSessionID(allocator);
    defer allocator.free(id);
    const method = "UnregisterAuthenticationAgent";
    const ArgsType = .{
        dbus.Struct(.{
            dbus.String,
            dbus.Dict(dbus.String, dbus.AnyVariant),
        }),
        dbus.String,
    };
    const result = dbus.call(
        allocator,
        conn,
        &err,
        "org.freedesktop.PolicyKit1",
        "/org/freedesktop/PolicyKit1/Authority",
        "org.freedesktop.PolicyKit1.Authority",
        method,
        ArgsType,
        .{
            .{
                "unix-session",
                &.{.{ .key = "session-id", .value = dbus.Variant(dbus.String).init(&id) }},
            },
            path,
        },
    ) catch {
        return error.FailedToRegisterAgent;
    };
    defer result.deinit();
}
pub const Agent = struct {
    const Self = @This();
    const Identitie = union(enum) {
        unixUser: u32, // pid
        unixGroup: u32, // gid
    };
    pub const Context = struct {
        actionId: []const u8,
        message: []const u8,
        iconName: []const u8,
        details: std.StringHashMap([]const u8),
        cookie: []const u8,
        identities: []Identitie,
        fn init(gpa: Allocator, in: *dbus.MessageIter) !Context {
            const actionId = in.next(dbus.String).?;
            const message = in.next(dbus.String).?;
            const iconName = in.next(dbus.String).?;
            const details = in.next(dbus.Dict(dbus.String, dbus.String)).?;
            const cookie = in.next(dbus.String).?;
            const identities = in.next(DirectionDBus).?;

            var ctx: Context = .{
                .actionId = actionId,
                .message = message,
                .iconName = iconName,
                .cookie = cookie,
                .details = std.StringHashMap([]const u8).init(gpa),
                .identities = undefined,
            };
            errdefer ctx.details.deinit();

            for (details) |detail| {
                try ctx.details.put(detail.key, detail.value);
            }
            const eql = std.mem.eql;
            var identitiesList = std.ArrayList(Identitie){};

            for (identities) |identity| {
                const kind = identity[0];
                const details_ = identity[1];
                if (eql(u8, kind, "unix-user")) {
                    const uid = details_[0].value.as(dbus.UInt32);
                    try identitiesList.append(gpa, .{ .unixUser = uid });
                }
                if (eql(u8, kind, "unix-group")) {
                    const gid = details_[0].value.as(dbus.UInt32);
                    try identitiesList.append(gpa, .{ .unixGroup = gid });
                }
            }

            ctx.identities = try identitiesList.toOwnedSlice(gpa);
            return ctx;
        }
        fn deinit(self: *Context, gpa: Allocator) void {
            self.details.deinit();
            gpa.free(self.identities);
        }
        pub fn jsonStringify(self: @This(), jw: *std.json.Stringify) !void {
            try jw.beginObject();

            try jw.objectField("actionId");
            try jw.write(self.actionId);
            try jw.objectField("message");
            try jw.write(self.message);
            try jw.objectField("iconName");
            try jw.write(self.iconName);
            try jw.objectField("cookie");
            try jw.write(self.cookie);
            try jw.objectField("details");
            try jw.beginObject();
            var it = self.details.iterator();
            while (it.next()) |entry| {
                try jw.objectField(entry.key_ptr.*);
                try jw.write(entry.value_ptr.*);
            }
            try jw.endObject();

            try jw.objectField("identities");
            try jw.write(self.identities);

            try jw.endObject();
        }
    };
    const Session = struct {
        async: dbus.Context.Async,
        ctx: Context,
    };
    const path = "/mikashell/PolkitAgent";
    gpa: Allocator,
    bus: *dbus.Bus,
    sessions: std.ArrayList(Session),
    userdata: *anyopaque,
    onBeginAuthentication: *const fn (data: *anyopaque, Context) void,
    onCancelAuthentication: *const fn (data: *anyopaque, cookie: []const u8) void,
    fn beginAuthentication(self: *Self, ctx: *dbus.Context) !void {
        const in = ctx.getInput().?;
        var session: Session = undefined;
        session.ctx = try Context.init(self.gpa, in);
        session.async = ctx.async();
        try self.sessions.append(self.gpa, session);
        self.onBeginAuthentication(self.userdata, session.ctx);
    }
    fn cancelAuthentication(self: *Self, ctx: *dbus.Context) !void {
        const cookie = ctx.getInput().?.next(dbus.String).?;
        self.onCancelAuthentication(self.userdata, cookie);
        try self.cancel(cookie);
    }
    pub fn init(T: type, gpa: Allocator, bus: *dbus.Bus, options: struct {
        userdata: *T,
        onBeginAuthentication: *const fn (data: *T, Context) void,
        onCancelAuthentication: *const fn (data: *T, cookie: []const u8) void,
    }) !*Self {
        const self = try gpa.create(Self);
        errdefer gpa.destroy(self);
        self.* = .{
            .gpa = gpa,
            .bus = bus,
            .sessions = std.ArrayList(Session){},
            .userdata = @ptrCast(options.userdata),
            .onBeginAuthentication = @ptrCast(options.onBeginAuthentication),
            .onCancelAuthentication = @ptrCast(options.onCancelAuthentication),
        };
        try self.bus.publish(Agent, path, Interface, self, null);
        // TODO: 正确传递 locale
        registerAgent(self.bus, "en_US.UTF-8", path) catch {
            std.log.err("Failed to register polkit agent: {s}\n", .{self.bus.err.message()});
            return error.FailedToRegisterPolkitAgent;
        };
        return self;
    }
    pub fn deinit(self: *Self) void {
        unregisterAgent(self.gpa, self.bus.conn, path) catch {
            std.log.err("Failed to unregister polkit agent: {s}\n", .{self.bus.err.message()});
        };
        self.bus.unpublish(path, Interface.name);
        for (self.sessions.items) |*session| {
            _ = session.async.finish() catch {};
            session.ctx.deinit(self.gpa);
        }
        self.sessions.deinit(self.gpa);
        self.gpa.destroy(self);
    }
    pub fn auth(self: *Self, T: type, gpa: Allocator, cookie: []const u8, username: []const u8, password: []const u8, callback: *const fn (data: T, ok: bool, err: ?[]const u8) void, data: T) !void {
        const helper = @import("build-options").polkitAgentHelper;
        var proc = std.process.Child.init(&.{ helper, username }, gpa);
        proc.stdout_behavior = .Ignore;
        proc.stdin_behavior = .Pipe;
        proc.stderr_behavior = .Pipe;

        try proc.spawn();

        const glib = @import("glib");

        const input = proc.stdin.?;

        try input.writeAll(cookie);
        try input.writeAll("\n");
        try input.writeAll(password);
        try input.writeAll("\n");

        {
            const AuthContext = struct {
                child: std.process.Child,
                gpa: Allocator,
                agent: *Self,
                cookie: []const u8,
                callback: *const fn (data: T, ok: bool, err: ?[]const u8) void,
                data: T,
            };

            const ctx = try gpa.create(AuthContext);
            ctx.* = .{
                .child = proc,
                .gpa = gpa,
                .agent = self,
                .cookie = try gpa.dupe(u8, cookie),
                .callback = callback,
                .data = data,
            };
            _ = glib.childWatchAdd(proc.id, struct {
                fn f(_: glib.Pid, _: c_int, ctxInner_: ?*anyopaque) callconv(.c) void {
                    const ctxInner: *AuthContext = @ptrCast(@alignCast(ctxInner_));
                    var child = ctxInner.child;
                    var stderr = child.stderr.?;
                    const err = blk: {
                        const e = stderr.readToEndAlloc(ctxInner.gpa, 10 * 1024 * 1024) catch break :blk null;
                        if (e.len == 0) break :blk null;
                        break :blk e;
                    };
                    defer if (err) |e| ctxInner.gpa.free(e);

                    _ = child.kill() catch {};
                    ctxInner.callback(ctxInner.data, err == null, if (err) |e| std.mem.trimEnd(u8, e, "\n") else null);
                    if (err == null) ctxInner.agent.cancel(ctxInner.cookie) catch |err_| {
                        std.log.err("Failed to finish authentication: {t}: {s}", .{ err_, ctxInner.cookie });
                    };
                    ctxInner.gpa.free(ctxInner.cookie);
                    ctxInner.gpa.destroy(ctxInner);
                }
            }.f, ctx);
        }
    }
    pub fn cancel(self: *Self, cookie: []const u8) !void {
        for (self.sessions.items, 0..) |*session, i| {
            if (!std.mem.eql(u8, session.ctx.cookie, cookie)) {
                continue;
            }
            try session.async.finish();
            session.ctx.deinit(self.gpa);
            _ = self.sessions.swapRemove(i);
            return;
        }
        return error.SessionNotFound;
    }
};
const IdentityDBus = dbus.Struct(.{
    dbus.String,
    dbus.Dict(
        dbus.String,
        dbus.AnyVariant,
    ),
});
const DirectionDBus = dbus.Array(IdentityDBus);
const Interface = dbus.Interface(Agent){
    .name = "org.freedesktop.PolicyKit1.AuthenticationAgent",
    .method = &.{
        .{
            .name = "BeginAuthentication",
            .func = Agent.beginAuthentication,
            .args = &.{
                .{ .direction = .in, .name = "action_id", .type = dbus.String },
                .{ .direction = .in, .name = "message", .type = dbus.String },
                .{ .direction = .in, .name = "icon_name", .type = dbus.String },
                .{ .direction = .in, .name = "details", .type = dbus.Dict(dbus.String, dbus.String) },
                .{ .direction = .in, .name = "cookie", .type = dbus.String },
                .{ .direction = .in, .name = "identities", .type = DirectionDBus },
            },
        },
        .{
            .name = "CancelAuthentication",
            .func = Agent.cancelAuthentication,
            .args = &.{
                .{ .direction = .in, .name = "cookie", .type = dbus.String },
            },
        },
    },
};
