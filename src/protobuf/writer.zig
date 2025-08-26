const std = @import("std");
const Allocator = std.mem.Allocator;

// Protobuf writer implementation
pub const ProtoWriter = struct {
    buffer: std.ArrayList(u8),
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .buffer = std.ArrayList(u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
    }

    pub fn writeVarint(self: *Self, value: u64) !void {
        var v = value;
        while (v >= 0x80) {
            try self.buffer.append(@intCast((v & 0x7F) | 0x80));
            v >>= 7;
        }
        try self.buffer.append(@intCast(v & 0x7F));
    }

    pub fn writeZigzag(self: *Self, value: i64) !void {
        const encoded: u64 = @bitCast((value << 1) ^ (value >> 63));
        try self.writeVarint(encoded);
    }

    pub fn writeFixed32(self: *Self, value: u32) !void {
        var bytes: [4]u8 = undefined;
        std.mem.writeIntLittle(u32, &bytes, value);
        try self.buffer.appendSlice(&bytes);
    }

    pub fn writeFixed64(self: *Self, value: u64) !void {
        var bytes: [8]u8 = undefined;
        std.mem.writeIntLittle(u64, &bytes, value);
        try self.buffer.appendSlice(&bytes);
    }

    pub fn writeBytes(self: *Self, data: []const u8) !void {
        try self.writeVarint(data.len);
        try self.buffer.appendSlice(data);
    }

    pub fn writeString(self: *Self, str: []const u8) !void {
        // Validate UTF-8
        if (!std.unicode.utf8ValidateSlice(str)) {
            return error.InvalidUtf8;
        }
        try self.writeBytes(str);
    }

    pub fn writeTag(self: *Self, field_number: u32, wire_type: WireType) !void {
        const tag = (field_number << 3) | @intFromEnum(wire_type);
        try self.writeVarint(tag);
    }

    pub fn writeField(self: *Self, field_number: u32, wire_type: WireType, data: []const u8) !void {
        try self.writeTag(field_number, wire_type);
        try self.buffer.appendSlice(data);
    }

    pub fn writeInt32Field(self: *Self, field_number: u32, value: i32) !void {
        try self.writeTag(field_number, .Varint);
        try self.writeZigzag(@intCast(value));
    }

    pub fn writeInt64Field(self: *Self, field_number: u32, value: i64) !void {
        try self.writeTag(field_number, .Varint);
        try self.writeZigzag(value);
    }

    pub fn writeUint32Field(self: *Self, field_number: u32, value: u32) !void {
        try self.writeTag(field_number, .Varint);
        try self.writeVarint(@intCast(value));
    }

    pub fn writeUint64Field(self: *Self, field_number: u32, value: u64) !void {
        try self.writeTag(field_number, .Varint);
        try self.writeVarint(value);
    }

    pub fn writeBoolField(self: *Self, field_number: u32, value: bool) !void {
        try self.writeTag(field_number, .Varint);
        try self.writeVarint(if (value) 1 else 0);
    }

    pub fn writeFloatField(self: *Self, field_number: u32, value: f32) !void {
        try self.writeTag(field_number, .Fixed32);
        try self.writeFixed32(@bitCast(value));
    }

    pub fn writeDoubleField(self: *Self, field_number: u32, value: f64) !void {
        try self.writeTag(field_number, .Fixed64);
        try self.writeFixed64(@bitCast(value));
    }

    pub fn writeBytesField(self: *Self, field_number: u32, data: []const u8) !void {
        try self.writeTag(field_number, .LengthDelimited);
        try self.writeBytes(data);
    }

    pub fn writeStringField(self: *Self, field_number: u32, str: []const u8) !void {
        try self.writeTag(field_number, .LengthDelimited);
        try self.writeString(str);
    }

    pub fn writeMessageField(self: *Self, field_number: u32, message: []const u8) !void {
        try self.writeTag(field_number, .LengthDelimited);
        try self.writeBytes(message);
    }
    
    // Convenience methods for cleaner API
    pub fn writeInt32(self: *Self, field_number: u32, value: i32) !void {
        try self.writeInt32Field(field_number, value);
    }
    
    pub fn writeInt64(self: *Self, field_number: u32, value: i64) !void {
        try self.writeInt64Field(field_number, value);
    }
    
    pub fn writeUint64(self: *Self, field_number: u32, value: u64) !void {
        try self.writeUint64Field(field_number, value);
    }
    
    pub fn writeBool(self: *Self, field_number: u32, value: bool) !void {
        try self.writeBoolField(field_number, value);
    }
    
    pub fn writeMessage(self: *Self, field_number: u32, message: []const u8) !void {
        try self.writeMessageField(field_number, message);
    }

    pub fn writeEnumField(self: *Self, field_number: u32, comptime E: type, value: E) !void {
        try self.writeTag(field_number, .Varint);
        try self.writeVarint(@intCast(@intFromEnum(value)));
    }

    pub fn writePackedRepeatedField(self: *Self, field_number: u32, comptime T: type, values: []const T) !void {
        if (values.len == 0) return;

        // Calculate packed data size
        var packed_size: usize = 0;
        for (values) |value| {
            packed_size += switch (T) {
                i32, i64 => computeZigzagSize(@intCast(value)),
                u32, u64 => computeVarintSize(@intCast(value)),
                f32 => 4,
                f64 => 8,
                bool => 1,
                else => @compileError("Unsupported packed type"),
            };
        }

        // Write tag and length
        try self.writeTag(field_number, .LengthDelimited);
        try self.writeVarint(packed_size);

        // Write packed values
        for (values) |value| {
            switch (T) {
                i32, i64 => try self.writeZigzag(@intCast(value)),
                u32, u64 => try self.writeVarint(@intCast(value)),
                f32 => try self.writeFixed32(@bitCast(value)),
                f64 => try self.writeFixed64(@bitCast(value)),
                bool => try self.writeVarint(if (value) 1 else 0),
                else => unreachable,
            }
        }
    }

    pub fn writeRepeatedField(self: *Self, field_number: u32, comptime T: type, values: []const T) !void {
        for (values) |value| {
            switch (@typeInfo(T)) {
                .Int => |info| {
                    if (info.signedness == .signed) {
                        try self.writeInt64Field(field_number, @intCast(value));
                    } else {
                        try self.writeUint64Field(field_number, @intCast(value));
                    }
                },
                .Float => |info| {
                    if (info.bits == 32) {
                        try self.writeFloatField(field_number, value);
                    } else {
                        try self.writeDoubleField(field_number, value);
                    }
                },
                .Bool => try self.writeBoolField(field_number, value),
                .Enum => try self.writeEnumField(field_number, T, value),
                .Pointer => |ptr| {
                    if (ptr.child == u8) {
                        try self.writeBytesField(field_number, value);
                    } else {
                        @compileError("Unsupported repeated field type");
                    }
                },
                else => @compileError("Unsupported repeated field type"),
            }
        }
    }

    pub fn writeOptionalField(self: *Self, field_number: u32, comptime T: type, value: ?T) !void {
        if (value) |v| {
            switch (@typeInfo(T)) {
                .Int => |info| {
                    if (info.signedness == .signed) {
                        try self.writeInt64Field(field_number, @intCast(v));
                    } else {
                        try self.writeUint64Field(field_number, @intCast(v));
                    }
                },
                .Float => |info| {
                    if (info.bits == 32) {
                        try self.writeFloatField(field_number, v);
                    } else {
                        try self.writeDoubleField(field_number, v);
                    }
                },
                .Bool => try self.writeBoolField(field_number, v),
                .Enum => try self.writeEnumField(field_number, T, v),
                .Pointer => |ptr| {
                    if (ptr.child == u8) {
                        try self.writeBytesField(field_number, v);
                    } else {
                        @compileError("Unsupported optional field type");
                    }
                },
                else => @compileError("Unsupported optional field type"),
            }
        }
    }

    pub fn writeMap(self: *Self, field_number: u32, comptime K: type, comptime V: type, map: anytype) !void {
        var iterator = map.iterator();
        while (iterator.next()) |entry| {
            var map_entry = ProtoWriter.init(self.allocator);
            defer map_entry.deinit();

            // Write key (field 1)
            switch (@typeInfo(K)) {
                .Int => |info| {
                    if (info.signedness == .signed) {
                        try map_entry.writeInt64Field(1, @intCast(entry.key_ptr.*));
                    } else {
                        try map_entry.writeUint64Field(1, @intCast(entry.key_ptr.*));
                    }
                },
                .Pointer => |ptr| {
                    if (ptr.child == u8) {
                        try map_entry.writeStringField(1, entry.key_ptr.*);
                    } else {
                        @compileError("Unsupported map key type");
                    }
                },
                else => @compileError("Unsupported map key type"),
            }

            // Write value (field 2)
            switch (@typeInfo(V)) {
                .Int => |info| {
                    if (info.signedness == .signed) {
                        try map_entry.writeInt64Field(2, @intCast(entry.value_ptr.*));
                    } else {
                        try map_entry.writeUint64Field(2, @intCast(entry.value_ptr.*));
                    }
                },
                .Float => |info| {
                    if (info.bits == 32) {
                        try map_entry.writeFloatField(2, entry.value_ptr.*);
                    } else {
                        try map_entry.writeDoubleField(2, entry.value_ptr.*);
                    }
                },
                .Bool => try map_entry.writeBoolField(2, entry.value_ptr.*),
                .Pointer => |ptr| {
                    if (ptr.child == u8) {
                        try map_entry.writeStringField(2, entry.value_ptr.*);
                    } else {
                        @compileError("Unsupported map value type");
                    }
                },
                else => @compileError("Unsupported map value type"),
            }

            const entry_bytes = try map_entry.toOwnedSlice();
            defer self.allocator.free(entry_bytes);
            try self.writeMessageField(field_number, entry_bytes);
        }
    }

    pub fn getBytes(self: *const Self) []const u8 {
        return self.buffer.items;
    }

    pub fn toOwnedSlice(self: *Self) ![]u8 {
        return try self.buffer.toOwnedSlice();
    }

    pub fn reset(self: *Self) void {
        self.buffer.clearRetainingCapacity();
    }

    pub fn getSize(self: *const Self) usize {
        return self.buffer.items.len;
    }

    pub fn ensureCapacity(self: *Self, capacity: usize) !void {
        try self.buffer.ensureUnusedCapacity(capacity);
    }

    pub fn writeRawBytes(self: *Self, data: []const u8) !void {
        try self.buffer.appendSlice(data);
    }

    pub fn writeRawVarint(self: *Self, value: u64) !void {
        try self.writeVarint(value);
    }
};

// Wire type enum
pub const WireType = enum(u3) {
    Varint = 0,
    Fixed64 = 1,
    LengthDelimited = 2,
    StartGroup = 3, // Deprecated
    EndGroup = 4, // Deprecated
    Fixed32 = 5,
};

// Size computation helpers
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
    const encoded: u64 = @bitCast((value << 1) ^ (value >> 63));
    return computeVarintSize(encoded);
}

pub fn computeFixed32Size() usize {
    return 4;
}

pub fn computeFixed64Size() usize {
    return 8;
}

pub fn computeBytesSize(data: []const u8) usize {
    return computeVarintSize(data.len) + data.len;
}

pub fn computeStringSize(str: []const u8) usize {
    return computeBytesSize(str);
}

pub fn computeMessageSize(message_size: usize) usize {
    return computeVarintSize(message_size) + message_size;
}

pub fn computeTagSize(field_number: u32) usize {
    return computeVarintSize((field_number << 3));
}

pub fn computeFieldSize(field_number: u32, wire_type: WireType, data_size: usize) usize {
    return computeTagSize(field_number) + switch (wire_type) {
        .Varint, .Fixed32, .Fixed64 => data_size,
        .LengthDelimited => computeVarintSize(data_size) + data_size,
        else => 0,
    };
}

// Field validation
pub fn isValidFieldNumber(field_number: u32) bool {
    return field_number >= 1 and field_number <= 536870911 and
        (field_number < 19000 or field_number > 19999); // Reserved range
}

// Message builder helper
pub const MessageBuilder = struct {
    writer: ProtoWriter,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .writer = ProtoWriter.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.writer.deinit();
    }

    pub fn addField(self: *Self, field_number: u32, value: anytype) !void {
        const T = @TypeOf(value);

        if (!isValidFieldNumber(field_number)) {
            return error.InvalidFieldNumber;
        }

        switch (@typeInfo(T)) {
            .Int => |info| {
                if (info.signedness == .signed) {
                    try self.writer.writeInt64Field(field_number, @intCast(value));
                } else {
                    try self.writer.writeUint64Field(field_number, @intCast(value));
                }
            },
            .Float => |info| {
                if (info.bits == 32) {
                    try self.writer.writeFloatField(field_number, value);
                } else {
                    try self.writer.writeDoubleField(field_number, value);
                }
            },
            .Bool => try self.writer.writeBoolField(field_number, value),
            .Enum => try self.writer.writeEnumField(field_number, T, value),
            .Pointer => |ptr| {
                if (ptr.child == u8) {
                    if (ptr.size == .Slice) {
                        try self.writer.writeBytesField(field_number, value);
                    }
                }
            },
            .Optional => try self.writer.writeOptionalField(field_number, @typeInfo(T).Optional.child, value),
            else => @compileError("Unsupported field type"),
        }
    }

    pub fn build(self: *Self) ![]u8 {
        return try self.writer.toOwnedSlice();
    }
};
