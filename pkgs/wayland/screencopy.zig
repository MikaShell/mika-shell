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
    const Contxt = struct {
        allocator: Allocator,
        frame: *ScreencopyFrame,
        writer: std.io.AnyWriter,
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
    fn initContext(self: *Self, frame: *ScreencopyFrame) !*Contxt {
        const ctx = try self.allocator.create(Contxt);
        ctx.allocator = self.allocator;
        ctx.frame = frame;
        ctx.manager = self;
        ctx.yInvert = false;
        ctx.err = null;
        ctx.display = self.display;
        return ctx;
    }
    pub fn capture(self: *Self, writer: std.io.AnyWriter, overlayCursor: bool) !void {
        const frame = try self.screencopyManager.captureOutput(if (overlayCursor) 1 else 0, self.outputs.first.?.data);
        const ctx = try self.initContext(frame);
        ctx.writer = writer;
        frame.setListener(*Contxt, frameListener, ctx);
        _ = self.display.flush();
        // TODO: async wait for frame.ready
        // TODO: handle errors
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
                log.err("screencopy: unsupported format: {s}", .{@tagName(ctx.format)});
                ctx.err = error.UnsupportedFormat;
                return;
            }
            const posix = std.posix;
            const shm = ctx.manager.shm;
            const size = ctx.width * ctx.height * 4;
            const memfd = posix.memfd_create("mika-shell-screencopy", 0) catch |e| {
                log.err("screencopy: memfd_create failed: {s}", .{@errorName(e)});
                ctx.err = e;
                return;
            };
            defer posix.close(memfd);
            posix.ftruncate(memfd, size) catch |e| {
                log.err("screencopy: ftruncate failed: {s}", .{@errorName(e)});
                ctx.err = e;
                return;
            };
            ctx.pixels = posix.mmap(null, size, posix.PROT.READ | posix.PROT.WRITE, .{ .TYPE = .SHARED }, memfd, 0) catch unreachable;
            const shmPool = shm.createPool(memfd, @intCast(size)) catch |e| {
                log.err("screencopy: createPool failed: {s}", .{@errorName(e)});
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
                log.err("screencopy: createBuffer failed: {s}", .{@errorName(e)});
                ctx.err = e;
                return;
            };
            ctx.buffer = shmBuffer;
            f.copy(ctx.buffer);
            _ = ctx.display.flush();
        },
        .ready => |_| {
            defer {
                ctx.buffer.destroy();
                ctx.frame.destroy();
                ctx.allocator.destroy(ctx); // TODO: move to capture function
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
                100.0,
                &output_ptr,
            );
            if (size == 0 or output_ptr == null) {
                unreachable;
            }
            defer c.WebPFree(output_ptr);
            const webp = output_ptr[0..size];
            ctx.writer.writeAll(webp) catch |e| {
                log.err("screencopy: write failed: {s}", .{@errorName(e)});
                ctx.err = e;
                return;
            };
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
test "screencopy" {
    const allocator = std.testing.allocator;
    const manager = try Manager.init(allocator);
    defer manager.deinit();
    const f = try std.fs.cwd().createFile("test.webp", .{});
    defer f.close();
    const writer = f.writer().any();
    try manager.capture(writer, true);
    common.timeoutMainLoop(1000);
}
