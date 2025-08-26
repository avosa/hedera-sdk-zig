const std = @import("std");
const net = std.net;
const crypto = std.crypto;
const Node = @import("node.zig").Node;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;

// HPACK Huffman encoding tables (RFC 7541 Appendix B)
const huffman_codes = [257]u32{
    0x1ff8, 0x7fffd8, 0xfffffe2, 0xfffffe3, 0xfffffe4, 0xfffffe5, 0xfffffe6, 0xfffffe7,
    0xfffffe8, 0xffffea, 0x3ffffffc, 0xfffffe9, 0xfffffea, 0x3ffffffd, 0xfffffeb, 0xfffffec,
    0xfffffed, 0xfffffee, 0xfffffef, 0xffffff0, 0xffffff1, 0xffffff2, 0x3ffffffe, 0xffffff3,
    0xffffff4, 0xffffff5, 0xffffff6, 0xffffff7, 0xffffff8, 0xffffff9, 0xffffffa, 0xffffffb,
    0x14, 0x3f8, 0x3f9, 0xffa, 0x1ff9, 0x15, 0xf8, 0x7fa, 0x3fa, 0x3fb, 0xf9, 0x7fb, 0xfa, 0x16, 0x17, 0x18,
    0x0, 0x1, 0x2, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f, 0x5c, 0xfb, 0x7ffc, 0x20, 0xffb, 0x3fc,
    0x1ffa, 0x21, 0x5d, 0x5e, 0x5f, 0x60, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6a,
    0x6b, 0x6c, 0x6d, 0x6e, 0x6f, 0x70, 0x71, 0x72, 0xfc, 0x73, 0xfd, 0x1ffb, 0x7fff0, 0x1ffc, 0x3ffc,
    0x22, 0x7ffd, 0x3, 0x23, 0x4, 0x24, 0x5, 0x25, 0x26, 0x27, 0x6, 0x74, 0x75, 0x28, 0x29, 0x2a,
    0x7, 0x2b, 0x76, 0x2c, 0x8, 0x9, 0x2d, 0x77, 0x78, 0x79, 0x7a, 0x7b, 0x7ffe, 0x7fc, 0x3ffd, 0x1ffd,
    0xffffffc, 0xfffe6, 0x3fffd2, 0xfffe7, 0xfffe8, 0x3fffd3, 0x3fffd4, 0x3fffd5, 0x7fffd9, 0x3fffd6,
    0x7fffda, 0x7fffdb, 0x7fffdc, 0x7fffdd, 0x7fffde, 0xffffeb, 0x7fffdf, 0xffffec, 0xffffed, 0x3fffd7,
    0x7fffe0, 0xffffee, 0x7fffe1, 0x7fffe2, 0x7fffe3, 0x7fffe4, 0xffffef, 0x3fffd8, 0x3fffd9, 0xffffd9,
    0x3fffda, 0x3fffdb, 0x3fffdc, 0x3fffdd, 0x3fffde, 0xffffdf, 0x3fffdf, 0x3fffe0, 0x3fffe1, 0x3fffe2,
    0x3fffe3, 0x3fffe4, 0x3fffe5, 0x3fffe6, 0x3fffe7, 0x3fffe8, 0x3fffe9, 0x3fffea, 0x3fffeb, 0x3fffec,
    0x3fffed, 0x3fffee, 0x3fffef, 0x3ffff0, 0x3ffff1, 0x3ffff2, 0x3ffff3, 0x3ffff4, 0x3ffff5, 0x3ffff6,
    0x3ffff7, 0x3ffff8, 0x3ffff9, 0x3ffffa, 0x3ffffb, 0x3ffffc, 0x3ffffd, 0x3ffffe, 0x3fffff, 0x3fffffc,
    0x3fffffd, 0x3fffffe, 0x3ffffff, 0x3ffffff0, 0x3ffffff1, 0x3ffffff2, 0x3ffffff3, 0x3ffffff4,
    0x3ffffff5, 0x3ffffff6, 0x3ffffff7, 0x3ffffff8, 0x3ffffff9, 0x3ffffffa, 0x3ffffffb, 0x3ffffffc,
    0x3ffffffd, 0x3ffffffe, 0x3fffffff, 0x7ffffe0, 0x7ffffe1, 0x7ffffe2, 0x7ffffe3, 0x7ffffe4,
    0x7ffffe5, 0x7ffffe6, 0x7ffffe7, 0x7ffffe8, 0x7ffffe9, 0x7ffffea, 0x7ffffeb, 0x7ffffec,
    0x7ffffed, 0x7ffffee, 0x7ffffef, 0x7fffff0, 0x7fffff1, 0x7fffff2, 0x7fffff3, 0x7fffff4,
    0x7fffff5, 0x7fffff6, 0x7fffff7, 0x7fffff8, 0x7fffff9, 0x7fffffa, 0x7fffffb, 0x7fffffc,
    0x7fffffd, 0x7fffffe, 0x7ffffff, 0xfffffff, 0xfffffffe, 0xffffffff, 0xfffffffa, 0xfffffffb,
    0xfffffffc, 0xfffffffd, 0xfffffffe, 0xffffffff,
};

const huffman_code_lengths = [256]u8{
    13, 23, 28, 28, 28, 28, 28, 28, 28, 24, 30, 28, 28, 30, 28, 28,
    28, 28, 28, 28, 28, 28, 30, 28, 28, 28, 28, 28, 28, 28, 28, 28,
    6, 10, 10, 12, 13, 6, 8, 11, 10, 10, 8, 11, 8, 6, 6, 6,
    5, 5, 5, 6, 6, 6, 6, 6, 6, 6, 7, 8, 15, 6, 12, 10,
    13, 6, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 8, 7, 8, 13, 19, 13, 14, 6,
    15, 5, 6, 5, 6, 5, 6, 6, 6, 5, 7, 7, 6, 6, 6, 5,
    6, 7, 6, 5, 5, 6, 7, 7, 7, 7, 7, 15, 11, 14, 13, 28,
    20, 22, 20, 20, 22, 22, 22, 23, 22, 23, 23, 23, 23, 23, 24, 23,
    24, 24, 22, 23, 24, 23, 23, 23, 23, 21, 22, 23, 22, 23, 23, 24,
    22, 21, 20, 22, 22, 23, 23, 21, 23, 22, 22, 24, 21, 22, 23, 23,
    21, 21, 22, 21, 23, 22, 23, 23, 20, 22, 22, 22, 23, 22, 22, 23,
    26, 26, 20, 19, 22, 23, 22, 25, 26, 26, 26, 27, 27, 26, 24, 25,
    19, 21, 26, 27, 27, 26, 27, 24, 21, 21, 26, 26, 28, 27, 27, 27,
    20, 24, 20, 21, 22, 21, 21, 23, 22, 22, 25, 25, 24, 24, 26, 23,
    26, 27, 26, 26, 27, 27, 27, 27, 27, 28, 27, 27, 27, 27, 27, 26,
};

// gRPC status codes
pub const GrpcStatus = enum(u32) {
    Ok = 0,
    Cancelled = 1,
    Unknown = 2,
    InvalidArgument = 3,
    DeadlineExceeded = 4,
    NotFound = 5,
    AlreadyExists = 6,
    PermissionDenied = 7,
    ResourceExhausted = 8,
    FailedPrecondition = 9,
    Aborted = 10,
    OutOfRange = 11,
    Unimplemented = 12,
    Internal = 13,
    Unavailable = 14,
    DataLoss = 15,
    Unauthenticated = 16,
    
    pub fn isOk(self: GrpcStatus) bool {
        return self == .Ok;
    }
    
    pub fn toError(self: GrpcStatus) !void {
        return switch (self) {
            .Ok => {},
            .Cancelled => error.Cancelled,
            .Unknown => error.Unknown,
            .InvalidArgument => error.InvalidArgument,
            .DeadlineExceeded => error.DeadlineExceeded,
            .NotFound => error.NotFound,
            .AlreadyExists => error.AlreadyExists,
            .PermissionDenied => error.PermissionDenied,
            .ResourceExhausted => error.ResourceExhausted,
            .FailedPrecondition => error.FailedPrecondition,
            .Aborted => error.Aborted,
            .OutOfRange => error.OutOfRange,
            .Unimplemented => error.Unimplemented,
            .Internal => error.Internal,
            .Unavailable => error.Unavailable,
            .DataLoss => error.DataLoss,
            .Unauthenticated => error.Unauthenticated,
        };
    }
};

// HTTP/2 frame types
pub const FrameType = enum(u8) {
    Data = 0x0,
    Headers = 0x1,
    Priority = 0x2,
    RstStream = 0x3,
    Settings = 0x4,
    PushPromise = 0x5,
    Ping = 0x6,
    GoAway = 0x7,
    WindowUpdate = 0x8,
    Continuation = 0x9,
};

// HTTP/2 frame flags
pub const FrameFlags = struct {
    pub const END_STREAM: u8 = 0x1;
    pub const END_HEADERS: u8 = 0x4;
    pub const PADDED: u8 = 0x8;
    pub const PRIORITY: u8 = 0x20;
};

// HTTP/2 settings
pub const Settings = struct {
    pub const HEADER_TABLE_SIZE: u16 = 0x1;
    pub const ENABLE_PUSH: u16 = 0x2;
    pub const MAX_CONCURRENT_STREAMS: u16 = 0x3;
    pub const INITIAL_WINDOW_SIZE: u16 = 0x4;
    pub const MAX_FRAME_SIZE: u16 = 0x5;
    pub const MAX_HEADER_LIST_SIZE: u16 = 0x6;
};

// HTTP/2 frame
pub const Frame = struct {
    length: u24,
    frame_type: FrameType,
    flags: u8,
    stream_id: u31,
    payload: []const u8,
    
    pub fn encode(self: Frame, writer: anytype) !void {
        // Write frame header (9 bytes)
        try writer.writeInt(u24, self.length, .big);
        try writer.writeByte(@intFromEnum(self.frame_type));
        try writer.writeByte(self.flags);
        try writer.writeInt(u32, @as(u32, self.stream_id) & 0x7FFFFFFF, .big);
        
        // Write payload
        try writer.writeAll(self.payload);
    }
    
    pub fn decode(reader: anytype, allocator: std.mem.Allocator) !Frame {
        // Read frame header
        const length = try reader.readInt(u24, .big);
        const frame_type = @as(FrameType, @enumFromInt(try reader.readByte()));
        const flags = try reader.readByte();
        const stream_id = @as(u31, @intCast(try reader.readInt(u32, .big) & 0x7FFFFFFF));
        
        // Read payload
        const payload = try allocator.alloc(u8, length);
        _ = try reader.read(payload);
        
        return Frame{
            .length = length,
            .frame_type = frame_type,
            .flags = flags,
            .stream_id = stream_id,
            .payload = payload,
        };
    }
};

// HPACK encoder for HTTP/2 headers
pub const HpackEncoder = struct {
    allocator: std.mem.Allocator,
    dynamic_table: std.ArrayList(Header),
    max_dynamic_table_size: usize,
    current_table_size: usize,
    
    const Header = struct {
        name: []const u8,
        value: []const u8,
    };
    
    pub fn init(allocator: std.mem.Allocator) HpackEncoder {
        return HpackEncoder{
            .allocator = allocator,
            .dynamic_table = std.ArrayList(Header).init(allocator),
            .max_dynamic_table_size = 4096,
            .current_table_size = 0,
        };
    }
    
    pub fn deinit(self: *HpackEncoder) void {
        self.dynamic_table.deinit();
    }
    
    pub fn encode(self: *HpackEncoder, headers: []const Header, writer: anytype) !void {
        for (headers) |header| {
            // Indexed header field (static table)
            if (getStaticTableIndex(header.name)) |index| {
                try self.encodeInteger(writer, index, 7);
                try self.encodeString(writer, header.value, false);
            } else {
                // Literal header field with incremental indexing
                try writer.writeByte(0x40); // 01 prefix
                try self.encodeString(writer, header.name, false);
                try self.encodeString(writer, header.value, false);
                
                // Store in dynamic table
                try self.addToDynamicTable(header);
            }
        }
    }
    
    fn encodeInteger(self: *HpackEncoder, writer: anytype, value: u32, prefix_bits: u3) !void {
        _ = self;
        const max_prefix = (@as(u32, 1) << prefix_bits) - 1;
        
        if (value < max_prefix) {
            try writer.writeByte(@as(u8, @intCast(value)));
        } else {
            try writer.writeByte(@as(u8, @intCast(max_prefix)));
            var v = value - max_prefix;
            while (v >= 128) {
                try writer.writeByte(@as(u8, @intCast((v & 0x7F) | 0x80)));
                v >>= 7;
            }
            try writer.writeByte(@as(u8, @intCast(v)));
        }
    }
    
    fn encodeString(self: *HpackEncoder, writer: anytype, str: []const u8, huffman: bool) !void {
        if (huffman) {
            // Encode using HPACK Huffman encoding
            var encoded = try self.allocator.alloc(u8, str.len * 2); // Worst case size
            defer self.allocator.free(encoded);
            
            var bit_buffer: u32 = 0;
            var bit_count: u5 = 0;
            var encoded_len: usize = 0;
            
            for (str) |byte| {
                const code = huffman_codes[byte];
                const code_bits = huffman_code_lengths[byte];
                
                bit_buffer = (bit_buffer << @intCast(code_bits)) | code;
                bit_count += @intCast(code_bits);
                
                while (bit_count >= 8) {
                    bit_count -= 8;
                    encoded[encoded_len] = @intCast((bit_buffer >> bit_count) & 0xFF);
                    encoded_len += 1;
                }
            }
            
            // Pad with EOS pattern (all 1s) if needed
            if (bit_count > 0) {
                bit_buffer <<= @intCast(8 - bit_count);
                bit_buffer |= (@as(u32, 1) << @intCast(8 - bit_count)) - 1;
                encoded[encoded_len] = @intCast(bit_buffer & 0xFF);
                encoded_len += 1;
            }
            
            // Write huffman flag (1) and length
            try self.encodeInteger(writer, @intCast(encoded_len), 7);
            const first_byte = writer.context.items[writer.context.items.len - encoded_len - 1];
            writer.context.items[writer.context.items.len - encoded_len - 1] = first_byte | 0x80;
            try writer.writeAll(encoded[0..encoded_len]);
        } else {
            // Raw string
            try self.encodeInteger(writer, @as(u32, @intCast(str.len)), 7);
            try writer.writeAll(str);
        }
    }
    
    fn addToDynamicTable(self: *HpackEncoder, header: Header) !void {
        const entry_size = header.name.len + header.value.len + 32;
        
        // Evict entries if necessary
        while (self.current_table_size + entry_size > self.max_dynamic_table_size and
               self.dynamic_table.items.len > 0) {
            const removed = self.dynamic_table.orderedRemove(self.dynamic_table.items.len - 1);
            self.current_table_size -= removed.name.len + removed.value.len + 32;
        }
        
        // Store new entry
        try self.dynamic_table.insert(0, header);
        self.current_table_size += entry_size;
    }
    
    fn getStaticTableIndex(name: []const u8) ?u32 {
        // Common static table entries for gRPC
        if (std.mem.eql(u8, name, ":authority")) return 1;
        if (std.mem.eql(u8, name, ":method")) return 2;
        if (std.mem.eql(u8, name, ":path")) return 4;
        if (std.mem.eql(u8, name, ":scheme")) return 6;
        if (std.mem.eql(u8, name, ":status")) return 8;
        if (std.mem.eql(u8, name, "content-type")) return 31;
        if (std.mem.eql(u8, name, "te")) return null;
        if (std.mem.eql(u8, name, "grpc-timeout")) return null;
        if (std.mem.eql(u8, name, "grpc-encoding")) return null;
        return null;
    }
};

// gRPC connection to a single node
pub const GrpcConnection = struct {
    allocator: std.mem.Allocator,
    stream: net.Stream,
    node: Node,
    next_stream_id: u31,
    encoder: HpackEncoder,
    decoder: HpackDecoder,
    window_size: i32,
    settings_received: bool,
    mutex: std.Thread.Mutex,
    
    const PREFACE = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n";
    const DEFAULT_WINDOW_SIZE: i32 = 65535;
    const MAX_FRAME_SIZE: u32 = 16384;
    
    pub fn init(allocator: std.mem.Allocator, node: Node) !GrpcConnection {
        // Hedera REQUIRES TLS on port 50211 - this is production code
        // Using Zig's HTTP client which has full TLS support
        
        // Create HTTP client for TLS connection
        var http_client = std.http.Client{ .allocator = allocator };
        
        // Extract IP and port from node address
        const address_str = try std.fmt.allocPrint(allocator, "{}", .{node.address});
        defer allocator.free(address_str);
        
        const ip_end = std.mem.indexOf(u8, address_str, ":") orelse address_str.len;
        const ip = address_str[0..ip_end];
        
        // Build HTTPS URL for Hedera gRPC endpoint
        const url = try std.fmt.allocPrint(allocator, "https://{}:50211", .{ip});
        defer allocator.free(url);
        
        // Parse URL for connection
        const uri = try std.Uri.parse(url);
        
        // Create headers for HTTP/2 gRPC
        var headers = std.http.Headers{ .allocator = allocator };
        defer headers.deinit();
        try headers.append("connection", "Upgrade");
        try headers.append("upgrade", "h2c"); // HTTP/2 cleartext
        
        // Create the request to establish HTTP/2 connection
        var request = try http_client.request(.POST, uri, headers, .{});
        
        // This establishes the TLS connection with the Hedera node
        try request.start();
        
        // Get the underlying stream for HTTP/2 communication
        const stream = request.connection.?.stream;
        
        var conn = GrpcConnection{
            .allocator = allocator,
            .stream = stream,
            .node = node,
            .next_stream_id = 1,
            .encoder = HpackEncoder.init(allocator),
            .decoder = HpackDecoder.init(allocator),
            .window_size = DEFAULT_WINDOW_SIZE,
            .settings_received = false,
            .mutex = .{},
        };
        
        // Send HTTP/2 connection preface for gRPC
        try conn.sendPreface();
        
        // Send initial SETTINGS frame
        try conn.sendSettings();
        
        // Read SETTINGS frame from server
        try conn.readSettings();
        
        return conn;
    }
    
    pub fn deinit(self: *GrpcConnection) void {
        self.stream.close();
        self.encoder.deinit();
        self.decoder.deinit();
    }
    
    fn sendPreface(self: *GrpcConnection) !void {
        try self.stream.writer().writeAll(PREFACE);
    }
    
    fn sendSettings(self: *GrpcConnection) !void {
        var settings_payload = std.ArrayList(u8).init(self.allocator);
        defer settings_payload.deinit();
        
        // SETTINGS_INITIAL_WINDOW_SIZE
        try settings_payload.writer().writeInt(u16, Settings.INITIAL_WINDOW_SIZE, .big);
        try settings_payload.writer().writeInt(u32, DEFAULT_WINDOW_SIZE, .big);
        
        // SETTINGS_MAX_FRAME_SIZE
        try settings_payload.writer().writeInt(u16, Settings.MAX_FRAME_SIZE, .big);
        try settings_payload.writer().writeInt(u32, MAX_FRAME_SIZE, .big);
        
        const frame = Frame{
            .length = @as(u24, @intCast(settings_payload.items.len)),
            .frame_type = .Settings,
            .flags = 0,
            .stream_id = 0,
            .payload = settings_payload.items,
        };
        
        try frame.encode(self.stream.writer());
    }
    
    fn readSettings(self: *GrpcConnection) !void {
        const frame = try Frame.decode(self.stream.reader(), self.allocator);
        defer self.allocator.free(frame.payload);
        
        if (frame.frame_type != .Settings) {
            return error.UnexpectedFrame;
        }
        
        // Parse settings
        var i: usize = 0;
        while (i < frame.payload.len) : (i += 6) {
            const id = std.mem.readInt(u16, frame.payload[i..][0..2], .big);
            const value = std.mem.readInt(u32, frame.payload[i + 2 ..][0..4], .big);
            
            switch (id) {
                Settings.INITIAL_WINDOW_SIZE => self.window_size = @as(i32, @intCast(value)),
                else => {}, // Ignore other settings
            }
        }
        
        // Send SETTINGS ACK
        const ack_frame = Frame{
            .length = 0,
            .frame_type = .Settings,
            .flags = 0x1, // ACK flag
            .stream_id = 0,
            .payload = &[_]u8{},
        };
        
        try ack_frame.encode(self.stream.writer());
        self.settings_received = true;
    }
    
    pub fn call(self: *GrpcConnection, service: []const u8, method: []const u8, request: []const u8) ![]u8 {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const stream_id = self.getNextStreamId();
        
        // Send headers
        try self.sendHeaders(stream_id, service, method);
        
        // Send request data
        try self.sendData(stream_id, request, true);
        
        // Read response
        return try self.readResponse(stream_id);
    }
    
    fn getNextStreamId(self: *GrpcConnection) u31 {
        const id = self.next_stream_id;
        self.next_stream_id += 2; // Client uses odd stream IDs
        return id;
    }
    
    fn sendHeaders(self: *GrpcConnection, stream_id: u31, service: []const u8, method: []const u8) !void {
        var headers_data = std.ArrayList(u8).init(self.allocator);
        defer headers_data.deinit();
        
        const path = try std.fmt.allocPrint(self.allocator, "/{s}/{s}", .{ service, method });
        defer self.allocator.free(path);
        
        const headers = [_]HpackEncoder.Header{
            .{ .name = ":method", .value = "POST" },
            .{ .name = ":scheme", .value = "https" },
            .{ .name = ":path", .value = path },
            .{ .name = ":authority", .value = try std.fmt.allocPrint(self.allocator, "{}", .{self.node.address}) },
            .{ .name = "content-type", .value = "application/grpc+proto" },
            .{ .name = "te", .value = "trailers" },
            .{ .name = "grpc-accept-encoding", .value = "identity" },
        };
        defer self.allocator.free(headers[3].value);
        
        try self.encoder.encode(&headers, headers_data.writer());
        
        const frame = Frame{
            .length = @as(u24, @intCast(headers_data.items.len)),
            .frame_type = .Headers,
            .flags = FrameFlags.END_HEADERS,
            .stream_id = stream_id,
            .payload = headers_data.items,
        };
        
        try frame.encode(self.stream.writer());
    }
    
    fn sendData(self: *GrpcConnection, stream_id: u31, data: []const u8, end_stream: bool) !void {
        // gRPC message format: [compression_flag(1)] [length(4)] [data]
        var message = std.ArrayList(u8).init(self.allocator);
        defer message.deinit();
        
        try message.writer().writeByte(0); // No compression
        try message.writer().writeInt(u32, @as(u32, @intCast(data.len)), .big);
        try message.writer().writeAll(data);
        
        const frame = Frame{
            .length = @as(u24, @intCast(message.items.len)),
            .frame_type = .Data,
            .flags = if (end_stream) FrameFlags.END_STREAM else 0,
            .stream_id = stream_id,
            .payload = message.items,
        };
        
        try frame.encode(self.stream.writer());
    }
    
    fn readResponse(self: *GrpcConnection, stream_id: u31) ![]u8 {
        var response_data = std.ArrayList(u8).init(self.allocator);
        var headers_received = false;
        var data_received = false;
        var grpc_status: ?GrpcStatus = null;
        
        while (true) {
            const frame = try Frame.decode(self.stream.reader(), self.allocator);
            defer self.allocator.free(frame.payload);
            
            if (frame.stream_id != stream_id and frame.stream_id != 0) {
                continue; // Not for our stream
            }
            
            switch (frame.frame_type) {
                .Headers => {
                    if (!headers_received) {
                        headers_received = true;
                        // Parse headers for grpc-status
                        const headers = try self.decoder.decode(frame.payload);
                        for (headers) |header| {
                            if (std.mem.eql(u8, header.name, "grpc-status")) {
                                grpc_status = @as(GrpcStatus, @enumFromInt(try std.fmt.parseInt(u32, header.value, 10)));
                            }
                        }
                    }
                    
                    if (frame.flags & FrameFlags.END_STREAM != 0) {
                        break;
                    }
                },
                .Data => {
                    data_received = true;
                    // Parse gRPC message format
                    if (frame.payload.len >= 5) {
                        const compression = frame.payload[0];
                        const length = std.mem.readInt(u32, frame.payload[1..5], .big);
                        
                        if (compression != 0) {
                            return error.CompressionNotSupported;
                        }
                        
                        if (5 + length <= frame.payload.len) {
                            try response_data.appendSlice(frame.payload[5 .. 5 + length]);
                        }
                    }
                    
                    if (frame.flags & FrameFlags.END_STREAM != 0) {
                        break;
                    }
                },
                .RstStream => {
                    const error_code = std.mem.readInt(u32, frame.payload[0..4], .big);
                    return switch (error_code) {
                        1 => error.ProtocolError,
                        2 => error.InternalError,
                        3 => error.FlowControlError,
                        4 => error.SettingsTimeout,
                        5 => error.StreamClosed,
                        6 => error.FrameSizeError,
                        7 => error.RefusedStream,
                        8 => error.Cancel,
                        9 => error.CompressionError,
                        10 => error.ConnectError,
                        11 => error.EnhanceYourCalm,
                        12 => error.InadequateSecurity,
                        13 => error.Http11Required,
                        else => error.UnknownError,
                    };
                },
                .WindowUpdate => {
                    const increment = std.mem.readInt(u32, frame.payload[0..4], .big) & 0x7FFFFFFF;
                    self.window_size += @as(i32, @intCast(increment));
                },
                else => {},
            }
        }
        
        // Check gRPC status
        if (grpc_status) |status| {
            try status.toError();
        }
        
        return response_data.toOwnedSlice();
    }
};

// HPACK decoder for HTTP/2 headers
pub const HpackDecoder = struct {
    dynamic_table: std.ArrayList(Header),
    max_dynamic_table_size: usize,
    current_table_size: usize,
    allocator: std.mem.Allocator,
    
    const Header = struct {
        name: []const u8,
        value: []const u8,
    };
    
    pub fn init(allocator: std.mem.Allocator) HpackDecoder {
        return HpackDecoder{
            .dynamic_table = std.ArrayList(Header).init(allocator),
            .max_dynamic_table_size = 4096,
            .current_table_size = 0,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *HpackDecoder) void {
        self.dynamic_table.deinit();
    }
    
    pub fn decode(self: *HpackDecoder, data: []const u8) ![]Header {
        var headers = std.ArrayList(Header).init(self.allocator);
        var i: usize = 0;
        
        while (i < data.len) {
            const byte = data[i];
            
            if (byte & 0x80 != 0) {
                // Indexed header field
                const index = try self.decodeInteger(data, &i, 7);
                const header = try self.getIndexedHeader(index);
                try headers.append(header);
            } else if (byte & 0x40 != 0) {
                // Literal header field with incremental indexing
                i += 1;
                const name = try self.decodeString(data, &i);
                const value = try self.decodeString(data, &i);
                const header = Header{ .name = name, .value = value };
                try headers.append(header);
                try self.addToDynamicTable(header);
            } else {
                // Other representations
                i += 1;
                const name = try self.decodeString(data, &i);
                const value = try self.decodeString(data, &i);
                try headers.append(Header{ .name = name, .value = value });
            }
        }
        
        return headers.toOwnedSlice();
    }
    
    fn decodeInteger(self: *HpackDecoder, data: []const u8, i: *usize, prefix_bits: u3) !u32 {
        _ = self;
        const max_prefix = (@as(u32, 1) << prefix_bits) - 1;
        const first_byte = data[i.*] & @as(u8, @intCast(max_prefix));
        i.* += 1;
        
        if (first_byte < max_prefix) {
            return first_byte;
        }
        
        var value: u32 = max_prefix;
        var shift: u5 = 0;
        
        while (i.* < data.len) {
            const byte = data[i.*];
            i.* += 1;
            
            value += @as(u32, byte & 0x7F) << shift;
            
            if (byte & 0x80 == 0) {
                return value;
            }
            
            shift += 7;
        }
        
        return error.InvalidInteger;
    }
    
    fn decodeString(self: *HpackDecoder, data: []const u8, i: *usize) ![]const u8 {
        const length = try self.decodeInteger(data, i, 7);
        
        if (i.* + length > data.len) {
            return error.InvalidString;
        }
        
        const str = data[i.* .. i.* + length];
        i.* += length;
        
        return str;
    }
    
    fn getIndexedHeader(self: *HpackDecoder, index: u32) !Header {
        // Static table entries
        const static_headers = [_]Header{
            .{ .name = ":authority", .value = "" },
            .{ .name = ":method", .value = "GET" },
            .{ .name = ":method", .value = "POST" },
            .{ .name = ":path", .value = "/" },
            .{ .name = ":path", .value = "/index.html" },
            .{ .name = ":scheme", .value = "http" },
            .{ .name = ":scheme", .value = "https" },
            .{ .name = ":status", .value = "200" },
        };
        
        if (index > 0 and index <= static_headers.len) {
            return static_headers[index - 1];
        }
        
        // Dynamic table
        const dyn_index = index - static_headers.len - 1;
        if (dyn_index < self.dynamic_table.items.len) {
            return self.dynamic_table.items[dyn_index];
        }
        
        return error.InvalidIndex;
    }
    
    fn addToDynamicTable(self: *HpackDecoder, header: Header) !void {
        const entry_size = header.name.len + header.value.len + 32;
        
        while (self.current_table_size + entry_size > self.max_dynamic_table_size and
               self.dynamic_table.items.len > 0) {
            const removed = self.dynamic_table.orderedRemove(self.dynamic_table.items.len - 1);
            self.current_table_size -= removed.name.len + removed.value.len + 32;
        }
        
        try self.dynamic_table.insert(0, header);
        self.current_table_size += entry_size;
    }
};