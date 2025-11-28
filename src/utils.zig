const glib = @import("glib");

pub fn timeoutMainLoop(timeout_ms: u32) void {
    const loop = glib.MainLoop.new(null, 0);
    _ = glib.timeoutAddOnce(timeout_ms, @ptrCast(&struct {
        fn timeout(data: ?*anyopaque) callconv(.c) c_int {
            const loop_: *glib.MainLoop = @ptrCast(@alignCast(data));
            loop_.quit();
            return 0;
        }
    }.timeout), loop);
    loop.run();
}
const jsc = @import("jsc");
pub const JSValue = struct {
    /// `[]const u8` will be converted to a JavaScript string.
    ///
    /// `[]u8` will be converted to a JavaScript Uint8Array.
    pub fn from(ctx: *jsc.Context, value: anytype) *jsc.Value {
        const T = @TypeOf(value);
        switch (@typeInfo(T)) {
            .int => {
                if (value <= -(1 << 53) or value >= (1 << 53)) {
                    std.log.warn("Integer value out of range for JavaScript: {}", .{value});
                }
                return jsc.Value.newNumber(ctx, @floatFromInt(value));
            },
            .comptime_int => {
                return jsc.Value.newNumber(ctx, @floatFromInt(@as(std.math.IntFittingRange(value, value), value)));
            },
            .float, .comptime_float => {
                if (@as(f64, @floatCast(value)) != value) {
                    std.log.warn("Float value out of range for JavaScript: {}", .{value});
                }
                return jsc.Value.newNumber(ctx, @floatCast(value));
            },
            .bool => {
                return jsc.Value.newBoolean(ctx, @intFromBool(value));
            },
            .null => {
                return jsc.Value.newNull(ctx);
            },
            .optional => {
                if (value) |payload| {
                    return from(ctx, payload);
                } else {
                    return from(ctx, null);
                }
            },
            .@"enum" => |info| {
                if (!info.is_exhaustive) {
                    inline for (info.fields) |field| {
                        if (value == @field(T, field.name)) {
                            break;
                        }
                    } else {
                        return from(ctx, @intFromEnum(value));
                    }
                }

                return from(ctx, @tagName(value));
            },
            .enum_literal => {
                return from(ctx, @tagName(value));
            },
            .@"union" => {
                const obj = jsc.Value.newObject(ctx, null, null);
                const info = @typeInfo(T).@"union";
                if (info.tag_type) |UnionTagType| {
                    inline for (info.fields) |u_field| {
                        if (value == @field(UnionTagType, u_field.name)) {
                            const obj_tag = jsc.Value.newObject(ctx, null, null);
                            defer obj_tag.unref();
                            if (u_field.type == void) {
                                // void value is {}
                                obj.objectSetProperty(u_field.name, obj_tag);
                            } else {
                                const val = from(ctx, @field(value, u_field.name));
                                defer val.unref();
                                obj.objectSetProperty(u_field.name, val);
                            }
                            break;
                        }
                    } else {
                        std.debug.print("Unsupported Type: {s}\n", .{@typeName(T)});
                        unreachable; // No active tag?
                    }
                    return obj;
                } else {
                    @compileError("Unable to stringify untagged union '" ++ @typeName(T) ++ "'");
                }
            },
            .@"struct" => |S| {
                if (S.is_tuple) {
                    const g = @import("gobject");
                    const array = jsc.Value.newArray(ctx, g.ext.types.none);
                    inline for (S.fields, 0..) |Field, i| {
                        if (Field.type == void) continue;
                        const val = from(ctx, @field(value, Field.name));
                        defer val.unref();
                        array.objectSetPropertyAtIndex(i, val);
                    }
                    return array;
                } else {
                    const obj = jsc.Value.newObject(ctx, null, null);
                    inline for (S.fields) |Field| {
                        // don't include void fields
                        if (Field.type == void) continue;
                        // don't include private fields
                        if (Field.name[0] == '_') continue;
                        const val = from(ctx, @field(value, Field.name));
                        defer val.unref();
                        obj.objectSetProperty(Field.name, val);
                    }
                    return obj;
                }
            },
            .error_set => return from(ctx, @errorName(value)),

            .pointer => |ptr_info| switch (ptr_info.size) {
                .one => switch (@typeInfo(ptr_info.child)) {
                    .array => {
                        // Coerce `*[N]T` to `[]const T`.
                        const Slice = []const std.meta.Elem(ptr_info.child);
                        return from(ctx, @as(Slice, value));
                    },
                    else => {
                        return from(ctx, value.*);
                    },
                },
                .many, .slice => {
                    if (ptr_info.size == .many and ptr_info.sentinel() == null)
                        @compileError("unable to stringify type '" ++ @typeName(T) ++ "' without sentinel");
                    const slice = if (ptr_info.size == .many) std.mem.span(value) else value;
                    if (ptr_info.child == u8) {
                        // This is a []const u8, or some similar Zig string.
                        if (ptr_info.is_const and std.unicode.utf8ValidateSlice(slice)) {
                            if (slice.len == 0) {
                                return jsc.Value.newString(ctx, "");
                            }
                            if (ptr_info.sentinel() != 0) {
                                const str = std.heap.page_allocator.dupeZ(u8, slice) catch unreachable;
                                defer std.heap.page_allocator.free(str);
                                return jsc.Value.newString(ctx, str.ptr);
                            } else {
                                return jsc.Value.newString(ctx, @ptrCast(slice.ptr));
                            }
                        } else {
                            const buffer = jsc.Value.newTypedArray(ctx, .uint8, slice.len);
                            const data = @as([*]u8, @ptrCast(buffer.typedArrayGetData(null)))[0..slice.len];
                            @memcpy(data, slice);
                            return buffer;
                        }
                    }
                    const g = @import("gobject");
                    const array = jsc.Value.newArray(ctx, g.ext.types.none);
                    for (slice, 0..) |x, i| {
                        const elem_val = from(ctx, x);
                        defer elem_val.unref();
                        array.objectSetPropertyAtIndex(@intCast(i), elem_val);
                    }
                    return array;
                },
                else => @compileError("Unable to stringify type '" ++ @typeName(T) ++ "'"),
            },
            .array => {
                // Coerce `[N]T` to `*const [N]T` (and then to `[]const T`).
                return from(ctx, &value);
            },
            .vector => |info| {
                const array: [info.len]info.child = value;
                return from(ctx, &array);
            },
            else => @compileError("Unsupported type: " ++ @typeName(T)),
        }
    }
};

const std = @import("std");
const testing = std.testing;

test "JSValue.from" {
    const ctx = jsc.Context.new();
    defer ctx.unref();
    {
        const val = JSValue.from(ctx, 42);
        defer val.unref();
        try testing.expectEqual(1, val.isNumber());
        try testing.expectEqual(@as(f64, 42), val.toDouble());
    }
    {
        const val = JSValue.from(ctx, "hello");
        defer val.unref();
        try testing.expectEqual(1, val.isString());
        try testing.expectEqualStrings("hello", std.mem.span(val.toString()));
    }
    {
        const val = JSValue.from(ctx, true);
        defer val.unref();
        try testing.expectEqual(1, val.isBoolean());
        try testing.expectEqual(1, val.toBoolean());
    }
    {
        const data: []u8 = try testing.allocator.dupe(u8, "world");
        defer testing.allocator.free(data);
        const val = JSValue.from(ctx, data);
        defer val.unref();
        try testing.expectEqual(1, val.isTypedArray());
        try testing.expectEqual(jsc.TypedArrayType.uint8, val.typedArrayGetType());
        var size: usize = 0;
        const got = @as([*]u8, @ptrCast(val.typedArrayGetData(&size)));
        try testing.expectEqualSlices(u8, data, got[0..size]);
    }
    {
        const val = JSValue.from(ctx, .{
            .name = "Alice",
            .age = 30,
            .friends = &.{ "", "Charlie" },
            ._private = 42,
        });
        defer val.unref();
        try testing.expectEqual(1, val.isObject());
        const want =
            \\{
            \\    "name": "Alice",
            \\    "age": 30,
            \\    "friends": [
            \\        "",
            \\        "Charlie"
            \\    ]
            \\}
        ;
        try testing.expectEqualStrings(want, std.mem.span(val.toJson(4)));
    }
    {
        const Union = union(enum) {
            a: i32,
            b: f64,
            c: void,
        };
        const val = JSValue.from(ctx, Union{ .a = 42 });
        defer val.unref();
        try testing.expectEqual(1, val.isObject());
        try testing.expectEqual(@as(f64, 42), val.objectGetProperty("a").toDouble());
    }
}
