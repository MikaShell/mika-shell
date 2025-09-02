const std = @import("std");
const Allocator = std.mem.Allocator;
const wayland = @import("zig-wayland");
const wl = wayland.client.wl;
const ScreencopyManager = wayland.client.zwlr.ScreencopyManagerV1;
const ScreencopyFrame = wayland.client.zwlr.ScreencopyFrameV1;
const common = @import("common.zig");
pub const Manager = struct {
    const Self = @This();
    allocator: Allocator,
    screencopyManager: *ScreencopyManager,
    shm: *wl.Shm,
    outputs: std.DoublyLinkedList(*wl.Output),
    display: *wl.Display,
    glibWatch: common.GLibWatch,
    // if err is null, result is valid
    pub const Callback = *const fn (err: ?anyerror, result: ?[]u8, data: ?*anyopaque) void;
    const Contxt = struct {
        allocator: Allocator,
        frame: *ScreencopyFrame,
        manager: *Self,
        pixels: []u8,
        buffer: *wl.Buffer,
        display: *wl.Display,
        width: u32,
        height: u32,
        stride: u32,
        format: wl.Shm.Format,
        yInvert: bool,
        err: ?anyerror,
        callback: Callback,
        userdata: ?*anyopaque,
        quality: f32,
    };
    pub const Option = struct {
        output: u32,
        x: i32,
        y: i32,
        w: i32,
        h: i32,
        quality: f32,
        overlayCursor: bool,
    };
    pub fn init(allocator: Allocator) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.allocator = allocator;
        self.outputs = .{};

        const display = try common.init(*Self, registryListener, self);
        errdefer display.disconnect();
        self.display = display;

        self.glibWatch = try common.withGLibMainLoop(display);
        return self;
    }
    pub fn deinit(self: *Self) void {
        self.glibWatch.deinit();
        while (self.outputs.pop()) |node| {
            self.allocator.destroy(node);
        }
        self.allocator.destroy(self);
    }
    fn initContext(self: *Self, frame: *ScreencopyFrame, quality: f32, callback: Callback, userdata: ?*anyopaque) !*Contxt {
        const ctx = try self.allocator.create(Contxt);
        ctx.allocator = self.allocator;
        ctx.frame = frame;
        ctx.manager = self;
        ctx.yInvert = false;
        ctx.err = null;
        ctx.display = self.display;
        ctx.callback = callback;
        ctx.userdata = userdata;
        ctx.quality = quality;
        return ctx;
    }
    pub fn capture(self: *Self, callback: Callback, data: ?*anyopaque, option: Option) !void {
        const overlayCursor: i32 = if (option.overlayCursor) 1 else 0;
        const output = blk: {
            var node = self.outputs.first;
            var num: usize = 0;
            while (node) |n| : (node = n.next) {
                if (num == option.output) break :blk n.data;
                num += 1;
            }
            return error.InvalidOutput;
        };
        const frame = blk: {
            if (option.x == 0 and option.y == 0 and option.w == 0 and option.h == 0) {
                break :blk try self.screencopyManager.captureOutput(overlayCursor, output);
            } else {
                break :blk try self.screencopyManager.captureOutputRegion(overlayCursor, output, option.x, option.y, option.w, option.h);
            }
        };
        const ctx = try self.initContext(frame, option.quality, callback, data);
        frame.setListener(*Contxt, frameListener, ctx);
        _ = self.display.flush();
    }
    fn addOutput(self: *Self, output: *wl.Output) void {
        const node = self.allocator.create(std.DoublyLinkedList(*wl.Output).Node) catch unreachable;
        node.* = .{
            .data = output,
            .prev = null,
            .next = null,
        };
        self.outputs.append(node);
    }
};
const c = @cImport({
    @cInclude("webp/encode.h");
});

fn frameListener(f: *ScreencopyFrame, event: ScreencopyFrame.Event, ctx: *Manager.Contxt) void {
    const log = std.log.scoped(.wayland);
    switch (event) {
        .buffer => |buffer| {
            ctx.width = buffer.width;
            ctx.height = buffer.height;
            ctx.stride = buffer.stride;
            ctx.format = buffer.format;
        },
        .buffer_done => {
            if (!(ctx.format == .xrgb8888 or ctx.format == .argb8888)) {
                log.err("Screencopy: unsupported format: {s}", .{@tagName(ctx.format)});
                ctx.err = error.UnsupportedFormat;
                return;
            }
            const posix = std.posix;
            const shm = ctx.manager.shm;
            const size = ctx.width * ctx.height * 4;
            const memfd = posix.memfd_create("mika-shell-screencopy", 0) catch |e| {
                log.err("Screencopy: memfd_create failed: {s}", .{@errorName(e)});
                ctx.err = e;
                return;
            };
            defer posix.close(memfd);
            posix.ftruncate(memfd, size) catch |e| {
                log.err("Screencopy: ftruncate failed: {s}", .{@errorName(e)});
                ctx.err = e;
                return;
            };
            ctx.pixels = posix.mmap(null, size, posix.PROT.READ | posix.PROT.WRITE, .{ .TYPE = .SHARED }, memfd, 0) catch unreachable;
            const shmPool = shm.createPool(memfd, @intCast(size)) catch |e| {
                log.err("Screencopy: createPool failed: {s}", .{@errorName(e)});
                ctx.err = e;
                return;
            };
            defer shmPool.destroy();
            const shmBuffer = shmPool.createBuffer(
                0,
                @intCast(ctx.width),
                @intCast(ctx.height),
                @intCast(ctx.stride),
                ctx.format,
            ) catch |e| {
                log.err("Screencopy: createBuffer failed: {s}", .{@errorName(e)});
                ctx.err = e;
                return;
            };
            ctx.buffer = shmBuffer;
            f.copy(ctx.buffer);
            _ = ctx.display.flush();
        },
        .ready => |_| {
            var webp: ?[]u8 = null;
            defer {
                ctx.buffer.destroy();
                ctx.frame.destroy();
                ctx.allocator.destroy(ctx);
            }
            if (ctx.err != null) return;
            var output_ptr: [*c]u8 = undefined;
            // The buffer sent by the compositor is in little-endian order, but the actual memory order of argb/xrgb is bgra.
            const bgra = ctx.pixels;
            const size = c.WebPEncodeBGRA(
                bgra.ptr,
                @intCast(ctx.width),
                @intCast(ctx.height),
                @intCast(ctx.stride),
                ctx.quality,
                &output_ptr,
            );
            if (size == 0 or output_ptr == null) {
                unreachable;
            }
            defer c.WebPFree(output_ptr);
            webp = output_ptr[0..size];
            ctx.callback(ctx.err, webp, ctx.userdata);
        },
        .flags => |flags| {
            ctx.yInvert = flags.flags.y_invert;
            if (ctx.yInvert) {
                log.err("screencopy: y_invert==true is not supported", .{});
                ctx.err = error.YInvertFalseNotSupported;
                return;
            }
        },
        else => {},
    }
}
fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, ctx: *Manager) void {
    const mem = std.mem;
    switch (event) {
        .global => |global| {
            if (mem.orderZ(u8, global.interface, ScreencopyManager.interface.name) == .eq) {
                ctx.screencopyManager = registry.bind(global.name, ScreencopyManager, 3) catch return;
            } else if (mem.orderZ(u8, global.interface, wl.Output.interface.name) == .eq) {
                const output = registry.bind(global.name, wl.Output, 3) catch return;
                ctx.addOutput(output);
            } else if (mem.orderZ(u8, global.interface, wl.Shm.interface.name) == .eq) {
                ctx.shm = registry.bind(global.name, wl.Shm, 1) catch return;
            }
        },
        .global_remove => @panic("global_remove not implemented"),
    }
}
