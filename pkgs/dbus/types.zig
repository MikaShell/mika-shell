const std = @import("std");
const c = @cImport({
    @cInclude("dbus/dbus.h");
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
        pub const empty: Type = &.{};
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
    return Array(struct {
        pub const tag: Tags = .dict;
        pub const typeCode = 'e';
        pub const DictKey = Key;
        pub const DictValue = Value;
        pub const Type = struct {
            key: Key.Type,
            value: Value.Type,
        };
    });
}
pub const Vardict = Dict(String, AnyVariant);
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

const VariantContainer = struct {
    const Self = @This();
    tag: Tags,
    iter: *libdbus.MessageIter,
    value: ?*anyopaque = null,
    appendTo: ?*const fn (Self, *libdbus.MessageIter) libdbus.MessageIter.IterError!void = null,
    pub fn as(self: Self, T: type) T.Type {
        return self.iter.next(T).?;
    }
    pub fn getType(self: Self) Tags {
        return self.iter.getArgType();
    }
};

/// 在没法确定 Variant 的值类型时，可以用 `AnyVariant` 来表示。
pub fn Variant(comptime Sub_: type) type {
    return struct {
        const Self = @This();
        const Sub = if (Sub_ == void) Invalid else Sub_;
        pub const tag: Tags = .variant;
        pub const typeCode = 'v';
        pub const ValueType = Sub;
        pub fn init(value: *const Sub.Type) Type {
            if (Sub == Invalid) @compileError("AnyVariant cannot be initialized with init() method");
            return Type{
                .iter = undefined,
                .tag = Sub.tag,
                .value = @ptrCast(@constCast(value)),
                .appendTo = appendTo,
            };
        }
        fn appendTo(v: VariantContainer, iter: *libdbus.MessageIter) libdbus.MessageIter.IterError!void {
            if (v.tag == .invalid) @panic("AnyVariant cannot be appended to a message");
            const variant = try iter.openContainer(Self);
            defer variant.deinit();
            const value: *ValueType.Type = @ptrCast(@alignCast(v.value));
            try variant.append(ValueType, value.*);
            try iter.closeContainer(variant);
        }
        pub const Type = VariantContainer;
    };
}
pub const AnyVariant = Variant(void);
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
fn count(comptime T: type) usize {
    return switch (T.tag) {
        .invalid => 0,
        .array => 1 + count(T.ArrayElement),
        .dict => 2 + count(T.DictKey) + count(T.DictValue),
        .@"struct" => 2 + blk: {
            var sum: usize = 0;
            for (T.StructFields) |field| {
                sum += count(field);
            }
            break :blk sum;
        },
        else => 1,
    };
}
fn sSignature(comptime T: type) *const [count(T):0]u8 {
    return switch (T.tag) {
        .invalid => @compileError("invalid type has no signature"),
        .array => comptime blk: {
            const subSig = sSignature(T.ArrayElement);
            break :blk std.fmt.comptimePrint("a{s}", .{subSig});
        },
        .dict => comptime blk: {
            const keySig = sSignature(T.DictKey);
            const valueSig = sSignature(T.DictValue);
            break :blk std.fmt.comptimePrint("{{{s}{s}}}", .{ keySig, valueSig });
        },
        .@"struct" => comptime blk: {
            const fields = T.StructFields;
            const size = count(T);
            var buffer: [size:0]u8 = undefined;
            buffer[0] = '(';
            buffer[size - 1] = ')';
            buffer[size] = 0;
            var i: usize = 1;
            for (fields) |field| {
                const len = count(field);
                @memcpy(buffer[i .. i + len], sSignature(field));
                i += len;
            }
            const copy = buffer;
            break :blk &copy;
        },
        else => blk: {
            break :blk &[_:0]u8{T.typeCode};
        },
    };
}
pub fn signature(comptime T: type) []const u8 {
    return sSignature(T)[0..];
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
        .{ .typ = AnyVariant, .signature = "v" },
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
