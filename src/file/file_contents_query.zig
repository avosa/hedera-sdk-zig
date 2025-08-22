const std = @import("std");
const FileId = @import("../core/id.zig").FileId;
const Query = @import("../query/query.zig").Query;
const QueryResponse = @import("../query/query.zig").QueryResponse;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;
const Hbar = @import("../core/hbar.zig").Hbar;

// FileContents contains the contents of a file
pub const FileContents = struct {
    file_id: FileId,
    contents: []const u8,
    
    allocator: std.mem.Allocator,
    
    pub fn deinit(self: *FileContents) void {
        if (self.contents.len > 0) {
            self.allocator.free(self.contents);
        }
    }
};

// FileContentsQuery retrieves the contents of a file
pub const FileContentsQuery = struct {
    base: Query,
    file_id: ?FileId,
    
    pub fn init(allocator: std.mem.Allocator) FileContentsQuery {
        return FileContentsQuery{
            .base = Query.init(allocator),
            .file_id = null,
        };
    }
    
    pub fn deinit(self: *FileContentsQuery) void {
        self.base.deinit();
    }
    
    // Set the file ID to query contents for
    pub fn setFileId(self: *FileContentsQuery, file_id: FileId) *FileContentsQuery {
        self.file_id = file_id;
        return self;
    }
    
    // Set the query payment amount
    pub fn setQueryPayment(self: *FileContentsQuery, payment: Hbar) *FileContentsQuery {
        self.base.payment_amount = payment;
        return self;
    }
    
    // Execute the query
    pub fn execute(self: *FileContentsQuery, client: *Client) !FileContents {
        if (self.file_id == null) {
            return error.FileIdRequired;
        }
        
        const response = try self.base.execute(client);
        return try self.parseResponse(response);
    }
    
    // Get cost of the query
    pub fn getCost(self: *FileContentsQuery, client: *Client) !Hbar {
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
    pub fn buildQuery(self: *FileContentsQuery) ![]u8 {
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
        
        // fileGetContents = 7 (oneof query)
        var contents_query_writer = ProtoWriter.init(self.base.allocator);
        defer contents_query_writer.deinit();
        
        // fileID = 1
        if (self.file_id) |file| {
            var file_writer = ProtoWriter.init(self.base.allocator);
            defer file_writer.deinit();
            try file_writer.writeInt64(1, @intCast(file.shard));
            try file_writer.writeInt64(2, @intCast(file.realm));
            try file_writer.writeInt64(3, @intCast(file.num));
            const file_bytes = try file_writer.toOwnedSlice();
            defer self.base.allocator.free(file_bytes);
            try contents_query_writer.writeMessage(1, file_bytes);
        }
        
        const contents_query_bytes = try contents_query_writer.toOwnedSlice();
        defer self.base.allocator.free(contents_query_bytes);
        try writer.writeMessage(7, contents_query_bytes);
        
        return writer.toOwnedSlice();
    }
    
    // Parse the response
    fn parseResponse(self: *FileContentsQuery, response: QueryResponse) !FileContents {
        try response.validateStatus();
        
        var reader = ProtoReader.init(response.response_bytes);
        
        var contents = FileContents{
            .file_id = FileId.init(0, 0, 0),
            .contents = "",
            .allocator = self.base.allocator,
        };
        
        // Parse FileGetContentsResponse
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => {
                    // header
                    _ = try reader.readMessage();
                },
                2 => {
                    // fileContents
                    const file_contents_bytes = try reader.readMessage();
                    var file_reader = ProtoReader.init(file_contents_bytes);
                    
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
                                
                                contents.file_id = FileId.init(@intCast(shard), @intCast(realm), @intCast(num));
                            },
                            2 => {
                                // contents
                                const content_bytes = try file_reader.readBytes();
                                contents.contents = try self.base.allocator.dupe(u8, content_bytes);
                            },
                            else => try file_reader.skipField(f_tag.wire_type),
                        }
                    }
                },
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        if (self.file_id) |file_id| {
            contents.file_id = file_id;
        }
        
        return contents;
    }
};