const std = @import("std");
const Allocator = std.mem.Allocator;

// Protobuf reader implementation
pub const ProtobufReader = struct {
    data: []const u8,
    pos: usize,
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator, data: []const u8) Self {
        return Self{
            .data = data,
            .pos = 0,
            .allocator = allocator,
        };
    }

    pub fn nextField(self: *Self) !?Field {
        if (self.pos >= self.data.len) return null;

        const header = try self.readVarint();
        const tag: u32 = @as(u32, @intCast(header >> 3));
        const wire_type: u3 = @as(u3, @intCast(header & 0x7));

        return Field{
            .reader = self,
            .tag = tag,
            .wire_type = wire_type,
        };
    }

    pub fn readVarint(self: *Self) !u64 {
        var result: u64 = 0;
        var shift: u6 = 0;

        while (self.pos < self.data.len) {
            const byte = self.data[self.pos];
            self.pos += 1;

            result |= (@as(u64, byte & 0x7F) << shift);

            if ((byte & 0x80) == 0) {
                return result;
            }

            shift += 7;
            if (shift >= 64) return error.VarintOverflow;
        }

        return error.UnexpectedEndOfData;
    }

    pub fn readZigzag(self: *Self) !i64 {
        const n = try self.readVarint();
        const result: i64 = @as(i64, @bitCast((n >> 1) ^ (~(n & 1) +% 1)));
        return result;
    }

    pub fn readFixed32(self: *Self) !u32 {
        if (self.pos + 4 > self.data.len) return error.UnexpectedEndOfData;

        const result = std.mem.readIntLittle(u32, self.data[self.pos..][0..4]);
        self.pos += 4;
        return result;
    }

    pub fn readFixed64(self: *Self) !u64 {
        if (self.pos + 8 > self.data.len) return error.UnexpectedEndOfData;

        const result = std.mem.readIntLittle(u64, self.data[self.pos..][0..8]);
        self.pos += 8;
        return result;
    }

    pub fn readBytes(self: *Self, len: usize) ![]const u8 {
        if (self.pos + len > self.data.len) return error.UnexpectedEndOfData;

        const result = self.data[self.pos .. self.pos + len];
        self.pos += len;
        return result;
    }

    pub fn readLengthDelimited(self: *Self) ![]const u8 {
        const len = try self.readVarint();
        return try self.readBytes(@as(usize, @intCast(len)));
    }

    pub fn readString(self: *Self) ![]const u8 {
        const bytes = try self.readLengthDelimited();

        // Validate UTF-8
        if (!std.unicode.utf8ValidateSlice(bytes)) {
            return error.InvalidUtf8;
        }

        return bytes;
    }

    pub fn skipField(self: *Self, wire_type: u3) !void {
        switch (wire_type) {
            0 => _ = try self.readVarint(),
            1 => _ = try self.readFixed64(),
            2 => _ = try self.readLengthDelimited(),
            3, 4 => return error.GroupNotSupported, // Groups are deprecated
            5 => _ = try self.readFixed32(),
            else => return error.InvalidWireType,
        }
    }

    pub fn readMessage(self: *Self, comptime T: type) !T {
        const message_bytes = try self.readLengthDelimited();
        var sub_reader = ProtobufReader.init(self.allocator, message_bytes);
        return try T.fromProtobuf(&sub_reader);
    }

    pub fn readPackedRepeated(self: *Self, comptime T: type, list: *std.ArrayList(T)) !void {
        const packed_bytes = try self.readLengthDelimited();
        var packed_reader = ProtobufReader.init(self.allocator, packed_bytes);

        while (packed_reader.pos < packed_bytes.len) {
            const value = switch (T) {
                i32, i64 => try packed_reader.readZigzag(),
                u32, u64 => try packed_reader.readVarint(),
                f32 => @as(f32, @bitCast(try packed_reader.readFixed32())),
                f64 => @as(f64, @bitCast(try packed_reader.readFixed64())),
                bool => (try packed_reader.readVarint()) != 0,
                else => @compileError("Unsupported packed type"),
            };

            try list.append(@as(T, @intCast(value)));
        }
    }

    pub fn getPosition(self: *const Self) usize {
        return self.pos;
    }

    pub fn setPosition(self: *Self, pos: usize) !void {
        if (pos > self.data.len) return error.InvalidPosition;
        self.pos = pos;
    }

    pub fn getRemainingBytes(self: *const Self) usize {
        return self.data.len - self.pos;
    }

    pub fn isAtEnd(self: *const Self) bool {
        return self.pos >= self.data.len;
    }

    pub fn readInt32(self: *Self) !i32 {
        return @as(i32, @intCast(try self.readZigzag()));
    }

    pub fn readInt64(self: *Self) !i64 {
        return try self.readZigzag();
    }

    pub fn readUint32(self: *Self) !u32 {
        return @as(u32, @intCast(try self.readVarint()));
    }

    pub fn readUint64(self: *Self) !u64 {
        return try self.readVarint();
    }

    pub fn readBool(self: *Self) !bool {
        return (try self.readVarint()) != 0;
    }

    pub fn readFloat(self: *Self) !f32 {
        return @as(f32, @bitCast(try self.readFixed32()));
    }

    pub fn readDouble(self: *Self) !f64 {
        return @as(f64, @bitCast(try self.readFixed64()));
    }

    pub fn readEnum(self: *Self, comptime E: type) !E {
        const value = try self.readVarint();
        return std.meta.intToEnum(E, @as(std.meta.Tag(E), @intCast(value))) catch error.InvalidEnumValue;
    }

    pub const Field = struct {
        reader: *ProtobufReader,
        tag: u32,
        wire_type: u3,

        const FieldSelf = @This();

        pub fn readVarint(self: *FieldSelf) !u64 {
            if (self.wire_type != 0) return error.WireTypeMismatch;
            return try self.reader.readVarint();
        }

        pub fn readZigzag(self: *FieldSelf) !i64 {
            if (self.wire_type != 0) return error.WireTypeMismatch;
            return try self.reader.readZigzag();
        }

        pub fn readFixed32(self: *FieldSelf) !u32 {
            if (self.wire_type != 5) return error.WireTypeMismatch;
            return try self.reader.readFixed32();
        }

        pub fn readFixed64(self: *FieldSelf) !u64 {
            if (self.wire_type != 1) return error.WireTypeMismatch;
            return try self.reader.readFixed64();
        }

        pub fn readBytes(self: *FieldSelf, allocator: Allocator) ![]u8 {
            if (self.wire_type != 2) return error.WireTypeMismatch;

            const data = try self.reader.readLengthDelimited();
            return try allocator.dupe(u8, data);
        }

        pub fn readString(self: *FieldSelf, allocator: Allocator) ![]u8 {
            if (self.wire_type != 2) return error.WireTypeMismatch;

            const str = try self.reader.readString();
            return try allocator.dupe(u8, str);
        }

        pub fn readMessage(self: *FieldSelf, comptime T: type) !T {
            if (self.wire_type != 2) return error.WireTypeMismatch;
            return try self.reader.readMessage(T);
        }

        pub fn readInt32(self: *FieldSelf) !i32 {
            if (self.wire_type != 0) return error.WireTypeMismatch;
            return try self.reader.readInt32();
        }

        pub fn readInt64(self: *FieldSelf) !i64 {
            if (self.wire_type != 0) return error.WireTypeMismatch;
            return try self.reader.readInt64();
        }

        pub fn readUint32(self: *FieldSelf) !u32 {
            if (self.wire_type != 0) return error.WireTypeMismatch;
            return try self.reader.readUint32();
        }

        pub fn readUint64(self: *FieldSelf) !u64 {
            if (self.wire_type != 0) return error.WireTypeMismatch;
            return try self.reader.readUint64();
        }

        pub fn readBool(self: *FieldSelf) !bool {
            if (self.wire_type != 0) return error.WireTypeMismatch;
            return try self.reader.readBool();
        }

        pub fn readFloat(self: *FieldSelf) !f32 {
            if (self.wire_type != 5) return error.WireTypeMismatch;
            return try self.reader.readFloat();
        }

        pub fn readDouble(self: *FieldSelf) !f64 {
            if (self.wire_type != 1) return error.WireTypeMismatch;
            return try self.reader.readDouble();
        }

        pub fn readEnum(self: *FieldSelf, comptime E: type) !E {
            if (self.wire_type != 0) return error.WireTypeMismatch;
            return try self.reader.readEnum(E);
        }

        pub fn readPackedRepeated(self: *FieldSelf, comptime T: type, list: *std.ArrayList(T)) !void {
            if (self.wire_type != 2) return error.WireTypeMismatch;
            return try self.reader.readPackedRepeated(T, list);
        }

        pub fn skip(self: *FieldSelf) !void {
            return try self.reader.skipField(self.wire_type);
        }

        pub fn getTag(self: *const FieldSelf) u32 {
            return self.tag;
        }

        pub fn getWireType(self: *const FieldSelf) u3 {
            return self.wire_type;
        }
    };
};

// Wire type constants
pub const WireType = enum(u3) {
    Varint = 0,
    Fixed64 = 1,
    LengthDelimited = 2,
    StartGroup = 3, // Deprecated
    EndGroup = 4, // Deprecated
    Fixed32 = 5,
};

// Protobuf encoding helpers
pub fn computeVarintSize(value: u64) usize {
    var v = value;
    var size: usize = 1;
    while (v >= 128) {
        size += 1;
        v >>= 7;
    }
    return size;
}

pub fn computeZigzagSize(value: i64) usize {
    const encoded = @as(u64, @bitCast((value << 1) ^ (value >> 63)));
    return computeVarintSize(encoded);
}

pub fn computeStringSize(str: []const u8) usize {
    return computeVarintSize(str.len) + str.len;
}

pub fn computeMessageSize(size: usize) usize {
    return computeVarintSize(size) + size;
}

pub fn computeTagSize(tag: u32) usize {
    return computeVarintSize(tag << 3);
}

// Field number validation
pub fn isValidFieldNumber(field_number: u32) bool {
    return field_number >= 1 and field_number <= 536870911 and
        (field_number < 19000 or field_number > 19999); // Reserved range
}

// Default value helpers
pub fn getDefaultValue(comptime T: type) T {
    return switch (@typeInfo(T)) {
        .Int => 0,
        .Float => 0.0,
        .Bool => false,
        .Enum => @enumFromInt(0),
        .Optional => null,
        .Pointer => &[_]u8{},
        else => undefined,
    };
}

// Message validation
pub fn validateMessage(data: []const u8) !void {
    var reader = ProtobufReader.init(std.testing.allocator, data);

    while (try reader.nextField()) |field| {
        if (!isValidFieldNumber(field.tag)) {
            return error.InvalidFieldNumber;
        }

        try field.skip();
    }
}

// Test helpers for protobuf
pub fn expectEqualMessages(expected: []const u8, actual: []const u8) !void {
    try validateMessage(expected);
    try validateMessage(actual);

    if (!std.mem.eql(u8, expected, actual)) {
        return error.MessagesNotEqual;
    }
}
