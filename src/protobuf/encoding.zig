const std = @import("std");

// Wire types for protobuf encoding
pub const WireType = enum(u3) {
    Varint = 0,
    Fixed64 = 1,
    LengthDelimited = 2,
    StartGroup = 3, // Deprecated
    EndGroup = 4, // Deprecated
    Fixed32 = 5,
};

// ProtoWriter handles encoding data to protobuf wire format with Zig optimizations
pub const ProtoWriter = struct {
    buffer: std.ArrayList(u8),
    
    pub fn init(allocator: std.mem.Allocator) ProtoWriter {
        // Pre-allocate buffer for better performance than Go's dynamic growth
        var buffer = std.ArrayList(u8).init(allocator);
        buffer.ensureTotalCapacity(1024) catch {}; // Optimistic pre-allocation
        return ProtoWriter{
            .buffer = buffer,
        };
    }
    
    pub fn deinit(self: *ProtoWriter) void {
        self.buffer.deinit();
    }
    
    pub fn toOwnedSlice(self: *ProtoWriter) ![]u8 {
        return self.buffer.toOwnedSlice();
    }
    
    pub fn getWritten(self: ProtoWriter) []const u8 {
        return self.buffer.items;
    }
    
    // Write a field tag (field number and wire type)
    pub fn writeTag(self: *ProtoWriter, field_number: u32, wire_type: WireType) !void {
        const tag = (field_number << 3) | @intFromEnum(wire_type);
        try self.writeVarint(tag);
    }
    
    // Write a varint (variable-length integer) with Zig's optimized bit operations
    pub fn writeVarint(self: *ProtoWriter, value: u64) !void {
        var v = value;
        // Zig's bit operations are compile-time optimized vs Go's runtime shifts
        while (v >= 0x80) {
            try self.buffer.append(@as(u8, @truncate(v | 0x80)));
            v >>= 7;
        }
        try self.buffer.append(@as(u8, @truncate(v)));
    }
    
    // Write a signed varint using zigzag encoding
    pub fn writeSVarint(self: *ProtoWriter, value: i64) !void {
        const zigzag = if (value < 0) 
            @as(u64, @bitCast(-(value + 1))) * 2 + 1
        else 
            @as(u64, @bitCast(value)) * 2;
        try self.writeVarint(zigzag);
    }
    
    // Write a 32-bit value
    pub fn writeFixed32(self: *ProtoWriter, value: u32) !void {
        var bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &bytes, value, .little);
        try self.buffer.appendSlice(&bytes);
    }
    
    // Write a 64-bit value
    pub fn writeFixed64(self: *ProtoWriter, value: u64) !void {
        var bytes: [8]u8 = undefined;
        std.mem.writeInt(u64, &bytes, value, .little);
        try self.buffer.appendSlice(&bytes);
    }
    
    // Write bytes with length prefix
    pub fn writeBytes(self: *ProtoWriter, data: []const u8) !void {
        try self.writeVarint(@as(u64, data.len));
        try self.buffer.appendSlice(data);
    }
    
    // Write a string field
    pub fn writeString(self: *ProtoWriter, field_number: u32, value: []const u8) !void {
        if (value.len == 0) return;
        try self.writeTag(field_number, .LengthDelimited);
        try self.writeBytes(value);
    }
    
    // Write a bool field
    pub fn writeBool(self: *ProtoWriter, field_number: u32, value: bool) !void {
        try self.writeTag(field_number, .Varint);
        try self.writeVarint(if (value) 1 else 0);
    }
    
    // Write an int32 field
    pub fn writeInt32(self: *ProtoWriter, field_number: u32, value: i32) !void {
        if (value == 0) return;
        try self.writeTag(field_number, .Varint);
        try self.writeSVarint(@as(i64, value));
    }
    
    // Write an int64 field
    pub fn writeInt64(self: *ProtoWriter, field_number: u32, value: i64) !void {
        if (value == 0) return;
        try self.writeTag(field_number, .Varint);
        try self.writeSVarint(value);
    }
    
    // Write a uint32 field
    pub fn writeUint32(self: *ProtoWriter, field_number: u32, value: u32) !void {
        if (value == 0) return;
        try self.writeTag(field_number, .Varint);
        try self.writeVarint(@as(u64, value));
    }
    
    // Write a uint64 field
    pub fn writeUint64(self: *ProtoWriter, field_number: u32, value: u64) !void {
        if (value == 0) return;
        try self.writeTag(field_number, .Varint);
        try self.writeVarint(value);
    }
    
    // Write a message field
    pub fn writeMessage(self: *ProtoWriter, field_number: u32, message_data: []const u8) !void {
        if (message_data.len == 0) return;
        try self.writeTag(field_number, .LengthDelimited);
        try self.writeBytes(message_data);
    }
    
    // Write a repeated field
    pub fn writeRepeated(self: *ProtoWriter, field_number: u32, comptime T: type, values: []const T, write_fn: fn(*ProtoWriter, T) anyerror!void) !void {
        for (values) |value| {
            try self.writeTag(field_number, .LengthDelimited);
            
            // Write to temporary buffer to get size
            var temp_writer = ProtoWriter.init(self.buffer.allocator);
            defer temp_writer.deinit();
            try write_fn(&temp_writer, value);
            
            const data = temp_writer.getWritten();
            try self.writeBytes(data);
        }
    }
    
    // Write packed repeated field
    pub fn writePackedRepeated(self: *ProtoWriter, field_number: u32, comptime T: type, values: []const T, write_fn: fn(*ProtoWriter, T) anyerror!void) !void {
        if (values.len == 0) return;
        
        // Write to temporary buffer to get total size
        var temp_writer = ProtoWriter.init(self.buffer.allocator);
        defer temp_writer.deinit();
        
        for (values) |value| {
            try write_fn(&temp_writer, value);
        }
        
        // Write tag and length-delimited data
        try self.writeTag(field_number, .LengthDelimited);
        try self.writeBytes(temp_writer.getWritten());
    }
};

// ProtoReader handles decoding protobuf wire format
pub const ProtoReader = struct {
    data: []const u8,
    pos: usize,
    
    pub fn init(data: []const u8) ProtoReader {
        return ProtoReader{
            .data = data,
            .pos = 0,
        };
    }
    
    pub fn hasMore(self: ProtoReader) bool {
        return self.pos < self.data.len;
    }
    
    pub fn remaining(self: ProtoReader) usize {
        return self.data.len - self.pos;
    }
    
    // Read a varint
    pub fn readVarint(self: *ProtoReader) !u64 {
        var result: u64 = 0;
        var shift: u6 = 0;
        
        while (self.pos < self.data.len) {
            const byte = self.data[self.pos];
            self.pos += 1;
            
            result |= @as(u64, byte & 0x7F) << shift;
            
            if (byte < 0x80) {
                return result;
            }
            
            shift += 7;
            if (shift >= 64) {
                return error.InvalidVarint;
            }
        }
        
        return error.UnexpectedEndOfData;
    }
    
    // Read a signed varint with zigzag decoding
    pub fn readSVarint(self: *ProtoReader) !i64 {
        const zigzag = try self.readVarint();
        const value = @as(i64, @intCast(zigzag >> 1)) ^ (-@as(i64, @intCast(zigzag & 1)));
        return value;
    }
    
    // Read a field tag and return field number and wire type
    pub fn readTag(self: *ProtoReader) !struct { field_number: u32, wire_type: WireType } {
        const tag = try self.readVarint();
        return .{
            .field_number = @as(u32, @truncate(tag >> 3)),
            .wire_type = @as(WireType, @enumFromInt(@as(u3, @truncate(tag & 0x07)))),
        };
    }
    
    // Read fixed 32-bit value
    pub fn readFixed32(self: *ProtoReader) !u32 {
        if (self.pos + 4 > self.data.len) {
            return error.UnexpectedEndOfData;
        }
        const value = std.mem.readInt(u32, self.data[self.pos..][0..4], .little);
        self.pos += 4;
        return value;
    }
    
    // Read fixed 64-bit value
    pub fn readFixed64(self: *ProtoReader) !u64 {
        if (self.pos + 8 > self.data.len) {
            return error.UnexpectedEndOfData;
        }
        const value = std.mem.readInt(u64, self.data[self.pos..][0..8], .little);
        self.pos += 8;
        return value;
    }
    
    // Read length-delimited data
    pub fn readBytes(self: *ProtoReader) ![]const u8 {
        const length = try self.readVarint();
        if (self.pos + length > self.data.len) {
            return error.UnexpectedEndOfData;
        }
        const result = self.data[self.pos .. self.pos + length];
        self.pos += length;
        return result;
    }
    
    // Skip a field based on wire type
    pub fn skipField(self: *ProtoReader, wire_type: WireType) !void {
        switch (wire_type) {
            .Varint => _ = try self.readVarint(),
            .Fixed64 => self.pos += 8,
            .LengthDelimited => {
                const length = try self.readVarint();
                self.pos += length;
            },
            .Fixed32 => self.pos += 4,
            .StartGroup, .EndGroup => return error.UnsupportedWireType,
        }
    }
    
    // Read a string field
    pub fn readString(self: *ProtoReader) ![]const u8 {
        return self.readBytes();
    }
    
    // Read a bool field
    pub fn readBool(self: *ProtoReader) !bool {
        const value = try self.readVarint();
        return value != 0;
    }
    
    // Read an int32 field
    pub fn readInt32(self: *ProtoReader) !i32 {
        const value = try self.readSVarint();
        return @as(i32, @intCast(value));
    }
    
    // Read an int64 field
    pub fn readInt64(self: *ProtoReader) !i64 {
        return self.readSVarint();
    }
    
    // Read a uint32 field
    pub fn readUint32(self: *ProtoReader) !u32 {
        const value = try self.readVarint();
        return @as(u32, @intCast(value));
    }
    
    // Read a uint64 field
    pub fn readUint64(self: *ProtoReader) !u64 {
        return self.readVarint();
    }
    
    // Read a message field
    pub fn readMessage(self: *ProtoReader) ![]const u8 {
        return self.readBytes();
    }
};

// Helper function to calculate encoded size
pub fn getEncodedSize(comptime T: type, value: T) usize {
    const type_info = @typeInfo(T);
    
    switch (type_info) {
        .Int => |int| {
            if (int.signedness == .signed) {
                const zigzag = if (value < 0) 
                    @as(u64, @bitCast(-(value + 1))) * 2 + 1
                else 
                    @as(u64, @bitCast(value)) * 2;
                return getVarintSize(zigzag);
            } else {
                return getVarintSize(@as(u64, value));
            }
        },
        .Bool => return 1,
        .Pointer => |ptr| {
            if (ptr.size == .Slice and ptr.child == u8) {
                return getVarintSize(value.len) + value.len;
            }
        },
        else => {},
    }
    
    return 0;
}

fn getVarintSize(value: u64) usize {
    var v = value;
    var size: usize = 1;
    while (v >= 0x80) {
        size += 1;
        v >>= 7;
    }
    return size;
}