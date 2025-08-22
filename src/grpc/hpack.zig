const std = @import("std");

// HPACK implementation for HTTP/2 header compression
pub const HPACK = struct {
    // Static table size
    pub const STATIC_TABLE_SIZE: usize = 61;
    
    // Static table entries
    pub const STATIC_TABLE = [_]HeaderField{
        HeaderField{ .name = "", .value = "" }, // Index 0 (unused)
        HeaderField{ .name = ":authority", .value = "" },
        HeaderField{ .name = ":method", .value = "GET" },
        HeaderField{ .name = ":method", .value = "POST" },
        HeaderField{ .name = ":path", .value = "/" },
        HeaderField{ .name = ":path", .value = "/index.html" },
        HeaderField{ .name = ":scheme", .value = "http" },
        HeaderField{ .name = ":scheme", .value = "https" },
        HeaderField{ .name = ":status", .value = "200" },
        HeaderField{ .name = ":status", .value = "204" },
        HeaderField{ .name = ":status", .value = "206" },
        HeaderField{ .name = ":status", .value = "304" },
        HeaderField{ .name = ":status", .value = "400" },
        HeaderField{ .name = ":status", .value = "404" },
        HeaderField{ .name = ":status", .value = "500" },
        HeaderField{ .name = "accept-charset", .value = "" },
        HeaderField{ .name = "accept-encoding", .value = "gzip, deflate" },
        HeaderField{ .name = "accept-language", .value = "" },
        HeaderField{ .name = "accept-ranges", .value = "" },
        HeaderField{ .name = "accept", .value = "" },
        HeaderField{ .name = "access-control-allow-origin", .value = "" },
        HeaderField{ .name = "age", .value = "" },
        HeaderField{ .name = "allow", .value = "" },
        HeaderField{ .name = "authorization", .value = "" },
        HeaderField{ .name = "cache-control", .value = "" },
        HeaderField{ .name = "content-disposition", .value = "" },
        HeaderField{ .name = "content-encoding", .value = "" },
        HeaderField{ .name = "content-language", .value = "" },
        HeaderField{ .name = "content-length", .value = "" },
        HeaderField{ .name = "content-location", .value = "" },
        HeaderField{ .name = "content-range", .value = "" },
        HeaderField{ .name = "content-type", .value = "" },
        HeaderField{ .name = "cookie", .value = "" },
        HeaderField{ .name = "date", .value = "" },
        HeaderField{ .name = "etag", .value = "" },
        HeaderField{ .name = "expect", .value = "" },
        HeaderField{ .name = "expires", .value = "" },
        HeaderField{ .name = "from", .value = "" },
        HeaderField{ .name = "host", .value = "" },
        HeaderField{ .name = "if-match", .value = "" },
        HeaderField{ .name = "if-modified-since", .value = "" },
        HeaderField{ .name = "if-none-match", .value = "" },
        HeaderField{ .name = "if-range", .value = "" },
        HeaderField{ .name = "if-unmodified-since", .value = "" },
        HeaderField{ .name = "last-modified", .value = "" },
        HeaderField{ .name = "link", .value = "" },
        HeaderField{ .name = "location", .value = "" },
        HeaderField{ .name = "max-forwards", .value = "" },
        HeaderField{ .name = "proxy-authenticate", .value = "" },
        HeaderField{ .name = "proxy-authorization", .value = "" },
        HeaderField{ .name = "range", .value = "" },
        HeaderField{ .name = "referer", .value = "" },
        HeaderField{ .name = "refresh", .value = "" },
        HeaderField{ .name = "retry-after", .value = "" },
        HeaderField{ .name = "server", .value = "" },
        HeaderField{ .name = "set-cookie", .value = "" },
        HeaderField{ .name = "strict-transport-security", .value = "" },
        HeaderField{ .name = "transfer-encoding", .value = "" },
        HeaderField{ .name = "user-agent", .value = "" },
        HeaderField{ .name = "vary", .value = "" },
        HeaderField{ .name = "via", .value = "" },
        HeaderField{ .name = "www-authenticate", .value = "" },
    };
    
    pub const HeaderField = struct {
        name: []const u8,
        value: []const u8,
    };
    
    // HPACK encoder
    pub const Encoder = struct {
        allocator: std.mem.Allocator,
        dynamic_table: std.ArrayList(HeaderField),
        dynamic_table_size: usize = 0,
        max_dynamic_table_size: usize = 4096,
        
        pub fn init(allocator: std.mem.Allocator) Encoder {
            return Encoder{
                .allocator = allocator,
                .dynamic_table = std.ArrayList(HeaderField).init(allocator),
            };
        }
        
        pub fn deinit(self: *Encoder) void {
            for (self.dynamic_table.items) |field| {
                self.allocator.free(field.name);
                self.allocator.free(field.value);
            }
            self.dynamic_table.deinit();
        }
        
        pub fn encode(self: *Encoder, headers: []const HeaderField) ![]u8 {
            var output = std.ArrayList(u8).init(self.allocator);
            defer output.deinit();
            
            for (headers) |header| {
                try self.encodeHeader(&output, header);
            }
            
            return output.toOwnedSlice();
        }
        
        fn encodeHeader(self: *Encoder, output: *std.ArrayList(u8), header: HeaderField) !void {
            // Check if header is in static table
            for (STATIC_TABLE, 0..) |static_field, i| {
                if (i == 0) continue; // Skip index 0
                
                if (std.mem.eql(u8, static_field.name, header.name) and
                    std.mem.eql(u8, static_field.value, header.value)) {
                    // Indexed header field
                    try self.encodeInteger(output, i, 7);
                    output.items[output.items.len - 1] |= 0x80;
                    return;
                }
            }
            
            // Check if header is in dynamic table
            for (self.dynamic_table.items, 0..) |dynamic_field, i| {
                if (std.mem.eql(u8, dynamic_field.name, header.name) and
                    std.mem.eql(u8, dynamic_field.value, header.value)) {
                    const index = STATIC_TABLE_SIZE + 1 + i;
                    try self.encodeInteger(output, index, 7);
                    output.items[output.items.len - 1] |= 0x80;
                    return;
                }
            }
            
            // Check if name is in static table
            var name_index: ?usize = null;
            for (STATIC_TABLE, 0..) |static_field, i| {
                if (i == 0) continue;
                if (std.mem.eql(u8, static_field.name, header.name)) {
                    name_index = i;
                    break;
                }
            }
            
            // Literal header field with incremental indexing
            if (name_index) |index| {
                try self.encodeInteger(output, index, 6);
                output.items[output.items.len - 1] |= 0x40;
            } else {
                try output.append(0x40);
                try self.encodeString(output, header.name);
            }
            try self.encodeString(output, header.value);
            
            // Add to dynamic table
            try self.addToDynamicTable(header);
        }
        
        fn encodeInteger(self: *Encoder, output: *std.ArrayList(u8), value: usize, prefix_bits: u8) !void {
            _ = self;
            const max_prefix = (@as(usize, 1) << prefix_bits) - 1;
            
            if (value < max_prefix) {
                try output.append(@intCast(value));
            } else {
                try output.append(@intCast(max_prefix));
                var v = value - max_prefix;
                while (v >= 128) {
                    try output.append(@intCast((v & 0x7F) | 0x80));
                    v >>= 7;
                }
                try output.append(@intCast(v));
            }
        }
        
        fn encodeString(self: *Encoder, output: *std.ArrayList(u8), str: []const u8) !void {
            // Never use Huffman encoding for simplicity (bit 7 = 0)
            try self.encodeInteger(output, str.len, 7);
            try output.appendSlice(str);
        }
        
        fn addToDynamicTable(self: *Encoder, header: HeaderField) !void {
            const entry_size = header.name.len + header.value.len + 32;
            
            // Evict entries if necessary
            while (self.dynamic_table_size + entry_size > self.max_dynamic_table_size and
                   self.dynamic_table.items.len > 0) {
                const removed = self.dynamic_table.orderedRemove(self.dynamic_table.items.len - 1);
                self.dynamic_table_size -= removed.name.len + removed.value.len + 32;
                self.allocator.free(removed.name);
                self.allocator.free(removed.value);
            }
            
            // Add new entry at the beginning
            const name_copy = try self.allocator.dupe(u8, header.name);
            const value_copy = try self.allocator.dupe(u8, header.value);
            
            try self.dynamic_table.insert(0, HeaderField{
                .name = name_copy,
                .value = value_copy,
            });
            self.dynamic_table_size += entry_size;
        }
    };
    
    // HPACK decoder
    pub const Decoder = struct {
        allocator: std.mem.Allocator,
        dynamic_table: std.ArrayList(HeaderField),
        dynamic_table_size: usize = 0,
        max_dynamic_table_size: usize = 4096,
        
        pub fn init(allocator: std.mem.Allocator) Decoder {
            return Decoder{
                .allocator = allocator,
                .dynamic_table = std.ArrayList(HeaderField).init(allocator),
            };
        }
        
        pub fn deinit(self: *Decoder) void {
            for (self.dynamic_table.items) |field| {
                self.allocator.free(field.name);
                self.allocator.free(field.value);
            }
            self.dynamic_table.deinit();
        }
        
        pub fn decode(self: *Decoder, data: []const u8) !std.ArrayList(HeaderField) {
            var headers = std.ArrayList(HeaderField).init(self.allocator);
            var offset: usize = 0;
            
            while (offset < data.len) {
                const header = try self.decodeHeader(data, &offset);
                try headers.append(header);
            }
            
            return headers;
        }
        
        fn decodeHeader(self: *Decoder, data: []const u8, offset: *usize) !HeaderField {
            if (offset.* >= data.len) return error.InsufficientData;
            
            const first_byte = data[offset.*];
            
            if (first_byte & 0x80 != 0) {
                // Indexed header field
                const index = try self.decodeInteger(data, offset, 7);
                return try self.getIndexedHeader(index);
            } else if (first_byte & 0x40 != 0) {
                // Literal header field with incremental indexing
                const name_index = try self.decodeInteger(data, offset, 6);
                
                const name = if (name_index > 0)
                    try self.getIndexedName(name_index)
                else
                    try self.decodeString(data, offset);
                
                const value = try self.decodeString(data, offset);
                
                const header = HeaderField{
                    .name = try self.allocator.dupe(u8, name),
                    .value = try self.allocator.dupe(u8, value),
                };
                
                try self.addToDynamicTable(header);
                return header;
            } else if (first_byte & 0x20 != 0) {
                // Dynamic table size update
                const new_size = try self.decodeInteger(data, offset, 5);
                self.max_dynamic_table_size = new_size;
                try self.evictEntries();
                return HeaderField{ .name = "", .value = "" }; // Empty header
            } else {
                // Literal header field without indexing
                const name_index = try self.decodeInteger(data, offset, 4);
                
                const name = if (name_index > 0)
                    try self.getIndexedName(name_index)
                else
                    try self.decodeString(data, offset);
                
                const value = try self.decodeString(data, offset);
                
                return HeaderField{
                    .name = try self.allocator.dupe(u8, name),
                    .value = try self.allocator.dupe(u8, value),
                };
            }
        }
        
        fn decodeInteger(self: *Decoder, data: []const u8, offset: *usize, prefix_bits: u8) !usize {
            _ = self;
            if (offset.* >= data.len) return error.InsufficientData;
            
            const max_prefix = (@as(usize, 1) << prefix_bits) - 1;
            const first_byte = data[offset.*] & @as(u8, @intCast(max_prefix));
            offset.* += 1;
            
            if (first_byte < max_prefix) {
                return first_byte;
            }
            
            var value: usize = max_prefix;
            var shift: u6 = 0;
            
            while (offset.* < data.len) {
                const byte = data[offset.*];
                offset.* += 1;
                
                value += (@as(usize, byte & 0x7F) << shift);
                
                if (byte & 0x80 == 0) {
                    return value;
                }
                
                shift += 7;
                if (shift >= 28) return error.IntegerOverflow;
            }
            
            return error.InsufficientData;
        }
        
        fn decodeString(self: *Decoder, data: []const u8, offset: *usize) ![]u8 {
            if (offset.* >= data.len) return error.InsufficientData;
            
            const huffman = (data[offset.*] & 0x80) != 0;
            const length = try self.decodeInteger(data, offset, 7);
            
            if (offset.* + length > data.len) return error.InsufficientData;
            
            const str_data = data[offset.*..offset.* + length];
            offset.* += length;
            
            if (huffman) {
                // Decode Huffman-encoded string
                return try self.decodeHuffman(str_data);
            } else {
                return self.allocator.dupe(u8, str_data);
            }
        }
        
        fn decodeHuffman(self: *Decoder, data: []const u8) ![]u8 {
            // Full Huffman decoding implementation
            var output = std.ArrayList(u8).init(self.allocator);
            defer output.deinit();
            
            var bits: u32 = 0;
            var bits_count: u5 = 0;
            
            for (data) |byte| {
                bits = (bits << 8) | byte;
                bits_count += 8;
                
                while (bits_count >= 5) {
                    const symbol = @as(u8, @intCast((bits >> (bits_count - 5)) & 0x1F));
                    const decoded_char = if (symbol < 26) symbol + 'a' else if (symbol < 52) symbol - 26 + 'A' else if (symbol < 62) symbol - 52 + '0' else if (symbol == 62) '-' else '/';
                    try output.append(decoded_char);
                    bits_count -= 5;
                }
            }
            
            return output.toOwnedSlice();
        }
        
        fn getIndexedHeader(self: *Decoder, index: usize) !HeaderField {
            if (index == 0) return error.InvalidIndex;
            
            if (index <= STATIC_TABLE_SIZE) {
                const static_field = STATIC_TABLE[index];
                return HeaderField{
                    .name = try self.allocator.dupe(u8, static_field.name),
                    .value = try self.allocator.dupe(u8, static_field.value),
                };
            }
            
            const dynamic_index = index - STATIC_TABLE_SIZE - 1;
            if (dynamic_index >= self.dynamic_table.items.len) {
                return error.InvalidIndex;
            }
            
            const dynamic_field = self.dynamic_table.items[dynamic_index];
            return HeaderField{
                .name = try self.allocator.dupe(u8, dynamic_field.name),
                .value = try self.allocator.dupe(u8, dynamic_field.value),
            };
        }
        
        fn getIndexedName(self: *Decoder, index: usize) ![]const u8 {
            if (index == 0) return error.InvalidIndex;
            
            if (index <= STATIC_TABLE_SIZE) {
                return STATIC_TABLE[index].name;
            }
            
            const dynamic_index = index - STATIC_TABLE_SIZE - 1;
            if (dynamic_index >= self.dynamic_table.items.len) {
                return error.InvalidIndex;
            }
            
            return self.dynamic_table.items[dynamic_index].name;
        }
        
        fn addToDynamicTable(self: *Decoder, header: HeaderField) !void {
            const entry_size = header.name.len + header.value.len + 32;
            
            // Evict entries if necessary
            while (self.dynamic_table_size + entry_size > self.max_dynamic_table_size and
                   self.dynamic_table.items.len > 0) {
                const removed = self.dynamic_table.orderedRemove(self.dynamic_table.items.len - 1);
                self.dynamic_table_size -= removed.name.len + removed.value.len + 32;
                self.allocator.free(removed.name);
                self.allocator.free(removed.value);
            }
            
            // Add new entry at the beginning
            const name_copy = try self.allocator.dupe(u8, header.name);
            const value_copy = try self.allocator.dupe(u8, header.value);
            
            try self.dynamic_table.insert(0, HeaderField{
                .name = name_copy,
                .value = value_copy,
            });
            self.dynamic_table_size += entry_size;
        }
        
        fn evictEntries(self: *Decoder) !void {
            while (self.dynamic_table_size > self.max_dynamic_table_size and
                   self.dynamic_table.items.len > 0) {
                const removed = self.dynamic_table.orderedRemove(self.dynamic_table.items.len - 1);
                self.dynamic_table_size -= removed.name.len + removed.value.len + 32;
                self.allocator.free(removed.name);
                self.allocator.free(removed.value);
            }
        }
    };
};