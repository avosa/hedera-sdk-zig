const std = @import("std");

// Recursive Length Prefix (RLP) encoding for Ethereum
pub const RLP = struct {
    // RLP item types
    pub const ItemType = enum {
        String,
        List,
    };
    
    // RLP item
    pub const Item = struct {
        item_type: ItemType,
        data: []const u8,
        children: ?[]Item = null,
        allocator: std.mem.Allocator,
        
        pub fn init(allocator: std.mem.Allocator, item_type: ItemType) Item {
            return Item{
                .item_type = item_type,
                .data = &[_]u8{},
                .children = null,
                .allocator = allocator,
            };
        }
        
        pub fn deinit(self: *Item) void {
            if (self.data.len > 0) {
                self.allocator.free(self.data);
            }
            if (self.children) |children| {
                for (children) |*child| {
                    child.deinit();
                }
                self.allocator.free(children);
            }
        }
        
        pub fn setValue(self: *Item, data: []const u8) !void {
            if (self.data.len > 0) {
                self.allocator.free(self.data);
            }
            self.data = try self.allocator.dupe(u8, data);
        }
        
        pub fn addChild(self: *Item, child: Item) !void {
            if (self.item_type != .List) {
                return error.NotAList;
            }
            
            const old_children = self.children;
            const old_len = if (old_children) |c| c.len else 0;
            
            const new_children = try self.allocator.alloc(Item, old_len + 1);
            
            if (old_children) |c| {
                @memcpy(new_children[0..old_len], c);
                self.allocator.free(c);
            }
            
            new_children[old_len] = child;
            self.children = new_children;
        }
    };
    
    // RLP encoder
    pub const Encoder = struct {
        allocator: std.mem.Allocator,
        
        pub fn init(allocator: std.mem.Allocator) Encoder {
            return Encoder{
                .allocator = allocator,
            };
        }
        
        // Encode bytes
        pub fn encodeBytes(self: *Encoder, data: []const u8) ![]u8 {
            if (data.len == 1 and data[0] < 0x80) {
                // Single byte less than 0x80
                const result = try self.allocator.alloc(u8, 1);
                result[0] = data[0];
                return result;
            } else if (data.len <= 55) {
                // Short string
                const result = try self.allocator.alloc(u8, 1 + data.len);
                result[0] = @intCast(0x80 + data.len);
                @memcpy(result[1..], data);
                return result;
            } else {
                // Long string
                const len_bytes = bytesForInt(data.len);
                const result = try self.allocator.alloc(u8, 1 + len_bytes + data.len);
                result[0] = @intCast(0xb7 + len_bytes);
                writeInt(result[1..1 + len_bytes], data.len);
                @memcpy(result[1 + len_bytes..], data);
                return result;
            }
        }
        
        // Encode string
        pub fn encodeString(self: *Encoder, str: []const u8) ![]u8 {
            return self.encodeBytes(str);
        }
        
        // Encode integer
        pub fn encodeInt(self: *Encoder, value: u256) ![]u8 {
            if (value == 0) {
                return self.encodeBytes(&[_]u8{});
            }
            
            const bytes_needed = bytesForInt(value);
            const bytes = try self.allocator.alloc(u8, bytes_needed);
            defer self.allocator.free(bytes);
            
            var v = value;
            var i: usize = bytes_needed;
            while (i > 0) : (i -= 1) {
                bytes[i - 1] = @intCast(v & 0xFF);
                v >>= 8;
            }
            
            return self.encodeBytes(bytes);
        }
        
        // Encode list
        pub fn encodeList(self: *Encoder, items: []const []const u8) ![]u8 {
            // Calculate total length
            var total_len: usize = 0;
            for (items) |item| {
                total_len += item.len;
            }
            
            if (total_len <= 55) {
                // Short list
                const result = try self.allocator.alloc(u8, 1 + total_len);
                result[0] = @intCast(0xc0 + total_len);
                
                var offset: usize = 1;
                for (items) |item| {
                    @memcpy(result[offset..offset + item.len], item);
                    offset += item.len;
                }
                
                return result;
            } else {
                // Long list
                const len_bytes = bytesForInt(total_len);
                const result = try self.allocator.alloc(u8, 1 + len_bytes + total_len);
                result[0] = @intCast(0xf7 + len_bytes);
                writeInt(result[1..1 + len_bytes], total_len);
                
                var offset: usize = 1 + len_bytes;
                for (items) |item| {
                    @memcpy(result[offset..offset + item.len], item);
                    offset += item.len;
                }
                
                return result;
            }
        }
        
        // Encode item
        pub fn encodeItem(self: *Encoder, item: *const Item) ![]u8 {
            switch (item.item_type) {
                .String => return self.encodeBytes(item.data),
                .List => {
                    if (item.children) |children| {
                        var encoded_children = try self.allocator.alloc([]u8, children.len);
                        defer {
                            for (encoded_children) |child| {
                                self.allocator.free(child);
                            }
                            self.allocator.free(encoded_children);
                        }
                        
                        for (children, 0..) |*child, i| {
                            encoded_children[i] = try self.encodeItem(child);
                        }
                        
                        return self.encodeList(encoded_children);
                    } else {
                        return self.encodeList(&[_][]const u8{});
                    }
                },
            }
        }
    };
    
    // RLP decoder
    pub const Decoder = struct {
        allocator: std.mem.Allocator,
        
        pub fn init(allocator: std.mem.Allocator) Decoder {
            return Decoder{
                .allocator = allocator,
            };
        }
        
        // Decode RLP data
        pub fn decode(self: *Decoder, data: []const u8) !Item {
            var offset: usize = 0;
            return try self.decodeAt(data, &offset);
        }
        
        // Decode at offset
        fn decodeAt(self: *Decoder, data: []const u8, offset: *usize) !Item {
            if (offset.* >= data.len) {
                return error.InsufficientData;
            }
            
            const first_byte = data[offset.*];
            
            if (first_byte < 0x80) {
                // Single byte
                var item = Item.init(self.allocator, .String);
                try item.setValue(data[offset.*..offset.* + 1]);
                offset.* += 1;
                return item;
            } else if (first_byte <= 0xb7) {
                // Short string
                const len = first_byte - 0x80;
                if (offset.* + 1 + len > data.len) {
                    return error.InsufficientData;
                }
                
                var item = Item.init(self.allocator, .String);
                if (len > 0) {
                    try item.setValue(data[offset.* + 1..offset.* + 1 + len]);
                }
                offset.* += 1 + len;
                return item;
            } else if (first_byte <= 0xbf) {
                // Long string
                const len_bytes = first_byte - 0xb7;
                if (offset.* + 1 + len_bytes > data.len) {
                    return error.InsufficientData;
                }
                
                const len = readInt(data[offset.* + 1..offset.* + 1 + len_bytes]);
                if (offset.* + 1 + len_bytes + len > data.len) {
                    return error.InsufficientData;
                }
                
                var item = Item.init(self.allocator, .String);
                try item.setValue(data[offset.* + 1 + len_bytes..offset.* + 1 + len_bytes + len]);
                offset.* += 1 + len_bytes + len;
                return item;
            } else if (first_byte <= 0xf7) {
                // Short list
                const len = first_byte - 0xc0;
                if (offset.* + 1 + len > data.len) {
                    return error.InsufficientData;
                }
                
                offset.* += 1;
                const end_offset = offset.* + len;
                
                var item = Item.init(self.allocator, .List);
                while (offset.* < end_offset) {
                    const child = try self.decodeAt(data, offset);
                    try item.addChild(child);
                }
                
                return item;
            } else {
                // Long list
                const len_bytes = first_byte - 0xf7;
                if (offset.* + 1 + len_bytes > data.len) {
                    return error.InsufficientData;
                }
                
                const len = readInt(data[offset.* + 1..offset.* + 1 + len_bytes]);
                if (offset.* + 1 + len_bytes + len > data.len) {
                    return error.InsufficientData;
                }
                
                offset.* += 1 + len_bytes;
                const end_offset = offset.* + len;
                
                var item = Item.init(self.allocator, .List);
                while (offset.* < end_offset) {
                    const child = try self.decodeAt(data, offset);
                    try item.addChild(child);
                }
                
                return item;
            }
        }
    };
    
    // Helper functions
    fn bytesForInt(value: usize) usize {
        if (value == 0) return 0;
        var bytes: usize = 0;
        var v = value;
        while (v > 0) : (v >>= 8) {
            bytes += 1;
        }
        return bytes;
    }
    
    fn writeInt(dest: []u8, value: usize) void {
        var v = value;
        var i = dest.len;
        while (i > 0) : (i -= 1) {
            dest[i - 1] = @intCast(v & 0xFF);
            v >>= 8;
        }
    }
    
    fn readInt(data: []const u8) usize {
        var value: usize = 0;
        for (data) |byte| {
            value = (value << 8) | byte;
        }
        return value;
    }
};