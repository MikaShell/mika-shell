const std = @import("std");
const Allocator = std.mem.Allocator;
const wayland = @import("zig-wayland");
const wl = wayland.client.wl;
const ScreencopyManager = wayland.client.zwlr.ScreencopyManagerV1;
const ScreencopyFrame = wayland.client.zwlr.ScreencopyFrameV1;
const common = @import("common.zig");
const OutputNode = struct {
    data: *wl.Output,
    node: std.DoublyLinkedList.Node,
};
pub const Manager = struct {
    const Self = @This();
    allocator: Allocator,
    screencopyManager: *ScreencopyManager,
    shm: *wl.Shm,
    outputs: std.DoublyLinkedList,
    display: *wl.Display,
    glibWatch: common.GLibWatch,
    // if err is null, result is valid
    pub const Callback = *const fn (err: ?anyerror, result: ?[]u8, data: ?*anyopaque) void;
    pub const Encode = enum {
        webp,
        png,
    };
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
        option: Option,
    };
    pub const Option = struct {
        output: u32,
        x: i32,
        y: i32,
        w: i32,
        h: i32,
        webpQuality: f32,
        pngCompression: u32,
        overlayCursor: bool,
        encode: Encode,
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
            const output: *OutputNode = @fieldParentPtr("node", node);
            self.allocator.destroy(output);
        }
        self.display.disconnect();
        self.allocator.destroy(self);
    }
    fn initContext(self: *Self, frame: *ScreencopyFrame, opt: Option, callback: Callback, userdata: ?*anyopaque) !*Contxt {
        const ctx = try self.allocator.create(Contxt);
        ctx.allocator = self.allocator;
        ctx.frame = frame;
        ctx.manager = self;
        ctx.yInvert = false;
        ctx.err = null;
        ctx.display = self.display;
        ctx.callback = callback;
        ctx.userdata = userdata;
        ctx.option = opt;
        return ctx;
    }
    pub fn capture(self: *Self, callback: Callback, data: ?*anyopaque, option: Option) !void {
        const overlayCursor: i32 = if (option.overlayCursor) 1 else 0;
        const outputNode: *OutputNode = blk: {
            var node = self.outputs.first;
            var num: usize = 0;
            while (node) |n| : (node = n.next) {
                if (num == option.output) break :blk @fieldParentPtr("node", n);
                num += 1;
            }
            return error.InvalidOutput;
        };
        const frame = blk: {
            if (option.x == 0 and option.y == 0 and option.w == 0 and option.h == 0) {
                break :blk try self.screencopyManager.captureOutput(overlayCursor, outputNode.data);
            } else {
                break :blk try self.screencopyManager.captureOutputRegion(overlayCursor, outputNode.data, option.x, option.y, option.w, option.h);
            }
        };
        const ctx = try self.initContext(frame, option, callback, data);
        frame.setListener(*Contxt, frameListener, ctx);
        _ = self.display.flush();
    }
    fn addOutput(self: *Self, output: *wl.Output) void {
        const node = self.allocator.create(OutputNode) catch unreachable;
        node.* = .{
            .data = output,
            .node = .{},
        };
        self.outputs.append(&node.node);
    }
};
const c = @cImport({
    @cInclude("webp/encode.h");
    @cInclude("png.h");
});
const glib = @import("glib");
const gio = @import("gio");
const gobject = @import("gobject");
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
                log.err("Screencopy: unsupported format: {t}", .{ctx.format});
                ctx.err = error.UnsupportedFormat;
                return;
            }
            const posix = std.posix;
            const shm = ctx.manager.shm;
            const size = ctx.width * ctx.height * 4;
            const memfd = posix.memfd_create("mika-shell-screencopy", 0) catch |e| {
                log.err("Screencopy: memfd_create failed: {t}", .{e});
                ctx.err = e;
                return;
            };
            defer posix.close(memfd);
            posix.ftruncate(memfd, size) catch |e| {
                log.err("Screencopy: ftruncate failed: {t}", .{e});
                ctx.err = e;
                return;
            };
            ctx.pixels = posix.mmap(null, size, posix.PROT.READ | posix.PROT.WRITE, .{ .TYPE = .SHARED }, memfd, 0) catch unreachable;
            const shmPool = shm.createPool(memfd, @intCast(size)) catch |e| {
                log.err("Screencopy: createPool failed: {t}", .{e});
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
                log.err("Screencopy: createBuffer failed: {t}", .{e});
                ctx.err = e;
                return;
            };
            ctx.buffer = shmBuffer;
            f.copy(ctx.buffer);
            _ = ctx.display.flush();
        },
        .ready => |_| {
            if (ctx.err != null) {
                ctx.buffer.destroy();
                ctx.frame.destroy();
                ctx.allocator.destroy(ctx);
                return;
            }

            const task = gio.Task.new(null, null, null, null);
            task.setTaskData(ctx, null);
            task.runInThread(struct {
                fn cb(task_: *gio.Task, _: *gobject.Object, data: ?*anyopaque, _: ?*gio.Cancellable) callconv(.c) void {
                    defer task_.unref();
                    const ctx_: *Manager.Contxt = @ptrCast(@alignCast(data));
                    defer {
                        ctx_.buffer.destroy();
                        ctx_.frame.destroy();
                        ctx_.allocator.destroy(ctx_);
                    }
                    const bgra = ctx_.pixels;
                    switch (ctx_.option.encode) {
                        .webp => {
                            var output_ptr: [*c]u8 = undefined;
                            // The buffer sent by the compositor is in little-endian order, but the actual memory order of argb/xrgb is bgra.
                            const size = if (std.math.approxEqAbs(f32, ctx_.option.webpQuality, 100, 0.00001))
                                c.WebPEncodeLosslessBGRA(
                                    bgra.ptr,
                                    @intCast(ctx_.width),
                                    @intCast(ctx_.height),
                                    @intCast(ctx_.stride),
                                    &output_ptr,
                                )
                            else
                                c.WebPEncodeBGRA(
                                    bgra.ptr,
                                    @intCast(ctx_.width),
                                    @intCast(ctx_.height),
                                    @intCast(ctx_.stride),
                                    ctx_.option.webpQuality,
                                    &output_ptr,
                                );
                            if (size == 0 or output_ptr == null) {
                                unreachable;
                            }
                            defer c.WebPFree(output_ptr);
                            ctx_.callback(ctx_.err, output_ptr[0..size], ctx_.userdata);
                        },
                        .png => {
                            const png = c.png_create_write_struct(c.PNG_LIBPNG_VER_STRING, null, null, null) orelse {
                                log.err("Screencopy: png_create_write_struct failed", .{});
                                ctx_.err = error.PNGCreateWriteStructFailed;
                                return;
                            };
                            const info = c.png_create_info_struct(png) orelse {
                                log.err("Screencopy: png_create_info_struct failed", .{});
                                ctx_.err = error.PNGCreateInfoStructFailed;
                                return;
                            };
                            defer c.png_destroy_write_struct(@ptrCast(@constCast(&png)), @ptrCast(@constCast(&info)));
                            var buffer = std.ArrayList(u8){};
                            defer buffer.deinit(ctx_.allocator);
                            var writer = buffer.writer(ctx_.allocator);
                            c.png_set_write_fn(png, @ptrCast(&writer), struct {
                                fn write(png_: ?*c.png_struct, data_: [*c]u8, len: usize) callconv(.c) void {
                                    const w: *@TypeOf(writer) = @ptrCast(@alignCast(c.png_get_io_ptr(png_).?));
                                    w.writeAll(data_[0..len]) catch unreachable;
                                }
                            }.write, null);
                            c.png_set_IHDR(
                                png,
                                info,
                                @intCast(ctx_.width),
                                @intCast(ctx_.height),
                                8,
                                c.PNG_COLOR_TYPE_RGBA,
                                c.PNG_INTERLACE_NONE,
                                c.PNG_COMPRESSION_TYPE_DEFAULT,
                                c.PNG_FILTER_TYPE_DEFAULT,
                            );
                            c.png_set_compression_level(png, @intCast(ctx_.option.pngCompression));
                            c.png_write_info(png, info);
                            c.png_set_bgr(png);
                            for (0..ctx_.height) |y| {
                                const row = bgra[y * ctx_.stride ..][0 .. ctx_.width * 4];
                                c.png_write_row(png, row.ptr);
                            }
                            c.png_write_end(png, null);
                            ctx_.callback(ctx_.err, buffer.items, ctx_.userdata);
                        },
                    }
                }
            }.cb);
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
