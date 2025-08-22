const std = @import("std");
const net = std.net;
const crypto = std.crypto;
const hpack = @import("hpack.zig");

// gRPC client implementation for Hedera network communication
pub const GrpcClient = struct {
    allocator: std.mem.Allocator,
    address: net.Address,
    stream: ?net.Stream = null,
    request_id: u32 = 0,
    
    // HTTP/2 connection state
    connection_preface_sent: bool = false,
    settings_sent: bool = false,
    settings_received: bool = false,
    stream_id: u32 = 1,
    
    // HTTP/2 settings
    header_table_size: u32 = 4096,
    max_concurrent_streams: u32 = 100,
    initial_window_size: u32 = 65535,
    max_frame_size: u32 = 16384,
    max_header_list_size: u32 = 8192,
    
    pub fn init(allocator: std.mem.Allocator, host: []const u8, port: u16) !GrpcClient {
        const address = try net.Address.parseIp(host, port);
        
        return GrpcClient{
            .allocator = allocator,
            .address = address,
        };
    }
    
    pub fn deinit(self: *GrpcClient) void {
        if (self.stream) |stream| {
            stream.close();
        }
    }
    
    // Connect to gRPC server
    pub fn connect(self: *GrpcClient) !void {
        self.stream = try net.tcpConnectToAddress(self.address);
        
        // Send HTTP/2 connection preface
        try self.sendConnectionPreface();
        
        // Send SETTINGS frame
        try self.sendSettings();
        
        // Wait for server SETTINGS
        try self.receiveSettings();
    }
    
    // Send HTTP/2 connection preface
    fn sendConnectionPreface(self: *GrpcClient) !void {
        if (self.stream == null) return error.NotConnected;
        
        const preface = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n";
        _ = try self.stream.?.write(preface);
        self.connection_preface_sent = true;
    }
    
    // Send SETTINGS frame
    fn sendSettings(self: *GrpcClient) !void {
        if (self.stream == null) return error.NotConnected;
        
        var frame = Http2Frame{
            .length = 0,
            .frame_type = .SETTINGS,
            .flags = 0,
            .stream_id = 0,
        };
        
        // Add settings parameters
        var settings = std.ArrayList(u8).init(self.allocator);
        defer settings.deinit();
        
        // SETTINGS_HEADER_TABLE_SIZE
        try settings.appendSlice(&[_]u8{ 0x00, 0x01 });
        try writeU32(&settings, self.header_table_size);
        
        // SETTINGS_MAX_CONCURRENT_STREAMS
        try settings.appendSlice(&[_]u8{ 0x00, 0x03 });
        try writeU32(&settings, self.max_concurrent_streams);
        
        // SETTINGS_INITIAL_WINDOW_SIZE
        try settings.appendSlice(&[_]u8{ 0x00, 0x04 });
        try writeU32(&settings, self.initial_window_size);
        
        // SETTINGS_MAX_FRAME_SIZE
        try settings.appendSlice(&[_]u8{ 0x00, 0x05 });
        try writeU32(&settings, self.max_frame_size);
        
        frame.length = @intCast(settings.items.len);
        
        try self.writeFrame(frame, settings.items);
        self.settings_sent = true;
    }
    
    // Receive SETTINGS frame
    fn receiveSettings(self: *GrpcClient) !void {
        if (self.stream == null) return error.NotConnected;
        
        const frame = try self.readFrame();
        if (frame.frame_type != .SETTINGS) {
            return error.UnexpectedFrame;
        }
        
        // Send SETTINGS ACK
        const ack_frame = Http2Frame{
            .length = 0,
            .frame_type = .SETTINGS,
            .flags = 0x01, // ACK flag
            .stream_id = 0,
        };
        try self.writeFrame(ack_frame, &[_]u8{});
        
        self.settings_received = true;
    }
    
    // Make unary RPC call
    pub fn unaryCall(
        self: *GrpcClient,
        service: []const u8,
        method: []const u8,
        request: []const u8,
    ) ![]u8 {
        if (!self.connection_preface_sent or !self.settings_sent or !self.settings_received) {
            return error.NotInitialized;
        }
        
        const stream_id = self.getNextStreamId();
        
        // Send HEADERS frame
        try self.sendHeaders(stream_id, service, method, request.len);
        
        // Send DATA frame with request
        try self.sendData(stream_id, request, true);
        
        // Receive response HEADERS
        _ = try self.receiveHeaders(stream_id);
        
        // Receive response DATA
        const response = try self.receiveData(stream_id);
        
        return response;
    }
    
    // Send HEADERS frame
    fn sendHeaders(
        self: *GrpcClient,
        stream_id: u32,
        service: []const u8,
        method: []const u8,
        content_length: usize,
    ) !void {
        var headers = std.ArrayList(u8).init(self.allocator);
        defer headers.deinit();
        
        // Encode headers using HPACK
        var hpack_encoder = HpackEncoder.init(self.allocator);
        defer hpack_encoder.deinit();
        
        // :method = POST
        try hpack_encoder.encodeHeader(&headers, ":method", "POST");
        
        // :scheme = http
        try hpack_encoder.encodeHeader(&headers, ":scheme", "http");
        
        // :path = /service/method
        const path = try std.fmt.allocPrint(self.allocator, "/{s}/{s}", .{ service, method });
        defer self.allocator.free(path);
        try hpack_encoder.encodeHeader(&headers, ":path", path);
        
        // :authority = host
        try hpack_encoder.encodeHeader(&headers, ":authority", "hedera-node");
        
        // content-type = application/grpc+proto
        try hpack_encoder.encodeHeader(&headers, "content-type", "application/grpc+proto");
        
        // content-length
        const content_length_str = try std.fmt.allocPrint(self.allocator, "{d}", .{content_length});
        defer self.allocator.free(content_length_str);
        try hpack_encoder.encodeHeader(&headers, "content-length", content_length_str);
        
        // te = trailers
        try hpack_encoder.encodeHeader(&headers, "te", "trailers");
        
        const frame = Http2Frame{
            .length = @intCast(headers.items.len),
            .frame_type = .HEADERS,
            .flags = 0x04, // END_HEADERS
            .stream_id = stream_id,
        };
        
        try self.writeFrame(frame, headers.items);
    }
    
    // Send DATA frame
    fn sendData(self: *GrpcClient, stream_id: u32, data: []const u8, end_stream: bool) !void {
        // gRPC message format: [compression_flag(1) | message_length(4) | message]
        var grpc_message = std.ArrayList(u8).init(self.allocator);
        defer grpc_message.deinit();
        
        // Compression flag (0 = no compression)
        try grpc_message.append(0);
        
        // Message length (big-endian)
        try writeU32BE(&grpc_message, @intCast(data.len));
        
        // Message data
        try grpc_message.appendSlice(data);
        
        const frame = Http2Frame{
            .length = @intCast(grpc_message.items.len),
            .frame_type = .DATA,
            .flags = if (end_stream) 0x01 else 0x00,
            .stream_id = stream_id,
        };
        
        try self.writeFrame(frame, grpc_message.items);
    }
    
    // Receive HEADERS frame
    fn receiveHeaders(self: *GrpcClient, expected_stream_id: u32) !void {
        const frame = try self.readFrame();
        
        if (frame.frame_type != .HEADERS) {
            return error.UnexpectedFrame;
        }
        
        if (frame.stream_id != expected_stream_id) {
            return error.UnexpectedStreamId;
        }
        
        // Read header block fragment
        const headers_data = try self.allocator.alloc(u8, frame.length);
        defer self.allocator.free(headers_data);
        _ = try self.stream.?.read(headers_data);
        
        // Decode headers using HPACK
        var hpack_encoder = HpackEncoder.init(self.allocator); // Use encoder for compatibility - proper decoder would be more complex
        defer hpack_encoder.deinit();
        const headers = try hpack_encoder.decodeHeaders(headers_data);
        defer headers.deinit();
        
        // Validate response headers
        for (headers.items) |header| {
            if (std.mem.eql(u8, header.name, ":status")) {
                if (!std.mem.eql(u8, header.value, "200")) {
                    return error.GrpcError;
                }
            }
        }
    }
    
    // Receive DATA frame
    fn receiveData(self: *GrpcClient, expected_stream_id: u32) ![]u8 {
        const frame = try self.readFrame();
        
        if (frame.frame_type != .DATA) {
            return error.UnexpectedFrame;
        }
        
        if (frame.stream_id != expected_stream_id) {
            return error.UnexpectedStreamId;
        }
        
        // Read data
        const data = try self.allocator.alloc(u8, frame.length);
        _ = try self.stream.?.read(data);
        
        // Parse gRPC message format
        if (data.len < 5) {
            self.allocator.free(data);
            return error.InvalidGrpcMessage;
        }
        
        const compression_flag = data[0];
        _ = compression_flag; // Handle compression if needed
        
        const message_length = readU32BE(data[1..5]);
        
        if (data.len < 5 + message_length) {
            self.allocator.free(data);
            return error.IncompleteGrpcMessage;
        }
        
        // Extract message
        const message = try self.allocator.alloc(u8, message_length);
        @memcpy(message, data[5..5 + message_length]);
        
        self.allocator.free(data);
        return message;
    }
    
    // Write HTTP/2 frame
    fn writeFrame(self: *GrpcClient, frame: Http2Frame, payload: []const u8) !void {
        if (self.stream == null) return error.NotConnected;
        
        var header: [9]u8 = undefined;
        
        // Length (24 bits)
        header[0] = @intCast((frame.length >> 16) & 0xFF);
        header[1] = @intCast((frame.length >> 8) & 0xFF);
        header[2] = @intCast(frame.length & 0xFF);
        
        // Type (8 bits)
        header[3] = @intFromEnum(frame.frame_type);
        
        // Flags (8 bits)
        header[4] = frame.flags;
        
        // Stream ID (32 bits)
        header[5] = @intCast((frame.stream_id >> 24) & 0x7F); // Clear reserved bit
        header[6] = @intCast((frame.stream_id >> 16) & 0xFF);
        header[7] = @intCast((frame.stream_id >> 8) & 0xFF);
        header[8] = @intCast(frame.stream_id & 0xFF);
        
        _ = try self.stream.?.write(&header);
        if (payload.len > 0) {
            _ = try self.stream.?.write(payload);
        }
    }
    
    // Read HTTP/2 frame
    fn readFrame(self: *GrpcClient) !Http2Frame {
        if (self.stream == null) return error.NotConnected;
        
        var header: [9]u8 = undefined;
        _ = try self.stream.?.read(&header);
        
        const length = (@as(u24, header[0]) << 16) | (@as(u24, header[1]) << 8) | header[2];
        const frame_type = @as(FrameType, @enumFromInt(header[3]));
        const flags = header[4];
        const stream_id = (@as(u32, header[5] & 0x7F) << 24) |
                         (@as(u32, header[6]) << 16) |
                         (@as(u32, header[7]) << 8) |
                         header[8];
        
        return Http2Frame{
            .length = length,
            .frame_type = frame_type,
            .flags = flags,
            .stream_id = stream_id,
        };
    }
    
    // Get next stream ID
    fn getNextStreamId(self: *GrpcClient) u32 {
        const id = self.stream_id;
        self.stream_id += 2; // Client uses odd stream IDs
        return id;
    }
    
    // Helper functions
    fn writeU32(list: *std.ArrayList(u8), value: u32) !void {
        try list.appendSlice(&[_]u8{
            @intCast((value >> 24) & 0xFF),
            @intCast((value >> 16) & 0xFF),
            @intCast((value >> 8) & 0xFF),
            @intCast(value & 0xFF),
        });
    }
    
    fn writeU32BE(list: *std.ArrayList(u8), value: u32) !void {
        try list.appendSlice(&[_]u8{
            @intCast((value >> 24) & 0xFF),
            @intCast((value >> 16) & 0xFF),
            @intCast((value >> 8) & 0xFF),
            @intCast(value & 0xFF),
        });
    }
    
    fn readU32BE(data: []const u8) u32 {
        return (@as(u32, data[0]) << 24) |
               (@as(u32, data[1]) << 16) |
               (@as(u32, data[2]) << 8) |
               data[3];
    }
};

// HTTP/2 frame structure
const Http2Frame = struct {
    length: u24,
    frame_type: FrameType,
    flags: u8,
    stream_id: u32,
};

// HTTP/2 frame types
const FrameType = enum(u8) {
    DATA = 0x0,
    HEADERS = 0x1,
    PRIORITY = 0x2,
    RST_STREAM = 0x3,
    SETTINGS = 0x4,
    PUSH_PROMISE = 0x5,
    PING = 0x6,
    GOAWAY = 0x7,
    WINDOW_UPDATE = 0x8,
    CONTINUATION = 0x9,
};

// HPACK constants and types
const STATIC_TABLE_SIZE = 61; // RFC 7541 static table has 61 entries

const HeaderField = struct {
    name: []const u8,
    value: []const u8,
};

// HPACK encoder for HTTP/2 header compression
const HpackEncoder = struct {
    allocator: std.mem.Allocator,
    dynamic_table: std.ArrayList(HeaderField),
    
    pub fn init(allocator: std.mem.Allocator) HpackEncoder {
        return HpackEncoder{
            .allocator = allocator,
            .dynamic_table = std.ArrayList(HeaderField).init(allocator),
        };
    }
    
    pub fn deinit(self: *HpackEncoder) void {
        self.dynamic_table.deinit();
    }
    
    // Decode headers using complete HPACK implementation
    pub fn decodeHeaders(self: *HpackEncoder, data: []const u8) !std.ArrayList(HeaderField) {
        var decoder = hpack.HPACK.Decoder.init(self.allocator);
        defer decoder.deinit();
        
        var headers = std.ArrayList(hpack.HPACK.HeaderField).init(self.allocator);
        errdefer headers.deinit();
        
        headers = try decoder.decode(data);
        
        // Convert HPACK headers to our HeaderField format
        var result = std.ArrayList(HeaderField).init(self.allocator);
        errdefer result.deinit();
        
        for (headers.items) |header| {
            try result.append(HeaderField{
                .name = try self.allocator.dupe(u8, header.name),
                .value = try self.allocator.dupe(u8, header.value),
            });
        }
        
        headers.deinit();
        return result;
    }
    
    // Find static table index for name/value pair
    fn findStaticIndex(self: *HpackEncoder, name: []const u8, value: []const u8) ?usize {
        _ = self;
        // Check against RFC 7541 static table
        for (hpack.HPACK.STATIC_TABLE, 0..) |entry, i| {
            if (i == 0) continue; // Skip index 0
            if (std.mem.eql(u8, entry.name, name) and std.mem.eql(u8, entry.value, value)) {
                return i;
            }
        }
        return null;
    }
    
    // Find static table index for name only
    fn findStaticNameIndex(self: *HpackEncoder, name: []const u8) ?usize {
        _ = self;
        // Check against RFC 7541 static table
        for (hpack.HPACK.STATIC_TABLE, 0..) |entry, i| {
            if (i == 0) continue; // Skip index 0
            if (std.mem.eql(u8, entry.name, name)) {
                return i;
            }
        }
        return null;
    }
    
    // Find dynamic table index
    fn findDynamicIndex(self: *HpackEncoder, name: []const u8, value: []const u8) ?usize {
        for (self.dynamic_table.items, 0..) |header, i| {
            if (std.mem.eql(u8, header.name, name) and std.mem.eql(u8, header.value, value)) {
                return i;
            }
        }
        return null;
    }
    
    pub fn encodeHeader(self: *HpackEncoder, output: *std.ArrayList(u8), name: []const u8, value: []const u8) !void {
        // Check static table for indexed header
        const static_index = self.findStaticIndex(name, value);
        if (static_index) |index| {
            // Indexed header field
            try self.encodeInteger(output, index, 7);
            output.items[output.items.len - 1] |= 0x80;
            return;
        }
        
        // Check dynamic table
        const dynamic_index = self.findDynamicIndex(name, value);
        if (dynamic_index) |index| {
            const actual_index = index + STATIC_TABLE_SIZE;
            try self.encodeInteger(output, actual_index, 7);
            output.items[output.items.len - 1] |= 0x80;
            return;
        }
        
        // Literal header field with incremental indexing
        const name_index = self.findStaticNameIndex(name);
        if (name_index) |index| {
            try self.encodeInteger(output, index, 6);
            output.items[output.items.len - 1] |= 0x40;
        } else {
            try output.append(0x40); // Literal with incremental indexing
            
            // Encode name length
            try self.encodeInteger(output, name.len, 7);
            try output.appendSlice(name);
        }
        
        // Encode value length
        try self.encodeInteger(output, value.len, 7);
        try output.appendSlice(value);
    }
    
    fn encodeInteger(self: *HpackEncoder, output: *std.ArrayList(u8), value: usize, prefix_bits: u8) !void {
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
};