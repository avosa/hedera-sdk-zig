const std = @import("std");
const FileId = @import("../core/id.zig").FileId;
const Key = @import("../crypto/key.zig").Key;
const Timestamp = @import("../core/timestamp.zig").Timestamp;
const Query = @import("../query/query.zig").Query;
const QueryResponse = @import("../query/query.zig").QueryResponse;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;
const Hbar = @import("../core/hbar.zig").Hbar;

// FileInfo contains information about a file
pub const FileInfo = struct {
    file_id: FileId,
    size: i64,
    expiration_time: Timestamp,
    deleted: bool,
    keys: std.ArrayList(Key),
    memo: []const u8,
    ledger_id: []const u8,
    
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) FileInfo {
        return FileInfo{
            .file_id = FileId.init(0, 0, 0),
            .size = 0,
            .expiration_time = Timestamp{ .seconds = 0, .nanos = 0 },
            .deleted = false,
            .keys = std.ArrayList(Key).init(allocator),
            .memo = "",
            .ledger_id = "",
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *FileInfo) void {
        // Keys don't need individual deinit
        self.keys.deinit();
        if (self.memo.len > 0) {
            self.allocator.free(self.memo);
        }
        if (self.ledger_id.len > 0) {
            self.allocator.free(self.ledger_id);
        }
    }
};

// FileInfoQuery retrieves information about a file
pub const FileInfoQuery = struct {
    base: Query,
    file_id: ?FileId,
    
    pub fn init(allocator: std.mem.Allocator) FileInfoQuery {
        return FileInfoQuery{
            .base = Query.init(allocator),
            .file_id = null,
        };
    }
    
    pub fn deinit(self: *FileInfoQuery) void {
        self.base.deinit();
    }
    
    // Set the file ID to query
    pub fn setFileId(self: *FileInfoQuery, file_id: FileId) !void {
        self.file_id = file_id;
    }
    
    // Set the query payment amount
    pub fn setQueryPayment(self: *FileInfoQuery, payment: Hbar) !void {
        self.base.payment_amount = payment;
    }
    
    // Execute the query
    pub fn execute(self: *FileInfoQuery, client: *Client) !FileInfo {
        if (self.file_id == null) {
            return error.FileIdRequired;
        }
        
        const response = try self.base.execute(client);
        return try self.parseResponse(response);
    }
    
    // Get cost of the query
    pub fn getCost(self: *FileInfoQuery, client: *Client) !Hbar {
        self.base.response_type = .CostAnswer;
        const response = try self.base.execute(client);
        
        var reader = ProtoReader.init(response.response_bytes);
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                2 => {
                    const cost = try reader.readUint64();
                    return try Hbar.fromTinybars(@intCast(cost));
                },
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return error.CostNotFound;
    }
    
    // Build the query
    pub fn buildQuery(self: *FileInfoQuery) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Query message structure
        // header = 1
        var header_writer = ProtoWriter.init(self.base.allocator);
        defer header_writer.deinit();
        
        // payment = 1
        if (self.base.payment_transaction) |payment| {
            try header_writer.writeMessage(1, payment);
        }
        
        // responseType = 2
        try header_writer.writeInt32(2, @intFromEnum(self.base.response_type));
        
        const header_bytes = try header_writer.toOwnedSlice();
        defer self.base.allocator.free(header_bytes);
        try writer.writeMessage(1, header_bytes);
        
        // fileGetInfo = 6 (oneof query)
        var info_query_writer = ProtoWriter.init(self.base.allocator);
        defer info_query_writer.deinit();
        
        // fileID = 1
        if (self.file_id) |file| {
            var file_writer = ProtoWriter.init(self.base.allocator);
            defer file_writer.deinit();
            try file_writer.writeInt64(1, @intCast(file.entity.shard));
            try file_writer.writeInt64(2, @intCast(file.entity.realm));
            try file_writer.writeInt64(3, @intCast(file.entity.num));
            const file_bytes = try file_writer.toOwnedSlice();
            defer self.base.allocator.free(file_bytes);
            try info_query_writer.writeMessage(1, file_bytes);
        }
        
        const info_query_bytes = try info_query_writer.toOwnedSlice();
        defer self.base.allocator.free(info_query_bytes);
        try writer.writeMessage(6, info_query_bytes);
        
        return writer.toOwnedSlice();
    }
    
    // Parse the response
    fn parseResponse(self: *FileInfoQuery, response: QueryResponse) !FileInfo {
        try response.validateStatus();
        
        var reader = ProtoReader.init(response.response_bytes);
        
        var info = FileInfo{
            .file_id = FileId.init(0, 0, 0),
            .size = 0,
            .expiration_time = Timestamp{ .seconds = 0, .nanos = 0 },
            .deleted = false,
            .keys = std.ArrayList(Key).init(self.base.allocator),
            .memo = "",
            .ledger_id = "",
            .allocator = self.base.allocator,
        };
        
        // Parse FileGetInfoResponse
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => {
                    // header
                    _ = try reader.readMessage();
                },
                2 => {
                    // fileInfo
                    const file_info_bytes = try reader.readMessage();
                    var file_reader = ProtoReader.init(file_info_bytes);
                    
                    while (file_reader.hasMore()) {
                        const f_tag = try file_reader.readTag();
                        
                        switch (f_tag.field_number) {
                            1 => {
                                // fileID
                                const file_bytes = try file_reader.readMessage();
                                var id_reader = ProtoReader.init(file_bytes);
                                
                                var shard: i64 = 0;
                                var realm: i64 = 0;
                                var num: i64 = 0;
                                
                                while (id_reader.hasMore()) {
                                    const i = try id_reader.readTag();
                                    switch (i.field_number) {
                                        1 => shard = try id_reader.readInt64(),
                                        2 => realm = try id_reader.readInt64(),
                                        3 => num = try id_reader.readInt64(),
                                        else => try id_reader.skipField(i.wire_type),
                                    }
                                }
                                
                                info.file_id = FileId.init(@intCast(shard), @intCast(realm), @intCast(num));
                            },
                            2 => info.size = try file_reader.readInt64(),
                            3 => {
                                // expirationTime
                                const exp_bytes = try file_reader.readMessage();
                                var exp_reader = ProtoReader.init(exp_bytes);
                                
                                while (exp_reader.hasMore()) {
                                    const e = try exp_reader.readTag();
                                    switch (e.field_number) {
                                        1 => info.expiration_time.seconds = try exp_reader.readInt64(),
                                        2 => info.expiration_time.nanos = try exp_reader.readInt32(),
                                        else => try exp_reader.skipField(e.wire_type),
                                    }
                                }
                            },
                            4 => info.deleted = try file_reader.readBool(),
                            5 => {
                                // keys
                                const keys_bytes = try file_reader.readMessage();
                                var keys_reader = ProtoReader.init(keys_bytes);
                                
                                while (keys_reader.hasMore()) {
                                    const k_tag = try keys_reader.readTag();
                                    
                                    switch (k_tag.field_number) {
                                        1 => {
                                            // keys (repeated)
                                            const key_bytes = try keys_reader.readMessage();
                                            const key = try Key.fromProtobuf(key_bytes, self.base.allocator);
                                            try info.keys.append(key);
                                        },
                                        else => try keys_reader.skipField(k_tag.wire_type),
                                    }
                                }
                            },
                            6 => info.memo = try self.base.allocator.dupe(u8, try file_reader.readString()),
                            7 => {
                                // ledgerId
                                const ledger_bytes = try file_reader.readBytes();
                                info.ledger_id = try self.base.allocator.dupe(u8, ledger_bytes);
                            },
                            else => try file_reader.skipField(f_tag.wire_type),
                        }
                    }
                },
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return info;
    }
};