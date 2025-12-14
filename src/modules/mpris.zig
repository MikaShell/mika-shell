const App = @import("../app.zig").App;
const std = @import("std");
const modules = @import("root.zig");
const Args = modules.Args;
const InitContext = modules.InitContext;
const Context = modules.Context;
const Registry = modules.Registry;
const Allocator = std.mem.Allocator;
const mprisLib = @import("../lib/mpris.zig");
const dbus = @import("dbus");

pub const Mpris = struct {
    const Self = @This();
    allocator: Allocator,
    bus: *dbus.Bus,

    pub fn init(ctx: InitContext) !*Self {
        const self = try ctx.allocator.create(Self);
        self.allocator = ctx.allocator;
        self.bus = ctx.sessionBus;
        return self;
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.destroy(self);
    }

    pub fn register() Registry(Self) {
        return .{
            .exports = &.{
                .{ "listPlayers", listPlayers },
                .{ "raise", raise },
                .{ "quit", quit },
                .{ "next", next },
                .{ "previous", previous },
                .{ "pause", pause },
                .{ "playPause", playPause },
                .{ "stop", stop },
                .{ "play", play },
                .{ "seek", seek },
                .{ "setPosition", setPosition },
                .{ "openUri", openUri },
                .{ "getIdentity", getIdentity },
                .{ "getDesktopEntry", getDesktopEntry },
                .{ "canQuit", canQuit },
                .{ "canRaise", canRaise },
                .{ "canSetFullscreen", canSetFullscreen },
                .{ "hasTrackList", hasTrackList },
                .{ "getFullscreen", getFullscreen },
                .{ "setFullscreen", setFullscreen },
                .{ "getPlaybackStatus", getPlaybackStatus },
                .{ "getLoopStatus", getLoopStatus },
                .{ "setLoopStatus", setLoopStatus },
                .{ "getRate", getRate },
                .{ "setRate", setRate },
                .{ "getShuffle", getShuffle },
                .{ "setShuffle", setShuffle },
                .{ "getVolume", getVolume },
                .{ "setVolume", setVolume },
                .{ "getPosition", getPosition },
                .{ "getMinimumRate", getMinimumRate },
                .{ "getMaximumRate", getMaximumRate },
                .{ "canGoNext", canGoNext },
                .{ "canGoPrevious", canGoPrevious },
                .{ "canPlay", canPlay },
                .{ "canPause", canPause },
                .{ "canSeek", canSeek },
                .{ "canControl", canControl },
                .{ "getMetadata", getMetadata },
                .{ "getPlayerInfo", getPlayerInfo },
                .{ "getPlayerStatus", getPlayerStatus },
            },
        };
    }

    pub fn listPlayers(self: *Self, ctx: *Context) !void {
        const players = try mprisLib.listPlayers(self.allocator, self.bus);
        defer {
            for (players) |p| self.allocator.free(p);
            self.allocator.free(players);
        }
        ctx.commit(players);
    }

    fn getPlayer(self: *Self, ctx: *Context) !mprisLib.MediaPlayer2 {
        const busName = try ctx.args.string(0);
        return try mprisLib.MediaPlayer2.init(self.allocator, self.bus, busName);
    }

    pub fn raise(self: *Self, ctx: *Context) !void {
        const player = try self.getPlayer(ctx);
        defer player.deinit();
        try player.raise();
    }

    pub fn quit(self: *Self, ctx: *Context) !void {
        const player = try self.getPlayer(ctx);
        defer player.deinit();
        try player.quit();
    }

    pub fn next(self: *Self, ctx: *Context) !void {
        const player = try self.getPlayer(ctx);
        defer player.deinit();
        try player.next();
    }

    pub fn previous(self: *Self, ctx: *Context) !void {
        const player = try self.getPlayer(ctx);
        defer player.deinit();
        try player.previous();
    }

    pub fn pause(self: *Self, ctx: *Context) !void {
        const player = try self.getPlayer(ctx);
        defer player.deinit();
        try player.pause();
    }

    pub fn playPause(self: *Self, ctx: *Context) !void {
        const player = try self.getPlayer(ctx);
        defer player.deinit();
        try player.playPause();
    }

    pub fn stop(self: *Self, ctx: *Context) !void {
        const player = try self.getPlayer(ctx);
        defer player.deinit();
        try player.stop();
    }

    pub fn play(self: *Self, ctx: *Context) !void {
        const player = try self.getPlayer(ctx);
        defer player.deinit();
        try player.play();
    }

    pub fn seek(self: *Self, ctx: *Context) !void {
        const busName = try ctx.args.string(0);
        const offset = try ctx.args.integer(1);
        const player = try mprisLib.MediaPlayer2.init(self.allocator, self.bus, busName);
        defer player.deinit();
        try player.seek(offset);
    }

    pub fn setPosition(self: *Self, ctx: *Context) !void {
        const busName = try ctx.args.string(0);
        const trackId = try ctx.args.string(1);
        const position = try ctx.args.integer(2);
        const player = try mprisLib.MediaPlayer2.init(self.allocator, self.bus, busName);
        defer player.deinit();
        try player.setPosition(trackId, position);
    }

    pub fn openUri(self: *Self, ctx: *Context) !void {
        const busName = try ctx.args.string(0);
        const uri = try ctx.args.string(1);
        const player = try mprisLib.MediaPlayer2.init(self.allocator, self.bus, busName);
        defer player.deinit();
        try player.openUri(uri);
    }

    pub fn getIdentity(self: *Self, ctx: *Context) !void {
        const player = try self.getPlayer(ctx);
        defer player.deinit();
        const identity = try player.getIdentity(self.allocator);
        defer self.allocator.free(identity);
        ctx.commit(identity);
    }

    pub fn getDesktopEntry(self: *Self, ctx: *Context) !void {
        const player = try self.getPlayer(ctx);
        defer player.deinit();
        const entry = try player.getDesktopEntry(self.allocator);
        defer self.allocator.free(entry);
        ctx.commit(entry);
    }

    pub fn canQuit(self: *Self, ctx: *Context) !void {
        const player = try self.getPlayer(ctx);
        defer player.deinit();
        const result = try player.canQuit();
        ctx.commit(result);
    }

    pub fn canRaise(self: *Self, ctx: *Context) !void {
        const player = try self.getPlayer(ctx);
        defer player.deinit();
        const result = try player.canRaise();
        ctx.commit(result);
    }

    pub fn canSetFullscreen(self: *Self, ctx: *Context) !void {
        const player = try self.getPlayer(ctx);
        defer player.deinit();
        const result = try player.canSetFullscreen();
        ctx.commit(result);
    }

    pub fn hasTrackList(self: *Self, ctx: *Context) !void {
        const player = try self.getPlayer(ctx);
        defer player.deinit();
        const result = try player.hasTrackList();
        ctx.commit(result);
    }

    pub fn getFullscreen(self: *Self, ctx: *Context) !void {
        const player = try self.getPlayer(ctx);
        defer player.deinit();
        const result = try player.getFullscreen();
        ctx.commit(result);
    }

    pub fn setFullscreen(self: *Self, ctx: *Context) !void {
        const busName = try ctx.args.string(0);
        const fullscreen = try ctx.args.bool(1);
        const player = try mprisLib.MediaPlayer2.init(self.allocator, self.bus, busName);
        defer player.deinit();
        try player.setFullscreen(fullscreen);
    }

    pub fn getPlaybackStatus(self: *Self, ctx: *Context) !void {
        const player = try self.getPlayer(ctx);
        defer player.deinit();
        const status = try player.getPlaybackStatus(self.allocator);
        ctx.commit(status.toString());
    }

    pub fn getLoopStatus(self: *Self, ctx: *Context) !void {
        const player = try self.getPlayer(ctx);
        defer player.deinit();
        const status = try player.getLoopStatus(self.allocator);
        ctx.commit(status.toString());
    }

    pub fn setLoopStatus(self: *Self, ctx: *Context) !void {
        const busName = try ctx.args.string(0);
        const statusStr = try ctx.args.string(1);
        const player = try mprisLib.MediaPlayer2.init(self.allocator, self.bus, busName);
        defer player.deinit();
        const status = mprisLib.LoopStatus.fromString(statusStr) orelse return error.InvalidLoopStatus;
        try player.setLoopStatus(status);
    }

    pub fn getRate(self: *Self, ctx: *Context) !void {
        const player = try self.getPlayer(ctx);
        defer player.deinit();
        const rate = try player.getRate();
        ctx.commit(rate);
    }

    pub fn setRate(self: *Self, ctx: *Context) !void {
        const busName = try ctx.args.string(0);
        const rate = try ctx.args.float(1);
        const player = try mprisLib.MediaPlayer2.init(self.allocator, self.bus, busName);
        defer player.deinit();
        try player.setRate(rate);
    }

    pub fn getShuffle(self: *Self, ctx: *Context) !void {
        const player = try self.getPlayer(ctx);
        defer player.deinit();
        const shuffle = try player.getShuffle();
        ctx.commit(shuffle);
    }

    pub fn setShuffle(self: *Self, ctx: *Context) !void {
        const busName = try ctx.args.string(0);
        const shuffle = try ctx.args.bool(1);
        const player = try mprisLib.MediaPlayer2.init(self.allocator, self.bus, busName);
        defer player.deinit();
        try player.setShuffle(shuffle);
    }

    pub fn getVolume(self: *Self, ctx: *Context) !void {
        const player = try self.getPlayer(ctx);
        defer player.deinit();
        const volume = try player.getVolume();
        ctx.commit(volume);
    }

    pub fn setVolume(self: *Self, ctx: *Context) !void {
        const busName = try ctx.args.string(0);
        const volume = try ctx.args.float(1);
        const player = try mprisLib.MediaPlayer2.init(self.allocator, self.bus, busName);
        defer player.deinit();
        try player.setVolume(volume);
    }

    pub fn getPosition(self: *Self, ctx: *Context) !void {
        const player = try self.getPlayer(ctx);
        defer player.deinit();
        const position = try player.getPosition();
        ctx.commit(position);
    }

    pub fn getMinimumRate(self: *Self, ctx: *Context) !void {
        const player = try self.getPlayer(ctx);
        defer player.deinit();
        const rate = try player.getMinimumRate();
        ctx.commit(rate);
    }

    pub fn getMaximumRate(self: *Self, ctx: *Context) !void {
        const player = try self.getPlayer(ctx);
        defer player.deinit();
        const rate = try player.getMaximumRate();
        ctx.commit(rate);
    }

    pub fn canGoNext(self: *Self, ctx: *Context) !void {
        const player = try self.getPlayer(ctx);
        defer player.deinit();
        const result = try player.canGoNext();
        ctx.commit(result);
    }

    pub fn canGoPrevious(self: *Self, ctx: *Context) !void {
        const player = try self.getPlayer(ctx);
        defer player.deinit();
        const result = try player.canGoPrevious();
        ctx.commit(result);
    }

    pub fn canPlay(self: *Self, ctx: *Context) !void {
        const player = try self.getPlayer(ctx);
        defer player.deinit();
        const result = try player.canPlay();
        ctx.commit(result);
    }

    pub fn canPause(self: *Self, ctx: *Context) !void {
        const player = try self.getPlayer(ctx);
        defer player.deinit();
        const result = try player.canPause();
        ctx.commit(result);
    }

    pub fn canSeek(self: *Self, ctx: *Context) !void {
        const player = try self.getPlayer(ctx);
        defer player.deinit();
        const result = try player.canSeek();
        ctx.commit(result);
    }

    pub fn canControl(self: *Self, ctx: *Context) !void {
        const player = try self.getPlayer(ctx);
        defer player.deinit();
        const result = try player.canControl();
        ctx.commit(result);
    }

    pub fn getMetadata(self: *Self, ctx: *Context) !void {
        const player = try self.getPlayer(ctx);
        defer player.deinit();
        const metadata = try player.getMetadata(self.allocator);
        defer metadata.deinit(self.allocator);
        ctx.commit(metadata);
    }

    pub fn getPlayerInfo(self: *Self, ctx: *Context) !void {
        const player = try self.getPlayer(ctx);
        defer player.deinit();
        const info = try player.getPlayerInfo(self.allocator);
        defer info.deinit(self.allocator);
        ctx.commit(info);
    }

    pub fn getPlayerStatus(self: *Self, ctx: *Context) !void {
        const player = try self.getPlayer(ctx);
        defer player.deinit();
        const status = try player.getPlayerStatus(self.allocator);
        defer status.deinit(self.allocator);
        ctx.commit(status);
    }
};
