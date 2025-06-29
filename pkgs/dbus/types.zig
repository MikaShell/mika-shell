const std = @import("std");
const c = @cImport({
    @cInclude("dbus/dbus.h");
    @cInclude("dbus.h");
});
const libdbus = @import("libdbus.zig");
pub fn getTupleTypes(t: anytype) type {
    const info = @typeInfo(@TypeOf(t));
    if (info != .@"struct" or !info.@"struct".is_tuple) {
        @compileError("expected a tuple, found " ++ @typeName(@TypeOf(t)));
    }
    const ts = blk: {
        var tmp: [t.len]type = undefined;
        for (t, 0..) |s, i| {
            tmp[i] = s.Type;
        }
        break :blk tmp;
    };
    return std.meta.Tuple(&ts);
}

pub fn Array(comptime Sub: type) type {
    return struct {
        pub const tag: Tags = .array;
        pub const typeCode = 'a';
        pub const ArrayElement = Sub;
        pub const Type = []const Sub.Type;
    };
}

pub fn Dict(comptime Key: type, comptime Value: type) type {
    const allowKeys = [_]type{
        Byte,
        Boolean,
        Int16,
        UInt16,
        Int32,
        UInt32,
        Int64,
        UInt64,
        Double,
        String,
        ObjectPath,
        Signature,
    };
    for (allowKeys) |K| {
        if (K == Key) break;
    } else {
        @compileError("key type not allowed in dictionary: " ++ @typeName(Key));
    }
    return struct {
        pub const tag: Tags = .dict;
        pub const typeCode = 'e';
        pub const DictKey = Key;
        pub const DictValue = Value;
        pub const Entry = struct {
            key: Key.Type,
            value: Value.Type,
        };
        pub const Type = []const Entry;
    };
}
pub fn Struct(comptime sub: anytype) type {
    const info = @typeInfo(@TypeOf(sub));
    if (info != .@"struct" or !info.@"struct".is_tuple) {
        @compileError("expected a tuple, found " ++ @typeName(@TypeOf(sub)));
    }
    const types = blk: {
        var tmp: [sub.len]type = undefined;
        for (sub, 0..) |s, i| {
            tmp[i] = s.Type;
        }
        break :blk tmp;
    };
    return struct {
        pub const tag: Tags = .@"struct";
        pub const typeCode = 'r';
        pub const StructFields = sub;
        pub const Type = std.meta.Tuple(&types);
    };
}
pub const Variant = struct {
    pub const tag: Tags = .variant;
    pub const typeCode = 'v';
    pub fn init(comptime T: type, value: T.Type) Type {
        const v = std.heap.page_allocator.create(T.Type) catch @panic("OOM");
        v.* = value;
        return .{
            .iter = undefined,
            .tag = T.tag,
            .value = @ptrCast(v),
            .store = struct {
                fn f(self: Type, parent: *libdbus.MessageIter) !void {
                    const iter = try parent.openContainerS(.variant, signature(T));
                    defer iter.deinit();
                    defer parent.closeContainer(iter) catch {};
                    const vv: *T.Type = @ptrCast(@alignCast(self.value));
                    defer std.heap.page_allocator.destroy(vv);
                    try iter.append(T, vv.*);
                }
            }.f,
        };
    }
    pub const Type = struct {
        tag: Tags,
        iter: *libdbus.MessageIter,
        value: *anyopaque,
        store: *const fn (Type, *libdbus.MessageIter) anyerror!void,
        pub fn get(self: Type, T: type) !T.Type {
            return self.iter.next(T).?;
        }
    };
};
pub const Variant2 = struct {
    pub const tag: Tags = .variant;
    pub const typeCode = 'v';
    pub const Type = struct {
        value: *anyopaque,
        signature: []const u8,
    };
};

pub const Invalid = struct {
    pub const tag: Tags = .invalid;
    pub const typeCode = '\x00';
    pub const Type = void;
};
pub const Byte = struct {
    pub const tag: Tags = .byte;
    pub const typeCode = 'y';
    pub const Type = u8;
};
pub const Boolean = struct {
    pub const tag: Tags = .boolean;
    pub const typeCode = 'b';
    pub const Type = bool;
};
pub const Int16 = struct {
    pub const tag: Tags = .int16;
    pub const typeCode = 'n';
    pub const Type = i16;
};
pub const UInt16 = struct {
    pub const tag: Tags = .uint16;
    pub const typeCode = 'q';
    pub const Type = u16;
};
pub const Int32 = struct {
    pub const tag: Tags = .int32;
    pub const typeCode = 'i';
    pub const Type = i32;
};
pub const UInt32 = struct {
    pub const tag: Tags = .uint32;
    pub const typeCode = 'u';
    pub const Type = u32;
};
pub const Int64 = struct {
    pub const tag: Tags = .int64;
    pub const typeCode = 'x';
    pub const Type = i64;
};
pub const UInt64 = struct {
    pub const tag: Tags = .uint64;
    pub const typeCode = 't';
    pub const Type = u64;
};
pub const Double = struct {
    pub const tag: Tags = .double;
    pub const typeCode = 'd';
    pub const Type = f64;
};
pub const String = struct {
    pub const tag: Tags = .string;
    pub const typeCode = 's';
    pub const Type = []const u8;
};
pub const ObjectPath = struct {
    pub const tag: Tags = .object_path;
    pub const typeCode = 'o';
    pub const Type = []const u8;
};
pub const Signature = struct {
    pub const tag: Tags = .signature;
    pub const typeCode = 'g';
    pub const Type = []const u8;
};
pub const UnixFd = struct {
    pub const tag: Tags = .unix_fd;
    pub const typeCode = 'h';
    pub const Type = std.os.linux.fd_t;
};
pub fn signature(comptime T: type) []const u8 {
    return switch (T.tag) {
        .invalid => @compileError("invalid type has no signature"),
        .array => comptime blk: {
            const subSig = signature(T.ArrayElement);
            break :blk std.fmt.comptimePrint("a{s}", .{subSig});
        },
        .dict => comptime blk: {
            const keySig = signature(T.DictKey);
            const valueSig = signature(T.DictValue);
            break :blk std.fmt.comptimePrint("a{{{s}{s}}}", .{ keySig, valueSig });
        },
        .@"struct" => blk: {
            const fields = T.StructFields;
            comptime var len: usize = 0;
            comptime {
                for (fields) |field| {
                    const s = signature(field);
                    len += s.len;
                }
            }
            var sig: [len + 2]u8 = undefined;
            sig[0] = '(';
            sig[len + 1] = ')';
            var i: usize = 1;
            inline for (fields) |field| {
                const s = signature(field);
                std.mem.copyBackwards(u8, sig[i .. i + s.len], s);
                i += s.len;
            }
            break :blk &sig;
        },
        else => &[_]u8{T.typeCode},
    };
}

pub const Tags = enum(c_int) {
    invalid = c.DBUS_TYPE_INVALID,
    byte = c.DBUS_TYPE_BYTE,
    boolean = c.DBUS_TYPE_BOOLEAN,
    int16 = c.DBUS_TYPE_INT16,
    uint16 = c.DBUS_TYPE_UINT16,
    int32 = c.DBUS_TYPE_INT32,
    uint32 = c.DBUS_TYPE_UINT32,
    int64 = c.DBUS_TYPE_INT64,
    uint64 = c.DBUS_TYPE_UINT64,
    double = c.DBUS_TYPE_DOUBLE,
    string = c.DBUS_TYPE_STRING,
    object_path = c.DBUS_TYPE_OBJECT_PATH,
    signature = c.DBUS_TYPE_SIGNATURE,
    unix_fd = c.DBUS_TYPE_UNIX_FD,
    array = c.DBUS_TYPE_ARRAY,
    variant = c.DBUS_TYPE_VARIANT,
    @"struct" = c.DBUS_TYPE_STRUCT,
    dict = c.DBUS_TYPE_DICT_ENTRY,
    pub fn asInt(t: Tags) c_int {
        return @intFromEnum(t);
    }
    pub fn asString(t: Tags) []const u8 {
        return switch (t) {
            .invalid => "\x00",
            .byte => "y",
            .boolean => "b",
            .int16 => "n",
            .uint16 => "q",
            .int32 => "i",
            .uint32 => "u",
            .int64 => "x",
            .uint64 => "t",
            .double => "d",
            .string => "s",
            .object_path => "o",
            .signature => "g",
            .unix_fd => "h",
            .array => "a",
            .variant => "v",
            .@"struct" => "r",
            .dict => "e",
        };
    }
};

const testing = std.testing;

test "signature" {
    const cases = [_]struct {
        typ: type,
        signature: []const u8,
    }{
        .{ .typ = Byte, .signature = "y" },
        .{ .typ = Boolean, .signature = "b" },
        .{ .typ = Int16, .signature = "n" },
        .{ .typ = UInt16, .signature = "q" },
        .{ .typ = Int32, .signature = "i" },
        .{ .typ = UInt32, .signature = "u" },
        .{ .typ = Int64, .signature = "x" },
        .{ .typ = UInt64, .signature = "t" },
        .{ .typ = Double, .signature = "d" },
        .{ .typ = String, .signature = "s" },
        .{ .typ = ObjectPath, .signature = "o" },
        .{ .typ = Signature, .signature = "g" },
        .{ .typ = UnixFd, .signature = "h" },
        .{ .typ = Array(Byte), .signature = "ay" },
        .{ .typ = Array(Array(Byte)), .signature = "aay" },
        .{ .typ = Dict(String, Int32), .signature = "a{si}" },
        .{ .typ = Dict(String, Array(Byte)), .signature = "a{say}" },
        .{ .typ = Variant, .signature = "v" },
        .{ .typ = Struct(.{ String, Int32 }), .signature = "(si)" },
        .{ .typ = Struct(.{ String, Array(Byte) }), .signature = "(say)" },
        .{ .typ = Struct(.{ String, Dict(String, Int32) }), .signature = "(sa{si})" },
        .{ .typ = Struct(.{ Int64, Dict(String, Int32) }), .signature = "(xa{si})" },
    };

    inline for (cases) |case| {
        const actual = signature(case.typ);
        try testing.expectEqualSlices(u8, case.signature, actual);
    }
}
