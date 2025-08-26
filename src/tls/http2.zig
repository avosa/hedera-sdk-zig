const std = @import("std");
const tls = @import("tls_simple.zig");

// HTTP/2 Constants
pub const CONNECTION_PREFACE = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n";
pub const DEFAULT_WINDOW_SIZE: u32 = 65535;
pub const DEFAULT_MAX_FRAME_SIZE: u32 = 16384;
pub const MAX_FRAME_SIZE: u32 = 16777215; // 2^24 - 1

// HTTP/2 Frame Types
pub const FrameType = enum(u8) {
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
    _,  // Allow unknown frame types
};

// HTTP/2 Frame Flags
pub const FrameFlags = struct {
    pub const DATA_END_STREAM: u8 = 0x1;
    pub const DATA_PADDED: u8 = 0x8;
    
    pub const HEADERS_END_STREAM: u8 = 0x1;
    pub const HEADERS_END_HEADERS: u8 = 0x4;
    pub const HEADERS_PADDED: u8 = 0x8;
    pub const HEADERS_PRIORITY: u8 = 0x20;
    
    pub const SETTINGS_ACK: u8 = 0x1;
    pub const PING_ACK: u8 = 0x1;
};

// HTTP/2 Settings
pub const SettingsId = enum(u16) {
    HEADER_TABLE_SIZE = 0x1,
    ENABLE_PUSH = 0x2,
    MAX_CONCURRENT_STREAMS = 0x3,
    INITIAL_WINDOW_SIZE = 0x4,
    MAX_FRAME_SIZE = 0x5,
    MAX_HEADER_LIST_SIZE = 0x6,
};

pub const Setting = struct {
    id: SettingsId,
    value: u32,
};

// HTTP/2 Error Codes
pub const ErrorCode = enum(u32) {
    NO_ERROR = 0x0,
    PROTOCOL_ERROR = 0x1,
    INTERNAL_ERROR = 0x2,
    FLOW_CONTROL_ERROR = 0x3,
    SETTINGS_TIMEOUT = 0x4,
    STREAM_CLOSED = 0x5,
    FRAME_SIZE_ERROR = 0x6,
    REFUSED_STREAM = 0x7,
    CANCEL = 0x8,
    COMPRESSION_ERROR = 0x9,
    CONNECT_ERROR = 0xa,
    ENHANCE_YOUR_CALM = 0xb,
    INADEQUATE_SECURITY = 0xc,
    HTTP_1_1_REQUIRED = 0xd,
};

// HTTP/2 Frame Structure
pub const Frame = struct {
    length: u24,
    frame_type: FrameType,
    flags: u8,
    stream_id: u31, // 31 bits, high bit is reserved
    payload: []const u8,
    
    pub fn init(frame_type: FrameType, flags: u8, stream_id: u31, payload: []const u8) Frame {
        return Frame{
            .length = @as(u24, @intCast(payload.len)),
            .frame_type = frame_type,
            .flags = flags,
            .stream_id = stream_id,
            .payload = payload,
        };
    }
};

// HTTP/2 Header
pub const Header = struct {
    name: []const u8,
    value: []const u8,
    
    pub fn init(name: []const u8, value: []const u8) Header {
        return Header{ .name = name, .value = value };
    }
};

// Stream State
pub const StreamState = enum {
    idle,
    reserved_local,
    reserved_remote,
    open,
    half_closed_local,
    half_closed_remote,
    closed,
};

// HTTP/2 Stream
pub const Stream = struct {
    id: u31,
    state: StreamState,
    window_size: i32,
    headers: std.ArrayList(Header),
    data: std.ArrayList(u8),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, id: u31) Stream {
        return Stream{
            .id = id,
            .state = .idle,
            .window_size = @intCast(DEFAULT_WINDOW_SIZE),
            .headers = std.ArrayList(Header).init(allocator),
            .data = std.ArrayList(u8).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Stream) void {
        for (self.headers.items) |header| {
            self.allocator.free(header.name);
            self.allocator.free(header.value);
        }
        self.headers.deinit();
        self.data.deinit();
    }
};

// HPACK Context (Simplified)
pub const HpackContext = struct {
    dynamic_table: std.ArrayList(Header),
    table_size: u32,
    max_table_size: u32,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) HpackContext {
        return HpackContext{
            .dynamic_table = std.ArrayList(Header).init(allocator),
            .table_size = 0,
            .max_table_size = 4096,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *HpackContext) void {
        for (self.dynamic_table.items) |header| {
            self.allocator.free(header.name);
            self.allocator.free(header.value);
        }
        self.dynamic_table.deinit();
    }
    
    pub fn encodeHeaders(self: *HpackContext, headers: []const Header) ![]u8 {
        
        // Simplified HPACK encoding - literal header fields without indexing
        var result = std.ArrayList(u8).init(self.allocator);
        
        for (headers) |header| {
            // Literal header field without indexing (0x00)
            try result.append(0x00);
            
            // Name length and name
            try result.append(@as(u8, @intCast(header.name.len)));
            try result.appendSlice(header.name);
            
            // Value length and value  
            try result.append(@as(u8, @intCast(header.value.len)));
            try result.appendSlice(header.value);
        }
        
        return result.toOwnedSlice();
    }
    
    pub fn decodeHeaders(self: *HpackContext, data: []const u8) ![]Header {
        
        // Simplified HPACK decoding - literal header fields without indexing
        var headers = std.ArrayList(Header).init(self.allocator);
        var i: usize = 0;
        
        while (i < data.len) {
            if (data[i] == 0x00) { // Literal header field without indexing
                i += 1;
                if (i >= data.len) break;
                
                // Read name
                const name_len = data[i];
                i += 1;
                if (i + name_len > data.len) break;
                
                const name = try self.allocator.dupe(u8, data[i..i + name_len]);
                i += name_len;
                
                if (i >= data.len) {
                    self.allocator.free(name);
                    break;
                }
                
                // Read value
                const value_len = data[i];
                i += 1;
                if (i + value_len > data.len) {
                    self.allocator.free(name);
                    break;
                }
                
                const value = try self.allocator.dupe(u8, data[i..i + value_len]);
                i += value_len;
                
                try headers.append(Header.init(name, value));
            } else {
                // Skip unknown encoding now
                i += 1;
            }
        }
        
        return headers.toOwnedSlice();
    }
};

// HTTP/2 Connection
pub const Connection = struct {
    tls_client: tls.SimpleClient,
    allocator: std.mem.Allocator,
    next_stream_id: u31,
    streams: std.AutoHashMap(u31, Stream),
    settings: std.AutoHashMap(SettingsId, u32),
    hpack: HpackContext,
    window_size: i32,
    max_frame_size: u32,
    
    // Buffers
    read_buffer: std.ArrayList(u8),
    write_buffer: std.ArrayList(u8),
    
    pub fn init(allocator: std.mem.Allocator, tls_client: tls.SimpleClient) !Connection {
        var conn = Connection{
            .tls_client = tls_client,
            .allocator = allocator,
            .next_stream_id = 1, // Client streams are odd
            .streams = std.AutoHashMap(u31, Stream).init(allocator),
            .settings = std.AutoHashMap(SettingsId, u32).init(allocator),
            .hpack = HpackContext.init(allocator),
            .window_size = @intCast(DEFAULT_WINDOW_SIZE),
            .max_frame_size = DEFAULT_MAX_FRAME_SIZE,
            .read_buffer = std.ArrayList(u8).init(allocator),
            .write_buffer = std.ArrayList(u8).init(allocator),
        };
        
        // Initialize default settings
        try conn.settings.put(.HEADER_TABLE_SIZE, 4096);
        try conn.settings.put(.ENABLE_PUSH, 1);
        try conn.settings.put(.MAX_CONCURRENT_STREAMS, 100);
        try conn.settings.put(.INITIAL_WINDOW_SIZE, DEFAULT_WINDOW_SIZE);
        try conn.settings.put(.MAX_FRAME_SIZE, DEFAULT_MAX_FRAME_SIZE);
        try conn.settings.put(.MAX_HEADER_LIST_SIZE, 8192);
        
        return conn;
    }
    
    pub fn deinit(self: *Connection) void {
        var stream_it = self.streams.iterator();
        while (stream_it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.streams.deinit();
        self.settings.deinit();
        self.hpack.deinit();
        self.read_buffer.deinit();
        self.write_buffer.deinit();
        self.tls_client.deinit();
    }
    
    pub fn handshake(self: *Connection) !void {
        // Send HTTP/2 connection preface
        _ = try self.tls_client.write(CONNECTION_PREFACE);
        
        // Send initial SETTINGS frame
        try self.sendSettings(&[_]Setting{
            Setting{ .id = .HEADER_TABLE_SIZE, .value = 4096 },
            Setting{ .id = .MAX_CONCURRENT_STREAMS, .value = 100 },
            Setting{ .id = .INITIAL_WINDOW_SIZE, .value = DEFAULT_WINDOW_SIZE },
            Setting{ .id = .MAX_FRAME_SIZE, .value = DEFAULT_MAX_FRAME_SIZE },
        });
        
        // Wait for server settings and ACK
        try self.receiveSettings();
    }
    
    pub fn sendHeaders(self: *Connection, stream_id: u31, headers: []const Header, end_stream: bool) !void {
        // Encode headers using HPACK
        const encoded_headers = try self.hpack.encodeHeaders(headers);
        defer self.allocator.free(encoded_headers);
        
        var flags: u8 = FrameFlags.HEADERS_END_HEADERS;
        if (end_stream) flags |= FrameFlags.HEADERS_END_STREAM;
        
        const frame = Frame.init(.HEADERS, flags, stream_id, encoded_headers);
        try self.sendFrame(frame);
        
        // Create or update stream
        if (!self.streams.contains(stream_id)) {
            try self.streams.put(stream_id, Stream.init(self.allocator, stream_id));
        }
        
        var stream = self.streams.getPtr(stream_id).?;
        stream.state = if (end_stream) .half_closed_local else .open;
    }
    
    pub fn sendData(self: *Connection, stream_id: u31, data: []const u8, end_stream: bool) !void {
        var flags: u8 = 0;
        if (end_stream) flags |= FrameFlags.DATA_END_STREAM;
        
        // Send data in chunks if larger than max frame size
        var remaining = data;
        while (remaining.len > 0) {
            const chunk_size = @min(remaining.len, self.max_frame_size);
            const chunk = remaining[0..chunk_size];
            const is_last_chunk = remaining.len == chunk_size;
            
            var chunk_flags = flags;
            if (!is_last_chunk) chunk_flags &= ~FrameFlags.DATA_END_STREAM;
            
            const frame = Frame.init(.DATA, chunk_flags, stream_id, chunk);
            try self.sendFrame(frame);
            
            remaining = remaining[chunk_size..];
        }
        
        // Update stream state
        if (end_stream) {
            if (self.streams.getPtr(stream_id)) |stream| {
                stream.state = switch (stream.state) {
                    .open => .half_closed_local,
                    .half_closed_remote => .closed,
                    else => stream.state,
                };
            }
        }
    }
    
    pub fn sendGoaway(self: *Connection, last_stream_id: u31, error_code: ErrorCode, debug_data: []const u8) !void {
        // Create GOAWAY payload in a temporary buffer
        var payload = std.ArrayList(u8).init(self.allocator);
        defer payload.deinit();
        
        var writer = payload.writer();
        try writer.writeInt(u32, last_stream_id, .big);
        try writer.writeInt(u32, @intFromEnum(error_code), .big);
        try writer.writeAll(debug_data);
        
        const frame = Frame.init(.GOAWAY, 0, 0, payload.items);
        try self.sendFrame(frame);
    }
    
    pub fn readFrame(self: *Connection) !Frame {
        // Read frame header (9 bytes)
        var header: [9]u8 = undefined;
        try self.tls_client.readAll(&header);
        
        // Parse frame header
        const length = (@as(u32, header[0]) << 16) | (@as(u32, header[1]) << 8) | @as(u32, header[2]);
        const frame_type = @as(FrameType, @enumFromInt(header[3]));
        const flags = header[4];
        const stream_id_raw = std.mem.readInt(u32, header[5..9][0..4], .big);
        const stream_id = @as(u31, @intCast(stream_id_raw & 0x7FFFFFFF)); // Clear reserved bit
        
        if (length > MAX_FRAME_SIZE) return error.FrameSizeError;
        
        // Read payload
        if (length > self.read_buffer.capacity) {
            try self.read_buffer.ensureTotalCapacity(length);
        }
        self.read_buffer.shrinkRetainingCapacity(0);
        try self.read_buffer.resize(length);
        
        if (length > 0) {
            try self.tls_client.readAll(self.read_buffer.items);
        }
        
        return Frame{
            .length = @as(u24, @intCast(length)),
            .frame_type = frame_type,
            .flags = flags,
            .stream_id = stream_id,
            .payload = self.read_buffer.items,
        };
    }
    
    pub fn handleFrame(self: *Connection, frame: Frame) !void {
        switch (frame.frame_type) {
            .SETTINGS => try self.handleSettings(frame),
            .HEADERS => try self.handleHeaders(frame),
            .DATA => try self.handleData(frame),
            .WINDOW_UPDATE => try self.handleWindowUpdate(frame),
            .PING => try self.handlePing(frame),
            .GOAWAY => try self.handleGoaway(frame),
            .RST_STREAM => try self.handleRstStream(frame),
            else => {
                // Ignore unknown frame types
            },
        }
    }
    
    fn sendFrame(self: *Connection, frame: Frame) !void {
        self.write_buffer.clearRetainingCapacity();
        var writer = self.write_buffer.writer();
        
        // Write frame header
        try writer.writeByte(@as(u8, @intCast((frame.length >> 16) & 0xFF)));
        try writer.writeByte(@as(u8, @intCast((frame.length >> 8) & 0xFF)));
        try writer.writeByte(@as(u8, @intCast(frame.length & 0xFF)));
        try writer.writeByte(@intFromEnum(frame.frame_type));
        try writer.writeByte(frame.flags);
        try writer.writeInt(u32, frame.stream_id, .big);
        
        // Write payload
        try writer.writeAll(frame.payload);
        
        _ = try self.tls_client.write(self.write_buffer.items);
    }
    
    fn sendSettings(self: *Connection, settings: []const Setting) !void {
        // Create settings payload in a temporary buffer
        var payload = std.ArrayList(u8).init(self.allocator);
        defer payload.deinit();
        
        var writer = payload.writer();
        for (settings) |setting| {
            try writer.writeInt(u16, @intFromEnum(setting.id), .big);
            try writer.writeInt(u32, setting.value, .big);
        }
        
        const frame = Frame.init(.SETTINGS, 0, 0, payload.items);
        try self.sendFrame(frame);
    }
    
    fn receiveSettings(self: *Connection) !void {
        const frame = try self.readFrame();
        try self.handleFrame(frame);
        
        // Send settings ACK
        const ack_frame = Frame.init(.SETTINGS, FrameFlags.SETTINGS_ACK, 0, &[_]u8{});
        try self.sendFrame(ack_frame);
    }
    
    fn handleSettings(self: *Connection, frame: Frame) !void {
        if (frame.flags & FrameFlags.SETTINGS_ACK != 0) {
            // Settings ACK - nothing to do
            return;
        }
        
        if (frame.payload.len % 6 != 0) return error.ProtocolError;
        
        var i: usize = 0;
        while (i + 6 <= frame.payload.len) {
            const setting_id_raw = std.mem.readInt(u16, frame.payload[i..i + 2][0..2], .big);
            const setting_value = std.mem.readInt(u32, frame.payload[i + 2..i + 6][0..4], .big);
            
            if (std.meta.intToEnum(SettingsId, setting_id_raw)) |setting_id| {
                try self.settings.put(setting_id, setting_value);
                
                // Apply certain settings immediately
                switch (setting_id) {
                    .MAX_FRAME_SIZE => {
                        if (setting_value >= 16384 and setting_value <= 16777215) {
                            self.max_frame_size = setting_value;
                        }
                    },
                    .INITIAL_WINDOW_SIZE => {
                        if (setting_value <= 2147483647) {
                            self.window_size = @intCast(setting_value);
                        }
                    },
                    else => {},
                }
            } else |_| {
                // Unknown setting ID, ignore
            }
            
            i += 6;
        }
    }
    
    fn handleHeaders(self: *Connection, frame: Frame) !void {
        const stream = try self.getOrCreateStream(frame.stream_id);
        
        // Decode headers
        const headers = try self.hpack.decodeHeaders(frame.payload);
        defer {
            for (headers) |header| {
                self.allocator.free(header.name);
                self.allocator.free(header.value);
            }
            self.allocator.free(headers);
        }
        
        // Store headers in stream
        for (headers) |header| {
            const name = try self.allocator.dupe(u8, header.name);
            const value = try self.allocator.dupe(u8, header.value);
            try stream.headers.append(Header.init(name, value));
        }
        
        // Update stream state
        if (frame.flags & FrameFlags.HEADERS_END_STREAM != 0) {
            stream.state = switch (stream.state) {
                .idle => .half_closed_remote,
                .open => .half_closed_remote,
                else => stream.state,
            };
        } else {
            stream.state = .open;
        }
    }
    
    fn handleData(self: *Connection, frame: Frame) !void {
        const stream = self.streams.getPtr(frame.stream_id) orelse return error.ProtocolError;
        
        // Append data to stream
        try stream.data.appendSlice(frame.payload);
        
        // Update stream state
        if (frame.flags & FrameFlags.DATA_END_STREAM != 0) {
            stream.state = switch (stream.state) {
                .open => .half_closed_remote,
                .half_closed_local => .closed,
                else => stream.state,
            };
        }
    }
    
    fn handleWindowUpdate(self: *Connection, frame: Frame) !void {
        if (frame.payload.len != 4) return error.ProtocolError;
        
        const window_size_increment = std.mem.readInt(u32, frame.payload[0..4][0..4], .big) & 0x7FFFFFFF;
        
        if (frame.stream_id == 0) {
            // Connection-level window update - prevent overflow
            const new_size = @as(i64, self.window_size) + @as(i64, window_size_increment);
            self.window_size = @as(i32, @intCast(@min(new_size, std.math.maxInt(i32))));
        } else {
            // Stream-level window update - prevent overflow
            if (self.streams.getPtr(frame.stream_id)) |stream| {
                const new_size = @as(i64, stream.window_size) + @as(i64, window_size_increment);
                stream.window_size = @as(i32, @intCast(@min(new_size, std.math.maxInt(i32))));
            }
        }
    }
    
    fn handlePing(self: *Connection, frame: Frame) !void {
        if (frame.payload.len != 8) return error.ProtocolError;
        
        if (frame.flags & FrameFlags.PING_ACK == 0) {
            // Send PING ACK
            const ack_frame = Frame.init(.PING, FrameFlags.PING_ACK, 0, frame.payload);
            try self.sendFrame(ack_frame);
        }
    }
    
    fn handleGoaway(self: *Connection, frame: Frame) !void {
        _ = self;
        _ = frame;
        // Server is closing the connection
        return error.ConnectionClosed;
    }
    
    fn handleRstStream(self: *Connection, frame: Frame) !void {
        if (frame.payload.len != 4) return error.ProtocolError;
        
        if (self.streams.getPtr(frame.stream_id)) |stream| {
            stream.state = .closed;
        }
    }
    
    fn getOrCreateStream(self: *Connection, stream_id: u31) !*Stream {
        if (self.streams.getPtr(stream_id)) |stream| {
            return stream;
        }
        
        try self.streams.put(stream_id, Stream.init(self.allocator, stream_id));
        return self.streams.getPtr(stream_id).?;
    }
    
    pub fn getNextStreamId(self: *Connection) u31 {
        const stream_id = self.next_stream_id;
        self.next_stream_id += 2; // Client streams are odd
        return stream_id;
    }
    
    pub fn getStream(self: *Connection, stream_id: u31) ?*Stream {
        return self.streams.getPtr(stream_id);
    }
};