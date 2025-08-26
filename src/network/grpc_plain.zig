const std = @import("std");
const net = std.net;
const Node = @import("node.zig").Node;
const AccountId = @import("../core/id.zig").AccountId;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;

/// Plain gRPC implementation for Hedera blockchain
pub const GrpcPlainConnection = struct {
    allocator: std.mem.Allocator,
    node: Node,
    address: net.Address,
    stream: ?net.Stream = null,
    /// HTTP/2 connection state
    next_stream_id: u32 = 1,
    settings_received: bool = false,
    window_size: u32 = 65535,
    max_frame_size: u32 = 16384,
    last_error: ?[]const u8 = null,
    
    pub fn init(allocator: std.mem.Allocator, node: Node) !GrpcPlainConnection {
        const conn = GrpcPlainConnection{
            .allocator = allocator,
            .node = node,
            .address = node.address,
        };
        
        // Don't connect immediately - let it be lazy
        return conn;
    }
    
    /// Establish plain connection to Hedera node
    pub fn connect(self: *GrpcPlainConnection) !void {
        if (self.stream != null) return;
        
        std.debug.print("Connecting to {}\n", .{self.node.address});
        
        // Try to connect with timeout
        const start_time = std.time.milliTimestamp();
        
        self.stream = net.tcpConnectToAddress(self.address) catch |err| {
            const elapsed = std.time.milliTimestamp() - start_time;
            std.debug.print("Failed to connect to {} after {d}ms: {any}\n", .{ 
                self.node.address, 
                elapsed,
                err 
            });
            self.last_error = "Connection failed";
            return err;
        };
        
        const elapsed_connect = std.time.milliTimestamp() - start_time;
        std.debug.print("Connected to node in {d}ms\n", .{elapsed_connect});
        
        const stream = self.stream.?;
        errdefer {
            stream.close();
            self.stream = null;
        }
        
        // Send HTTP/2 connection preface for gRPC
        const preface = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n";
        _ = try stream.write(preface);
        std.debug.print("Sent HTTP/2 preface\n", .{});
        
        // Send initial SETTINGS frame
        const settings = [_]u8{
            // Frame header (9 bytes)
            0, 0, 18, // Length: 18 bytes (3 settings * 6 bytes each)
            0x04, // Type: SETTINGS
            0, // Flags: none
            0, 0, 0, 0, // Stream ID: 0
            
            // Settings payload
            // ENABLE_PUSH = 0
            0, 0x02, // ID: ENABLE_PUSH
            0, 0, 0, 0, // Value: 0
            
            // INITIAL_WINDOW_SIZE = 65535
            0, 0x04, // ID: INITIAL_WINDOW_SIZE
            0, 0, 0xFF, 0xFF, // Value: 65535
            
            // MAX_FRAME_SIZE = 16384
            0, 0x05, // ID: MAX_FRAME_SIZE
            0, 0, 0x40, 0x00, // Value: 16384
        };
        
        _ = try stream.write(&settings);
        std.debug.print("Sent SETTINGS frame\n", .{});
        
        // Wait for SETTINGS frame with timeout
        var settings_buffer: [1024]u8 = undefined;
        const read_start = std.time.milliTimestamp();
        
        const settings_len = stream.read(&settings_buffer) catch |err| {
            const elapsed = std.time.milliTimestamp() - read_start;
            std.debug.print("Failed to read SETTINGS after {d}ms: {any}\n", .{ elapsed, err });
            self.last_error = "SETTINGS timeout";
            return err;
        };
        
        if (settings_len > 0) {
            std.debug.print("Received {d} bytes (expecting SETTINGS frame)\n", .{settings_len});
            
            // Parse frame header
            if (settings_len >= 9) {
                const frame_length = (@as(u32, settings_buffer[0]) << 16) |
                                   (@as(u32, settings_buffer[1]) << 8) |
                                   @as(u32, settings_buffer[2]);
                const frame_type = settings_buffer[3];
                const flags = settings_buffer[4];
                
                std.debug.print("Frame: type={d}, length={d}, flags={d}\n", .{ frame_type, frame_length, flags });
                
                if (frame_type == 0x04) { // SETTINGS frame
                    self.settings_received = true;
                    
                    // Send SETTINGS ACK
                    const settings_ack = [_]u8{
                        0, 0, 0, // Length: 0
                        0x04, // Type: SETTINGS
                        0x01, // Flags: ACK
                        0, 0, 0, 0, // Stream ID: 0
                    };
                    _ = try stream.write(&settings_ack);
                    std.debug.print("Sent SETTINGS ACK\n", .{});
                }
            }
        } else {
            std.debug.print("No data received for SETTINGS\n", .{});
            return error.NoDataReceived;
        }
    }
    
    pub fn deinit(self: *GrpcPlainConnection) void {
        // Send GOAWAY frame for clean HTTP/2 shutdown
        if (self.stream) |stream| {
            const goaway = [_]u8{
                0, 0, 8, // Length: 8 bytes
                0x07, // Type: GOAWAY
                0, // Flags: none
                0, 0, 0, 0, // Stream ID: 0
                
                // Payload
                0, 0, 0, 0, // Last stream ID: 0
                0, 0, 0, 0, // Error code: NO_ERROR
            };
            
            _ = stream.write(&goaway) catch {};
            stream.close();
        }
        
        if (self.last_error) |err| {
            self.allocator.free(err);
        }
    }
    
    fn getNextStreamId(self: *GrpcPlainConnection) u32 {
        const id = self.next_stream_id;
        self.next_stream_id += 2; // Client-initiated streams are odd
        return id;
    }
    
    /// Send a gRPC request over HTTP/2 (plain)
    pub fn call(
        self: *GrpcPlainConnection,
        service: []const u8,
        method: []const u8,
        request_bytes: []const u8,
    ) ![]u8 {
        try self.connect();
        
        const stream = self.stream orelse return error.NotConnected;
        
        // Ensure we've completed the HTTP/2 handshake
        if (!self.settings_received) {
            std.debug.print("Error: Settings not received\n", .{});
            return error.ProtocolError;
        }
        
        const stream_id = self.getNextStreamId();
        std.debug.print("Starting gRPC call {s}/{s} on stream {d}\n", .{ service, method, stream_id });
        
        // Build HTTP/2 HEADERS frame for gRPC
        const path = try std.fmt.allocPrint(self.allocator, "/{s}/{s}", .{ service, method });
        defer self.allocator.free(path);
        
        // Build HPACK-encoded headers
        var headers_buf: [512]u8 = undefined;
        var headers_len: usize = 0;
        
        // :method = POST (static table index 3)
        headers_buf[headers_len] = 0x83;
        headers_len += 1;
        
        // :scheme = http (for plain gRPC)
        headers_buf[headers_len] = 0x86; // Static table index 6
        headers_len += 1;
        
        // :path (literal with incremental indexing)
        headers_buf[headers_len] = 0x44; // Literal indexed, index 4
        headers_len += 1;
        headers_buf[headers_len] = @intCast(path.len);
        headers_len += 1;
        @memcpy(headers_buf[headers_len..headers_len + path.len], path);
        headers_len += path.len;
        
        // :authority (use node address)
        headers_buf[headers_len] = 0x41; // Literal indexed, index 1
        headers_len += 1;
        const authority = if (self.node.hostname) |hostname|
            try std.fmt.allocPrint(self.allocator, "{s}", .{hostname})
        else
            try std.fmt.allocPrint(self.allocator, "{}", .{self.node.address});
        defer self.allocator.free(authority);
        headers_buf[headers_len] = @intCast(authority.len);
        headers_len += 1;
        @memcpy(headers_buf[headers_len..headers_len + authority.len], authority);
        headers_len += authority.len;
        
        // content-type: application/grpc
        headers_buf[headers_len] = 0x40; // Literal without indexing
        headers_len += 1;
        headers_buf[headers_len] = 12; // "content-type" length
        headers_len += 1;
        @memcpy(headers_buf[headers_len..headers_len + 12], "content-type");
        headers_len += 12;
        headers_buf[headers_len] = 16; // "application/grpc" length
        headers_len += 1;
        @memcpy(headers_buf[headers_len..headers_len + 16], "application/grpc");
        headers_len += 16;
        
        // te: trailers
        headers_buf[headers_len] = 0x40; // Literal without indexing
        headers_len += 1;
        headers_buf[headers_len] = 2; // "te" length
        headers_len += 1;
        @memcpy(headers_buf[headers_len..headers_len + 2], "te");
        headers_len += 2;
        headers_buf[headers_len] = 8; // "trailers" length
        headers_len += 1;
        @memcpy(headers_buf[headers_len..headers_len + 8], "trailers");
        headers_len += 8;
        
        // grpc-timeout: 10S
        headers_buf[headers_len] = 0x40; // Literal without indexing
        headers_len += 1;
        headers_buf[headers_len] = 12; // "grpc-timeout" length
        headers_len += 1;
        @memcpy(headers_buf[headers_len..headers_len + 12], "grpc-timeout");
        headers_len += 12;
        headers_buf[headers_len] = 3; // "10S" length
        headers_len += 1;
        @memcpy(headers_buf[headers_len..headers_len + 3], "10S");
        headers_len += 3;
        
        // Send HEADERS frame
        var headers_frame: [9 + 512]u8 = undefined;
        headers_frame[0] = @intCast((headers_len >> 16) & 0xFF);
        headers_frame[1] = @intCast((headers_len >> 8) & 0xFF);
        headers_frame[2] = @intCast(headers_len & 0xFF);
        headers_frame[3] = 0x01; // Type: HEADERS
        headers_frame[4] = 0x04; // Flags: END_HEADERS
        // Stream ID (big-endian)
        headers_frame[5] = @intCast((stream_id >> 24) & 0xFF);
        headers_frame[6] = @intCast((stream_id >> 16) & 0xFF);
        headers_frame[7] = @intCast((stream_id >> 8) & 0xFF);
        headers_frame[8] = @intCast(stream_id & 0xFF);
        @memcpy(headers_frame[9..9 + headers_len], headers_buf[0..headers_len]);
        
        _ = try stream.write(headers_frame[0..9 + headers_len]);
        std.debug.print("Sent HEADERS frame ({d} bytes)\n", .{9 + headers_len});
        
        // Send DATA frame with gRPC message
        const grpc_len = 5 + request_bytes.len;
        var data_frame = try self.allocator.alloc(u8, 9 + grpc_len);
        defer self.allocator.free(data_frame);
        
        // HTTP/2 DATA frame header
        data_frame[0] = @intCast((grpc_len >> 16) & 0xFF);
        data_frame[1] = @intCast((grpc_len >> 8) & 0xFF);
        data_frame[2] = @intCast(grpc_len & 0xFF);
        data_frame[3] = 0x00; // Type: DATA
        data_frame[4] = 0x01; // Flags: END_STREAM
        // Stream ID (big-endian)
        data_frame[5] = @intCast((stream_id >> 24) & 0xFF);
        data_frame[6] = @intCast((stream_id >> 16) & 0xFF);
        data_frame[7] = @intCast((stream_id >> 8) & 0xFF);
        data_frame[8] = @intCast(stream_id & 0xFF);
        
        // gRPC message framing
        data_frame[9] = 0; // No compression
        const msg_len = @as(u32, @intCast(request_bytes.len));
        data_frame[10] = @intCast((msg_len >> 24) & 0xFF);
        data_frame[11] = @intCast((msg_len >> 16) & 0xFF);
        data_frame[12] = @intCast((msg_len >> 8) & 0xFF);
        data_frame[13] = @intCast(msg_len & 0xFF);
        @memcpy(data_frame[14..], request_bytes);
        
        _ = try stream.write(data_frame);
        std.debug.print("Sent DATA frame ({d} bytes)\n", .{data_frame.len});
        
        // Read response frames with timeout
        var response_data = std.ArrayList(u8).init(self.allocator);
        errdefer response_data.deinit();
        
        const start_time = std.time.milliTimestamp();
        const timeout_ms: i64 = 10000; // 10 second timeout;
        
        // Read until we get response
        var got_response = false;
        var retry_count: u32 = 0;
        const max_retries = 100;
        
        while (!got_response and retry_count < max_retries) {
            retry_count += 1;
            
            const elapsed = std.time.milliTimestamp() - start_time;
            if (elapsed > timeout_ms) {
                std.debug.print("Response timeout after {d}ms\n", .{elapsed});
                return error.Timeout;
            }
            
            var frame_header: [9]u8 = undefined;
            const bytes_read = stream.read(&frame_header) catch |err| {
                std.debug.print("Read error: {any}\n", .{err});
                return err;
            };
            
            if (bytes_read < 9) {
                if (bytes_read == 0) {
                    std.debug.print("Connection closed by peer\n", .{});
                    return error.ConnectionClosed;
                }
                // Partial read, try to read remaining
                var offset = bytes_read;
                while (offset < 9) {
                    const n = try stream.read(frame_header[offset..]);
                    if (n == 0) return error.ConnectionClosed;
                    offset += n;
                }
            }
            
            const length = (@as(u32, frame_header[0]) << 16) |
                          (@as(u32, frame_header[1]) << 8) |
                          @as(u32, frame_header[2]);
            const frame_type = frame_header[3];
            const flags = frame_header[4];
            const frame_stream_id = (@as(u32, frame_header[5]) << 24) |
                                   (@as(u32, frame_header[6]) << 16) |
                                   (@as(u32, frame_header[7]) << 8) |
                                   @as(u32, frame_header[8]);
            
            std.debug.print("Frame: type={d}, length={d}, flags={x}, stream={d}\n", .{ 
                frame_type, length, flags, frame_stream_id 
            });
            
            if (length > 0) {
                var payload = try self.allocator.alloc(u8, length);
                defer self.allocator.free(payload);
                _ = try stream.readAll(payload);
                
                if (frame_type == 0x00 and frame_stream_id == stream_id) { // DATA frame for our stream
                    std.debug.print("Received DATA frame for our stream\n", .{});
                    // Extract gRPC message
                    if (payload.len >= 5) {
                        const grpc_msg_len = (@as(u32, payload[1]) << 24) |
                                           (@as(u32, payload[2]) << 16) |
                                           (@as(u32, payload[3]) << 8) |
                                           @as(u32, payload[4]);
                        if (5 + grpc_msg_len <= payload.len) {
                            try response_data.appendSlice(payload[5..5 + grpc_msg_len]);
                            std.debug.print("Extracted gRPC message ({d} bytes)\n", .{grpc_msg_len});
                        }
                    }
                    if (flags & 0x01 != 0) { // END_STREAM
                        got_response = true;
                    }
                } else if (frame_type == 0x01 and frame_stream_id == stream_id) { // HEADERS frame for our stream
                    std.debug.print("Received HEADERS frame for our stream\n", .{});
                    // Parse headers to check for grpc-status
                    std.debug.print("HEADERS payload ({d} bytes): ", .{payload.len});
                    for (payload[0..@min(payload.len, 50)]) |byte| {
                        std.debug.print("{x:0>2} ", .{byte});
                    }
                    std.debug.print("\n", .{});
                    
                    if (flags & 0x01 != 0) { // END_STREAM
                        // Headers with END_STREAM but no DATA usually means an error
                        std.debug.print("WARNING: Received HEADERS with END_STREAM but no DATA frame\n", .{});
                        got_response = true;
                    }
                } else if (frame_type == 0x03 and frame_stream_id == stream_id) { // RST_STREAM
                    const error_code = (@as(u32, payload[0]) << 24) |
                                     (@as(u32, payload[1]) << 16) |
                                     (@as(u32, payload[2]) << 8) |
                                     @as(u32, payload[3]);
                    std.debug.print("Stream reset with error code: {d}\n", .{error_code});
                    return error.StreamReset;
                } else if (frame_type == 0x07) { // GOAWAY
                    const last_stream = (@as(u32, payload[0]) << 24) |
                                      (@as(u32, payload[1]) << 16) |
                                      (@as(u32, payload[2]) << 8) |
                                      @as(u32, payload[3]);
                    const error_code = (@as(u32, payload[4]) << 24) |
                                     (@as(u32, payload[5]) << 16) |
                                     (@as(u32, payload[6]) << 8) |
                                     @as(u32, payload[7]);
                    std.debug.print("GOAWAY: last_stream={d}, error={d}\n", .{ last_stream, error_code });
                    return error.ConnectionClosed;
                } else if (frame_type == 0x04) { // SETTINGS frame
                    // Send ACK if not already ACK
                    if (flags & 0x01 == 0) {
                        const ack = [_]u8{
                            0, 0, 0, // Length: 0
                            0x04, // Type: SETTINGS
                            0x01, // Flags: ACK
                            0, 0, 0, 0, // Stream ID: 0
                        };
                        _ = try stream.write(&ack);
                        std.debug.print("Sent SETTINGS ACK\n", .{});
                    }
                } else if (frame_type == 0x08) { // WINDOW_UPDATE
                    if (payload.len >= 4) {
                        const increment = (@as(u32, payload[0]) << 24) |
                                        (@as(u32, payload[1]) << 16) |
                                        (@as(u32, payload[2]) << 8) |
                                        @as(u32, payload[3]);
                        std.debug.print("WINDOW_UPDATE: increment={d} for stream={d}\n", .{ increment, frame_stream_id });
                    }
                } else if (frame_type == 0x06) { // PING
                    // Respond to PING with ACK
                    if (flags & 0x01 == 0) { // Not ACK, so respond
                        var ping_ack: [17]u8 = undefined;
                        ping_ack[0] = 0;
                        ping_ack[1] = 0;
                        ping_ack[2] = 8; // Length
                        ping_ack[3] = 0x06; // Type: PING
                        ping_ack[4] = 0x01; // Flags: ACK
                        ping_ack[5] = 0;
                        ping_ack[6] = 0;
                        ping_ack[7] = 0;
                        ping_ack[8] = 0; // Stream ID: 0
                        @memcpy(ping_ack[9..17], payload[0..8]); // Echo the ping data
                        _ = try stream.write(&ping_ack);
                        std.debug.print("Sent PING ACK\n", .{});
                    }
                }
            } else if (frame_type == 0x04) { // Empty SETTINGS frame
                // Send ACK if not already ACK
                if (flags & 0x01 == 0) {
                    const ack = [_]u8{
                        0, 0, 0, // Length: 0
                        0x04, // Type: SETTINGS
                        0x01, // Flags: ACK
                        0, 0, 0, 0, // Stream ID: 0
                    };
                    _ = try stream.write(&ack);
                    std.debug.print("Sent SETTINGS ACK\n", .{});
                }
            }
        }
        
        if (!got_response) {
            std.debug.print("No response received after {d} attempts\n", .{retry_count});
            return error.Timeout;
        }
        
        return response_data.toOwnedSlice();
    }
    
    /// Execute a Hedera transaction
    pub fn executeTransaction(self: *GrpcPlainConnection, transaction_bytes: []const u8) ![]u8 {
        // For transactions, use the CryptoService
        return try self.call(
            "proto.CryptoService",
            "createAccount",
            transaction_bytes,
        );
    }
    
    /// Execute a Hedera query
    pub fn executeQuery(self: *GrpcPlainConnection, query_bytes: []const u8) ![]u8 {
        // For queries, use appropriate service
        return try self.call(
            "proto.CryptoService",
            "getAccountInfo",
            query_bytes,
        );
    }
};

/// Connection pool for managing plain gRPC connections to Hedera nodes
pub const GrpcPlainPool = struct {
    allocator: std.mem.Allocator,
    connections: std.AutoHashMap(AccountId, *GrpcPlainConnection),
    mutex: std.Thread.Mutex,
    
    pub fn init(allocator: std.mem.Allocator) GrpcPlainPool {
        return .{
            .allocator = allocator,
            .connections = std.AutoHashMap(AccountId, *GrpcPlainConnection).init(allocator),
            .mutex = .{},
        };
    }
    
    pub fn deinit(self: *GrpcPlainPool) void {
        var iter = self.connections.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.connections.deinit();
    }
    
    pub fn getConnection(self: *GrpcPlainPool, node: *Node) !*GrpcPlainConnection {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const result = try self.connections.getOrPut(node.account_id);
        if (!result.found_existing) {
            const conn = try self.allocator.create(GrpcPlainConnection);
            conn.* = try GrpcPlainConnection.init(self.allocator, node.*);
            result.value_ptr.* = conn;
        }
        
        return result.value_ptr.*;
    }
    
    pub fn releaseConnection(self: *GrpcPlainPool, node: *Node, conn: *GrpcPlainConnection) void {
        _ = self;
        _ = node;
        _ = conn;
        // Connection stays in pool for reuse
    }
};