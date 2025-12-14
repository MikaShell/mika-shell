const dbus = @import("dbus");
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const PlaybackStatus = enum {
    Playing,
    Paused,
    Stopped,

    pub fn fromString(str: []const u8) ?PlaybackStatus {
        if (std.mem.eql(u8, str, "Playing")) return .Playing;
        if (std.mem.eql(u8, str, "Paused")) return .Paused;
        if (std.mem.eql(u8, str, "Stopped")) return .Stopped;
        return null;
    }

    pub fn toString(self: PlaybackStatus) []const u8 {
        return switch (self) {
            .Playing => "Playing",
            .Paused => "Paused",
            .Stopped => "Stopped",
        };
    }
};

pub const LoopStatus = enum {
    None,
    Track,
    Playlist,

    pub fn fromString(str: []const u8) ?LoopStatus {
        if (std.mem.eql(u8, str, "None")) return .None;
        if (std.mem.eql(u8, str, "Track")) return .Track;
        if (std.mem.eql(u8, str, "Playlist")) return .Playlist;
        return null;
    }

    pub fn toString(self: LoopStatus) []const u8 {
        return switch (self) {
            .None => "None",
            .Track => "Track",
            .Playlist => "Playlist",
        };
    }
};

pub const Metadata = struct {
    trackid: ?[]const u8 = null,
    length: ?i64 = null,
    artUrl: ?[]const u8 = null,
    album: ?[]const u8 = null,
    albumArtist: ?[][]const u8 = null,
    artist: ?[][]const u8 = null,
    asText: ?[]const u8 = null,
    audioBPM: ?i32 = null,
    autoRating: ?f64 = null,
    comment: ?[][]const u8 = null,
    composer: ?[][]const u8 = null,
    contentCreated: ?[]const u8 = null,
    discNumber: ?i32 = null,
    firstUsed: ?[]const u8 = null,
    genre: ?[][]const u8 = null,
    lastUsed: ?[]const u8 = null,
    lyricist: ?[][]const u8 = null,
    title: ?[]const u8 = null,
    trackNumber: ?i32 = null,
    url: ?[]const u8 = null,
    useCount: ?i32 = null,
    userRating: ?f64 = null,

    pub fn deinit(self: Metadata, allocator: Allocator) void {
        if (self.trackid) |v| allocator.free(v);
        if (self.artUrl) |v| allocator.free(v);
        if (self.album) |v| allocator.free(v);
        if (self.albumArtist) |arr| {
            for (arr) |v| allocator.free(v);
            allocator.free(arr);
        }
        if (self.artist) |arr| {
            for (arr) |v| allocator.free(v);
            allocator.free(arr);
        }
        if (self.asText) |v| allocator.free(v);
        if (self.comment) |arr| {
            for (arr) |v| allocator.free(v);
            allocator.free(arr);
        }
        if (self.composer) |arr| {
            for (arr) |v| allocator.free(v);
            allocator.free(arr);
        }
        if (self.contentCreated) |v| allocator.free(v);
        if (self.firstUsed) |v| allocator.free(v);
        if (self.genre) |arr| {
            for (arr) |v| allocator.free(v);
            allocator.free(arr);
        }
        if (self.lastUsed) |v| allocator.free(v);
        if (self.lyricist) |arr| {
            for (arr) |v| allocator.free(v);
            allocator.free(arr);
        }
        if (self.title) |v| allocator.free(v);
        if (self.url) |v| allocator.free(v);
    }
};

pub const PlayerInfo = struct {
    busName: []const u8,
    identity: ?[]const u8 = null,
    desktopEntry: ?[]const u8 = null,
    canQuit: bool = false,
    canRaise: bool = false,
    canSetFullscreen: bool = false,
    hasTrackList: bool = false,
    fullscreen: bool = false,

    pub fn deinit(self: PlayerInfo, allocator: Allocator) void {
        allocator.free(self.busName);
        if (self.identity) |v| allocator.free(v);
        if (self.desktopEntry) |v| allocator.free(v);
    }
};

pub const PlayerStatus = struct {
    canControl: bool = false,
    canGoNext: bool = false,
    canGoPrevious: bool = false,
    canPause: bool = false,
    canPlay: bool = false,
    canSeek: bool = false,
    loopStatus: LoopStatus = .None,
    maximumRate: f64 = 1.0,
    metadata: ?Metadata = null,
    minimumRate: f64 = 1.0,
    playbackStatus: PlaybackStatus = .Stopped,
    position: i64 = 0,
    rate: f64 = 1.0,
    shuffle: bool = false,
    volume: f64 = 1.0,

    pub fn deinit(self: PlayerStatus, allocator: Allocator) void {
        if (self.metadata) |m| m.deinit(allocator);
    }
};

pub const MediaPlayer2 = struct {
    const Self = @This();
    allocator: Allocator,
    bus: *dbus.Bus,
    busName: []const u8,
    player: *dbus.Object,
    playerInterface: *dbus.Object,
    userdata: ?*anyopaque = null,

    pub fn init(allocator: Allocator, bus: *dbus.Bus, busName: []const u8) !Self {
        const name = try allocator.dupe(u8, busName);
        errdefer allocator.free(name);

        const player = try bus.proxy(name, "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2");
        errdefer player.deinit();

        const playerInterface = try bus.proxy(name, "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2.Player");
        errdefer playerInterface.deinit();

        return .{
            .allocator = allocator,
            .bus = bus,
            .busName = name,
            .player = player,
            .playerInterface = playerInterface,
        };
    }

    pub fn deinit(self: Self) void {
        self.player.deinit();
        self.playerInterface.deinit();
        self.allocator.free(self.busName);
    }

    // org.mpris.MediaPlayer2 methods
    pub fn raise(self: Self) !void {
        const result = try self.player.call("Raise", .{}, .{});
        defer result.deinit();
    }

    pub fn quit(self: Self) !void {
        const result = try self.player.call("Quit", .{}, .{});
        defer result.deinit();
    }

    // org.mpris.MediaPlayer2.Player methods
    pub fn next(self: Self) !void {
        const result = try self.playerInterface.call("Next", .{}, .{});
        defer result.deinit();
    }

    pub fn previous(self: Self) !void {
        const result = try self.playerInterface.call("Previous", .{}, .{});
        defer result.deinit();
    }

    pub fn pause(self: Self) !void {
        const result = try self.playerInterface.call("Pause", .{}, .{});
        defer result.deinit();
    }

    pub fn playPause(self: Self) !void {
        const result = try self.playerInterface.call("PlayPause", .{}, .{});
        defer result.deinit();
    }

    pub fn stop(self: Self) !void {
        const result = try self.playerInterface.call("Stop", .{}, .{});
        defer result.deinit();
    }

    pub fn play(self: Self) !void {
        const result = try self.playerInterface.call("Play", .{}, .{});
        defer result.deinit();
    }

    pub fn seek(self: Self, offset: i64) !void {
        const result = try self.playerInterface.call("Seek", .{dbus.Int64}, .{offset});
        defer result.deinit();
    }

    pub fn setPosition(self: Self, trackId: []const u8, position: i64) !void {
        const result = try self.playerInterface.call("SetPosition", .{ dbus.ObjectPath, dbus.Int64 }, .{ trackId, position });
        defer result.deinit();
    }

    pub fn openUri(self: Self, uri: []const u8) !void {
        const result = try self.playerInterface.call("OpenUri", .{dbus.String}, .{uri});
        defer result.deinit();
    }

    // Property getters for org.mpris.MediaPlayer2
    pub fn getIdentity(self: Self, allocator: Allocator) ![]const u8 {
        return try self.player.getAlloc(allocator, "Identity", dbus.String);
    }

    pub fn getDesktopEntry(self: Self, allocator: Allocator) ![]const u8 {
        return try self.player.getAlloc(allocator, "DesktopEntry", dbus.String);
    }

    pub fn canQuit(self: Self) !bool {
        return try self.player.getBasic("CanQuit", dbus.Boolean);
    }

    pub fn canRaise(self: Self) !bool {
        return try self.player.getBasic("CanRaise", dbus.Boolean);
    }

    pub fn canSetFullscreen(self: Self) !bool {
        return try self.player.getBasic("CanSetFullscreen", dbus.Boolean);
    }

    pub fn hasTrackList(self: Self) !bool {
        return try self.player.getBasic("HasTrackList", dbus.Boolean);
    }

    pub fn getFullscreen(self: Self) !bool {
        return try self.player.getBasic("Fullscreen", dbus.Boolean);
    }

    pub fn setFullscreen(self: Self, fullscreen: bool) !void {
        try self.player.set("Fullscreen", dbus.Boolean, fullscreen);
    }

    // Property getters for org.mpris.MediaPlayer2.Player
    pub fn getPlaybackStatus(self: Self, allocator: Allocator) !PlaybackStatus {
        const str = try self.playerInterface.getAlloc(allocator, "PlaybackStatus", dbus.String);
        defer allocator.free(str);
        return PlaybackStatus.fromString(str) orelse .Stopped;
    }

    pub fn getLoopStatus(self: Self, allocator: Allocator) !LoopStatus {
        const str = try self.playerInterface.getAlloc(allocator, "LoopStatus", dbus.String);
        defer allocator.free(str);
        return LoopStatus.fromString(str) orelse .None;
    }

    pub fn setLoopStatus(self: Self, status: LoopStatus) !void {
        try self.playerInterface.set("LoopStatus", dbus.String, status.toString());
    }

    pub fn getRate(self: Self) !f64 {
        return try self.playerInterface.getBasic("Rate", dbus.Double);
    }

    pub fn setRate(self: Self, rate: f64) !void {
        try self.playerInterface.set("Rate", dbus.Double, rate);
    }

    pub fn getShuffle(self: Self) !bool {
        return try self.playerInterface.getBasic("Shuffle", dbus.Boolean);
    }

    pub fn setShuffle(self: Self, shuffle: bool) !void {
        try self.playerInterface.set("Shuffle", dbus.Boolean, shuffle);
    }

    pub fn getVolume(self: Self) !f64 {
        return try self.playerInterface.getBasic("Volume", dbus.Double);
    }

    pub fn setVolume(self: Self, volume: f64) !void {
        try self.playerInterface.set("Volume", dbus.Double, volume);
    }

    pub fn getPosition(self: Self) !i64 {
        return try self.playerInterface.getBasic("Position", dbus.Int64);
    }

    pub fn getMinimumRate(self: Self) !f64 {
        return try self.playerInterface.getBasic("MinimumRate", dbus.Double);
    }

    pub fn getMaximumRate(self: Self) !f64 {
        return try self.playerInterface.getBasic("MaximumRate", dbus.Double);
    }

    pub fn canGoNext(self: Self) !bool {
        return try self.playerInterface.getBasic("CanGoNext", dbus.Boolean);
    }

    pub fn canGoPrevious(self: Self) !bool {
        return try self.playerInterface.getBasic("CanGoPrevious", dbus.Boolean);
    }

    pub fn canPlay(self: Self) !bool {
        return try self.playerInterface.getBasic("CanPlay", dbus.Boolean);
    }

    pub fn canPause(self: Self) !bool {
        return try self.playerInterface.getBasic("CanPause", dbus.Boolean);
    }

    pub fn canSeek(self: Self) !bool {
        return try self.playerInterface.getBasic("CanSeek", dbus.Boolean);
    }

    pub fn canControl(self: Self) !bool {
        return try self.playerInterface.getBasic("CanControl", dbus.Boolean);
    }

    pub fn getMetadata(self: Self, allocator: Allocator) !Metadata {
        const result = try self.playerInterface.get("Metadata", dbus.Vardict);
        defer result.deinit();

        var metadata = Metadata{};
        errdefer metadata.deinit(allocator);

        for (result.value) |entry| {
            const key = entry.key;
            const value = entry.value;

            if (std.mem.eql(u8, key, "mpris:trackid")) {
                if (value.tag == dbus.String.tag) {
                    metadata.trackid = try allocator.dupe(u8, value.as(dbus.String));
                }
            } else if (std.mem.eql(u8, key, "mpris:length")) {
                if (value.tag == dbus.Int64.tag) {
                    metadata.length = value.as(dbus.Int64);
                }
            } else if (std.mem.eql(u8, key, "mpris:artUrl")) {
                if (value.tag == dbus.String.tag) {
                    metadata.artUrl = try allocator.dupe(u8, value.as(dbus.String));
                }
            } else if (std.mem.eql(u8, key, "xesam:album")) {
                if (value.tag == dbus.String.tag) {
                    metadata.album = try allocator.dupe(u8, value.as(dbus.String));
                }
            } else if (std.mem.eql(u8, key, "xesam:albumArtist")) {
                // Handle array of strings
                if (value.tag == dbus.Array(dbus.String).tag) {
                    const artists = value.as(dbus.Array(dbus.String));
                    if (artists.len > 0) {
                        var duped = try allocator.alloc([]const u8, artists.len);
                        errdefer allocator.free(duped);
                        for (artists, 0..) |artist, i| {
                            duped[i] = try allocator.dupe(u8, artist);
                        }
                        metadata.albumArtist = duped;
                    }
                }
            } else if (std.mem.eql(u8, key, "xesam:artist")) {
                // Handle array of strings
                if (value.tag == dbus.Array(dbus.String).tag) {
                    const artists = value.as(dbus.Array(dbus.String));
                    if (artists.len > 0) {
                        var duped = try allocator.alloc([]const u8, artists.len);
                        errdefer allocator.free(duped);
                        for (artists, 0..) |artist, i| {
                            duped[i] = try allocator.dupe(u8, artist);
                        }
                        metadata.artist = duped;
                    }
                }
            } else if (std.mem.eql(u8, key, "xesam:asText")) {
                if (value.tag == dbus.String.tag) {
                    metadata.asText = try allocator.dupe(u8, value.as(dbus.String));
                }
            } else if (std.mem.eql(u8, key, "xesam:audioBPM")) {
                if (value.tag == dbus.Int32.tag) {
                    metadata.audioBPM = value.as(dbus.Int32);
                }
            } else if (std.mem.eql(u8, key, "xesam:autoRating")) {
                if (value.tag == dbus.Double.tag) {
                    metadata.autoRating = value.as(dbus.Double);
                }
            } else if (std.mem.eql(u8, key, "xesam:comment")) {
                if (value.tag == dbus.Array(dbus.String).tag) {
                    const comments = value.as(dbus.Array(dbus.String));
                    if (comments.len > 0) {
                        var duped = try allocator.alloc([]const u8, comments.len);
                        errdefer allocator.free(duped);
                        for (comments, 0..) |comment, i| {
                            duped[i] = try allocator.dupe(u8, comment);
                        }
                        metadata.comment = duped;
                    }
                }
            } else if (std.mem.eql(u8, key, "xesam:composer")) {
                if (value.tag == dbus.Array(dbus.String).tag) {
                    const composers = value.as(dbus.Array(dbus.String));
                    if (composers.len > 0) {
                        var duped = try allocator.alloc([]const u8, composers.len);
                        errdefer allocator.free(duped);
                        for (composers, 0..) |composer, i| {
                            duped[i] = try allocator.dupe(u8, composer);
                        }
                        metadata.composer = duped;
                    }
                }
            } else if (std.mem.eql(u8, key, "xesam:contentCreated")) {
                if (value.tag == dbus.String.tag) {
                    metadata.contentCreated = try allocator.dupe(u8, value.as(dbus.String));
                }
            } else if (std.mem.eql(u8, key, "xesam:discNumber")) {
                if (value.tag == dbus.Int32.tag) {
                    metadata.discNumber = value.as(dbus.Int32);
                }
            } else if (std.mem.eql(u8, key, "xesam:firstUsed")) {
                if (value.tag == dbus.String.tag) {
                    metadata.firstUsed = try allocator.dupe(u8, value.as(dbus.String));
                }
            } else if (std.mem.eql(u8, key, "xesam:genre")) {
                if (value.tag == dbus.Array(dbus.String).tag) {
                    const genres = value.as(dbus.Array(dbus.String));
                    if (genres.len > 0) {
                        var duped = try allocator.alloc([]const u8, genres.len);
                        errdefer allocator.free(duped);
                        for (genres, 0..) |genre, i| {
                            duped[i] = try allocator.dupe(u8, genre);
                        }
                        metadata.genre = duped;
                    }
                }
            } else if (std.mem.eql(u8, key, "xesam:lastUsed")) {
                if (value.tag == dbus.String.tag) {
                    metadata.lastUsed = try allocator.dupe(u8, value.as(dbus.String));
                }
            } else if (std.mem.eql(u8, key, "xesam:lyricist")) {
                if (value.tag == dbus.Array(dbus.String).tag) {
                    const lyricists = value.as(dbus.Array(dbus.String));
                    if (lyricists.len > 0) {
                        var duped = try allocator.alloc([]const u8, lyricists.len);
                        errdefer allocator.free(duped);
                        for (lyricists, 0..) |lyricist, i| {
                            duped[i] = try allocator.dupe(u8, lyricist);
                        }
                        metadata.lyricist = duped;
                    }
                }
            } else if (std.mem.eql(u8, key, "xesam:title")) {
                if (value.tag == dbus.String.tag) {
                    metadata.title = try allocator.dupe(u8, value.as(dbus.String));
                }
            } else if (std.mem.eql(u8, key, "xesam:trackNumber")) {
                if (value.tag == dbus.Int32.tag) {
                    metadata.trackNumber = value.as(dbus.Int32);
                }
            } else if (std.mem.eql(u8, key, "xesam:url")) {
                if (value.tag == dbus.String.tag) {
                    metadata.url = try allocator.dupe(u8, value.as(dbus.String));
                }
            } else if (std.mem.eql(u8, key, "xesam:useCount")) {
                if (value.tag == dbus.Int32.tag) {
                    metadata.useCount = value.as(dbus.Int32);
                }
            } else if (std.mem.eql(u8, key, "xesam:userRating")) {
                if (value.tag == dbus.Double.tag) {
                    metadata.userRating = value.as(dbus.Double);
                }
            }
        }

        return metadata;
    }

    pub fn getPlayerInfo(self: Self, allocator: Allocator) !PlayerInfo {
        var info = PlayerInfo{
            .busName = try allocator.dupe(u8, self.busName),
        };
        errdefer info.deinit(allocator);

        info.identity = self.getIdentity(allocator) catch null;
        info.desktopEntry = self.getDesktopEntry(allocator) catch null;
        info.canQuit = self.canQuit() catch false;
        info.canRaise = self.canRaise() catch false;
        info.canSetFullscreen = self.canSetFullscreen() catch false;
        info.hasTrackList = self.hasTrackList() catch false;
        info.fullscreen = self.getFullscreen() catch false;

        return info;
    }

    pub fn getPlayerStatus(self: Self, allocator: Allocator) !PlayerStatus {
        var status = PlayerStatus{};
        errdefer status.deinit(allocator);

        status.playbackStatus = self.getPlaybackStatus(allocator) catch .Stopped;
        status.loopStatus = self.getLoopStatus(allocator) catch .None;
        status.rate = self.getRate() catch 1.0;
        status.shuffle = self.getShuffle() catch false;
        status.volume = self.getVolume() catch 1.0;
        status.position = self.getPosition() catch 0;
        status.minimumRate = self.getMinimumRate() catch 1.0;
        status.maximumRate = self.getMaximumRate() catch 1.0;
        status.canGoNext = self.canGoNext() catch false;
        status.canGoPrevious = self.canGoPrevious() catch false;
        status.canPlay = self.canPlay() catch false;
        status.canPause = self.canPause() catch false;
        status.canSeek = self.canSeek() catch false;
        status.canControl = self.canControl() catch false;
        status.metadata = self.getMetadata(allocator) catch null;

        return status;
    }
};

pub fn listPlayers(allocator: Allocator, bus: *dbus.Bus) ![][]const u8 {
    const dbusDaemon = try bus.proxy("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus");
    defer dbusDaemon.deinit();

    const result = try dbusDaemon.call("ListNames", .{}, .{});
    defer result.deinit();

    var players = std.ArrayList([]const u8){};
    defer players.deinit(allocator);

    for (result.next(dbus.Array(dbus.String))) |name| {
        if (std.mem.startsWith(u8, name, "org.mpris.MediaPlayer2.")) {
            try players.append(allocator, try allocator.dupe(u8, name));
        }
    }

    return try players.toOwnedSlice(allocator);
}
