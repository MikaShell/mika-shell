const std = @import("std");
const jsc = @import("jsc");
const webkit = @import("webkit");
/// 放心地在 Modules 回调中使用 try xxx(n), xxx是参数类型, n是参数的位置
///
/// 如果参数不符合预期,则会返回 error.InvalidArgs, 可以直接将此错误返回给前端
pub const Args = struct {
    items: []std.json.Value,
    fn verifyIndex(self: Args, index: usize) !void {
        if (index >= self.items.len) return error.InvalidArgs;
    }
    pub fn value(self: Args, index: usize) !std.json.Value {
        try self.verifyIndex(index);
        return self.items[index];
    }
    pub fn @"bool"(self: Args, index: usize) !bool {
        try self.verifyIndex(index);
        switch (self.items[index]) {
            .bool => |b| return b,
            else => return error.InvalidArgs,
        }
    }
    pub fn integer(self: Args, index: usize) !i64 {
        try self.verifyIndex(index);
        switch (self.items[index]) {
            .integer => |i| return i,
            else => return error.InvalidArgs,
        }
    }
    pub fn uInteger(self: Args, index: usize) !u64 {
        const i = try self.integer(index);
        if (i < 0) return error.InvalidArgs;
        return @intCast(i);
    }
    pub fn float(self: Args, index: usize) !f64 {
        try self.verifyIndex(index);
        switch (self.items[index]) {
            .float => |f| return f,
            else => return error.InvalidArgs,
        }
    }
    pub fn string(self: Args, index: usize) ![]const u8 {
        try self.verifyIndex(index);
        switch (self.items[index]) {
            .string => |s| return s,
            else => return error.InvalidArgs,
        }
    }
    pub fn array(self: Args, index: usize) !std.json.Array {
        try self.verifyIndex(index);
        switch (self.items[index]) {
            .array => |a| return a,
            else => return error.InvalidArgs,
        }
    }
    pub fn object(self: Args, index: usize) !std.json.ObjectMap {
        try self.verifyIndex(index);
        switch (self.items[index]) {
            .object => |o| return o,
            else => return error.InvalidArgs,
        }
    }
};
const glib = @import("glib");
fn replyCommit(reply: *webkit.ScriptMessageReply, ctx: *jsc.Context, value: anytype) void {
    switch (@typeInfo(@TypeOf(value))) {
        .void => {
            const res = jsc.Value.newUndefined(ctx);
            defer res.unref();
            reply.returnValue(res);
        },
        else => {
            const res = @import("../utils.zig").JSValue.from(ctx, value);
            defer res.unref();
            reply.returnValue(res);
        },
    }
}
fn replyErrors(reply: *webkit.ScriptMessageReply, comptime fmt: []const u8, args: anytype) void {
    const allocator = std.heap.page_allocator;
    const err = std.fmt.allocPrint(allocator, fmt, args) catch @panic("OOM");
    defer allocator.free(err);
    const msg = std.fmt.allocPrintSentinel(allocator, "Failed to call method: {s}", .{err}, 0) catch @panic("OOM");
    defer allocator.free(msg);
    reply.returnErrorMessage(msg.ptr);
}
pub const Async = struct {
    const Self = @This();
    reply: *webkit.ScriptMessageReply,
    ctx: *jsc.Context,
    pub fn commit(self: Self, value: anytype) void {
        replyCommit(self.reply, self.ctx, value);
        self.reply.unref();
        self.ctx.unref();
    }
    pub fn errors(self: Self, comptime fmt: []const u8, args: anytype) void {
        replyErrors(self.reply, fmt, args);
        self.reply.unref();
        self.ctx.unref();
    }
};
pub const Context = struct {
    const Self = @This();
    caller: u64,
    arena: std.mem.Allocator,
    reply: ?*webkit.ScriptMessageReply,
    args: Args,
    ctx: *jsc.Context,
    method: []const u8,
    // 确保 method 为字符串
    // 确保 args 为数组
    pub fn init(allocator: std.mem.Allocator, caller: u64, method: []const u8, args: *jsc.Value, reply: *webkit.ScriptMessageReply) !*Self {
        const arena = try allocator.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(allocator);
        const alloc = arena.allocator();
        const argsJson = args.toJson(0);
        defer glib.free(argsJson);
        const self = try alloc.create(Self);
        self.* = .{
            .caller = caller,
            .arena = alloc,
            .reply = reply,
            .args = .{ .items = (try std.json.parseFromSlice(std.json.Value, alloc, std.mem.span(argsJson), .{})).value.array.items },
            .ctx = args.getContext(),
            .method = try alloc.dupe(u8, method),
        };
        return self;
    }
    pub fn deinit(self: *Self) void {
        self.ctx.unref();
        const arena: *std.heap.ArenaAllocator = @ptrCast(@alignCast(self.arena.ptr));
        const allocator = arena.child_allocator;
        arena.deinit();
        allocator.destroy(arena);
    }
    pub fn commit(self: *Self, value: anytype) void {
        replyCommit(self.reply.?, self.ctx, value);
        self.reply = null;
    }
    pub fn errors(self: *Self, comptime fmt: []const u8, args: anytype) void {
        replyErrors(self.reply.?, fmt, args);
        self.reply = null;
    }
    pub fn async(self: *Self) Async {
        defer self.reply = null;
        self.ctx.ref();
        return .{ .reply = self.reply.?.ref(), .ctx = self.ctx };
    }
};

const Allocator = std.mem.Allocator;

pub fn Callable(comptime T: type) type {
    return *const fn (self: T, ctx: *Context) anyerror!void;
}
const App = @import("../app.zig").App;
const Webview = @import("../app.zig").Webview;
pub const InitContext = struct {
    allocator: std.mem.Allocator,
    app: *App,
    systemBus: *dbus.Bus,
    sessionBus: *dbus.Bus,
};
pub fn Registry(T: type) type {
    return struct {
        exports: []const std.meta.Tuple(&.{ []const u8, Callable(*T) }) = &.{},
        events: []const events.Events = &.{},
    };
}
const dbus = @import("dbus");
const events = @import("../events.zig");

pub fn Entry(comptime T: type) type {
    return struct {
        self: T,
        call: Callable(T),
    };
}
const AnyEntry = Entry(*anyopaque);
pub const Modules = struct {
    const Registered = struct {
        ptr: *anyopaque,
        deinit: *const fn (*anyopaque, Allocator) void,
    };
    pub const EventGroup = struct {
        events: []const events.Events,
        data: ?*anyopaque,
        start: ?*const fn (?*anyopaque) anyerror!void,
        stop: ?*const fn (?*anyopaque) anyerror!void,
        onChanged: ?*const fn (?*anyopaque, events.ChangeState, events.Events) void,
    };
    const Option = struct {
        app: *App,
        systemBus: *dbus.Bus,
        sessionBus: *dbus.Bus,
    };
    allocator: std.mem.Allocator,
    table: std.StringHashMap(AnyEntry),
    ctx: InitContext,
    registered: std.ArrayList(Registered),
    eventGroups: std.ArrayList(EventGroup),

    pub fn init(
        allocator: std.mem.Allocator,
        option: Option,
    ) *Modules {
        const m = allocator.create(Modules) catch unreachable;
        m.* = .{
            .table = std.StringHashMap(AnyEntry).init(allocator),
            .allocator = allocator,
            .ctx = .{
                .allocator = allocator,
                .app = option.app,
                .systemBus = option.systemBus,
                .sessionBus = option.sessionBus,
            },
            .registered = std.ArrayList(Registered){},
            .eventGroups = std.ArrayList(EventGroup){},
        };
        return m;
    }
    pub fn deinit(self: *Modules) void {
        self.table.deinit();
        for (self.registered.items) |module| {
            module.deinit(module.ptr, self.allocator);
        }
        self.registered.deinit(self.allocator);
        for (self.eventGroups.items) |group| {
            self.allocator.free(group.events);
        }
        self.eventGroups.deinit(self.allocator);
        self.allocator.destroy(self);
    }
    pub fn call(self: *Modules, name: []const u8, ctx: *Context) !void {
        const entry = self.table.get(name) orelse {
            return error.FunctionNotFound;
        };
        return entry.call(entry.self, ctx);
    }
    pub fn mount(self: *Modules, comptime Module_: type, comptime name: []const u8) !void {
        const m = try Module_.init(self.ctx);
        try self.registered.append(self.allocator, .{
            .ptr = m,
            .deinit = @ptrCast(&Module_.deinit),
        });
        const functions = comptime blk: {
            const registry: Registry(Module_) = Module_.register();
            const table = registry.exports;
            var tb: [table.len]std.meta.Tuple(&.{ []const u8, Callable(*Module_) }) = undefined;
            for (table, 0..) |entry, i| {
                const name_ = name ++ "." ++ entry[0];
                tb[i] = .{ name_, entry[1] };
            }
            break :blk tb;
        };
        inline for (functions) |entry| {
            self.register(m, entry[0], entry[1]);
        }
        const events_ = comptime blk: {
            const registry: Registry(Module_) = Module_.register();
            break :blk registry.events;
        };
        if (events_.len > 0) {
            var start: ?*const fn (*Module_) anyerror!void = null;
            var stop: ?*const fn (*Module_) anyerror!void = null;
            var onChanged: ?*const fn (*Module_, events.ChangeState, events.Events) void = null;
            if (@hasDecl(Module_, "eventStart")) {
                start = &Module_.eventStart;
            }
            if (@hasDecl(Module_, "eventStop")) {
                stop = &Module_.eventStop;
            }
            if (@hasDecl(Module_, "eventOnChange")) {
                onChanged = &Module_.eventOnChange;
            }
            try self.eventGroups.append(self.allocator, .{
                .events = try self.allocator.dupe(events.Events, events_),
                .start = @ptrCast(start),
                .stop = @ptrCast(stop),
                .data = @ptrCast(m),
                .onChanged = @ptrCast(onChanged),
            });
        }
    }
    fn register(
        self: *Modules,
        module: anytype,
        comptime name: []const u8,
        comptime function: Callable(@TypeOf(module)),
    ) void {
        const entry = AnyEntry{
            .self = module,
            .call = @ptrCast(function),
        };
        if (self.table.contains(name)) {
            @panic("function already registered");
        }
        self.table.put(name, entry) catch unreachable;
    }
};
pub const Emitter = struct {
    const Self = @This();
    const Group = struct {
        count: u32,
        group: Modules.EventGroup,
        fn has(self: Group, event: events.Events) bool {
            for (self.group.events) |e| {
                if (e == event) return true;
            }
            return false;
        }
        fn addOne(self: *Group, event: events.Events) !void {
            self.count += 1;
            if (self.count == 1) {
                if (self.group.start) |start| {
                    try start(self.group.data);
                }
            }
            if (self.group.onChanged) |onChanged| {
                onChanged(self.group.data, .add, event);
            }
        }
        fn removeOne(self: *Group, event: events.Events) !void {
            self.count -= 1;
            if (self.group.onChanged) |onChanged| {
                onChanged(self.group.data, .remove, event);
            }
            if (self.count == 0) {
                if (self.group.stop) |stop| {
                    try stop(self.group.data);
                }
            }
        }
    };
    const Service = struct {
        event: events.Events,
        path: []const u8,
        webview: ?*Webview,
    };
    allocator: Allocator,
    app: *App,
    subscriber: std.AutoHashMap(events.Events, std.ArrayList(u64)),
    channel: *events.EventChannel,
    groups: []Group,
    services: std.ArrayList(Service),
    pub fn init(
        allocator: Allocator,
        options: struct {
            app: *App,
            channel: *events.EventChannel,
            eventGroups: []Modules.EventGroup,
            // [event, path, event, path, ...]
            // e.g. ["notifd.add:/notification.html", "window.close:/app/window2"]
            // 如果页面存在，则不发送
            services: []const []const u8,
        },
    ) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        var groups = try allocator.alloc(Group, options.eventGroups.len);
        errdefer allocator.free(groups);

        for (options.eventGroups, 0..) |group, i| {
            groups[i] = .{ .count = 0, .group = group };
        }
        self.* = .{
            .allocator = allocator,
            .app = options.app,
            .subscriber = std.AutoHashMap(events.Events, std.ArrayList(u64)).init(allocator),
            .channel = options.channel,
            .groups = groups,
            .services = std.ArrayList(Service){},
        };
        errdefer self.services.deinit(self.allocator);

        for (options.services) |service| {
            const i = std.mem.indexOf(u8, service, ":").?;

            const event: events.Events = blk: {
                inline for (@typeInfo(events.Events).@"enum".fields) |field| {
                    if (std.mem.eql(u8, field.name, service[0..i])) {
                        break :blk @enumFromInt(field.value);
                    }
                }
                return error.InvalidEventName;
            };

            const path = try self.allocator.dupe(u8, service[i + 1 ..]);
            errdefer self.allocator.free(path);

            self.subscribe(0, event) catch |err| {
                std.log.err("Failed to subscribe event `{t}` to service: {t}", .{ event, err });
                self.allocator.free(path);
                continue;
            };

            try self.services.append(self.allocator, Service{
                .event = event,
                .path = path,
                .webview = null,
            });
        }

        return self;
    }
    pub fn deinit(self: *Self) void {
        const allocator = self.allocator;

        var it = self.subscriber.valueIterator();
        while (it.next()) |v| v.deinit(allocator);
        self.subscriber.deinit();

        allocator.free(self.groups);

        for (self.services.items) |service| allocator.free(service.path);
        self.services.deinit(allocator);

        allocator.destroy(self);
    }
    pub fn subscribe(
        self: *Self,
        id: u64,
        event: events.Events,
    ) !void {
        blk: {
            for (self.groups) |*group| {
                if (!group.has(event)) continue;
                try group.addOne(event);
                break :blk;
            }
            return error.UnkownEvent;
        }
        const list = try self.subscriber.getOrPut(event);
        if (!list.found_existing) {
            list.value_ptr.* = std.ArrayList(u64){};
        }
        for (list.value_ptr.items) |id_| {
            if (id_ == id) return;
        }
        try list.value_ptr.append(self.allocator, id);
    }
    pub fn unsubscribeAll(self: *Self, id: u64) void {
        var it = self.subscriber.iterator();
        var removed = std.ArrayList(events.Events){};
        defer removed.deinit(self.allocator);
        while (it.next()) |kv| {
            const list = kv.value_ptr;
            for (list.items, 0..) |item, i| {
                if (item == id) {
                    _ = list.swapRemove(i);
                    try removed.append(self.allocator, kv.key_ptr.*);
                    break;
                }
            }
            if (list.items.len == 0) {
                list.deinit();
                _ = self.subscriber.remove(kv.key_ptr.*);
                self.allocator.free(kv.key_ptr.*);
            }
        }
        for (removed.items) |event| {
            for (self.groups) |*group| {
                if (!group.has(event)) continue;
                try group.removeOne(event);
                break;
            }
            unreachable;
        }
    }
    pub fn unsubscribe(
        self: *Self,
        id: u64,
        event: events.Events,
    ) !void {
        const list = self.subscriber.getPtr(event) orelse return error.NotSubscribed;
        blk: {
            for (list.items, 0..) |item, i| {
                if (item != id) continue;
                _ = list.swapRemove(i);
                if (list.items.len == 0) {
                    list.deinit(self.allocator);
                    const key = self.subscriber.getKey(event).?;
                    _ = self.subscriber.remove(key);
                }
                break :blk;
            }
            return error.NotSubscribed;
        }
        for (self.groups) |*group| {
            if (!group.has(event)) continue;
            try group.removeOne(event);
            return;
        }
        unreachable;
    }
    pub fn emit(self: *Self, event: events.Events, data: anytype) void {
        const list = self.subscriber.get(event) orelse return;
        const json = std.json.Stringify.valueAlloc(self.allocator, .{ .event = @intFromEnum(event), .data = data }, .{}) catch unreachable;
        defer self.allocator.free(json);
        for (list.items) |id| {
            if (id == 0) {
                for (self.services.items) |*service| {
                    if (service.event != event) continue;
                    if (service.webview != null) continue;
                    var args = std.Io.Writer.Allocating.init(self.allocator);
                    defer args.deinit();

                    const dataJson = std.json.Stringify.valueAlloc(self.allocator, data, .{}) catch unreachable;
                    defer self.allocator.free(dataJson);
                    var query = std.Uri.Component{ .raw = dataJson };
                    query.formatEscaped(&args.writer) catch unreachable;

                    const path = std.fmt.allocPrint(self.allocator, "{s}?data={s}", .{ service.path, args.written() }) catch unreachable;
                    defer self.allocator.free(path);
                    service.webview = self.app.open(path) catch |err| {
                        std.log.err("Cannot wake up service `{t}:{s}`, failed to open url: {t}", .{ service.event, service.path, err });
                        continue;
                    };
                    std.log.debug("Service `{t}:{s}` woken up", .{ service.event, service.path });

                    const g = @import("gobject");
                    _ = g.signalConnectData(service.webview.?.impl.as(g.Object), "destroy", @ptrCast(&struct {
                        fn cb(_: *g.Object, s: *Service) callconv(.c) void {
                            std.log.debug("Service `{t}:{s}` destroyed", .{ s.event, s.path });
                            s.webview = null;
                        }
                    }.cb), service, null, .flags_default);
                }
            } else {
                const json_ = self.allocator.dupe(u8, json) catch unreachable;
                self.channel.store(.{ .dist = id, .allocator = self.allocator, .data = json_ }) catch unreachable;
            }
        }
    }
};
