const std = @import("std");
const FileId = @import("../core/id.zig").FileId;
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;

// Maximum chunk size for file append
pub const MAX_CHUNK_SIZE: usize = 4096; // 4KB per chunk
pub const MAX_CHUNKS: usize = 20;

// FileAppendTransaction appends contents to an existing file
pub const FileAppendTransaction = struct {
    base: Transaction,
    file_id: ?FileId,
    contents: []const u8,
    chunk_size: usize,
    max_chunks: u32,
    
    pub fn init(allocator: std.mem.Allocator) FileAppendTransaction {
        return FileAppendTransaction{
            .base = Transaction.init(allocator),
            .file_id = null,
            .contents = "",
            .chunk_size = MAX_CHUNK_SIZE,
            .max_chunks = MAX_CHUNKS,
        };
    }
    
    pub fn deinit(self: *FileAppendTransaction) void {
        self.base.deinit();
    }
    
    // Set the file ID to append to
    pub fn setFileId(self: *FileAppendTransaction, file_id: FileId) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.file_id = file_id;
    }
    
    // Set the contents to append
    pub fn setContents(self: *FileAppendTransaction, contents: []const u8) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        
        if (contents.len > MAX_CHUNK_SIZE * MAX_CHUNKS) {
            return error.ContentsTooLarge;
        }
        
        self.contents = contents;
    }
    
    // Set chunk size for multi-chunk appends
    pub fn setChunkSize(self: *FileAppendTransaction, size: usize) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        
        if (size == 0 or size > MAX_CHUNK_SIZE) {
            return error.InvalidChunkSize;
        }
        
        self.chunk_size = size;
    }
    
    // Set max chunks
    pub fn setMaxChunks(self: *FileAppendTransaction, max_chunks: u32) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        
        if (max_chunks == 0 or max_chunks > MAX_CHUNKS) {
            return error.InvalidMaxChunks;
        }
        
        self.max_chunks = max_chunks;
    }
    
    // Execute the transaction
    pub fn execute(self: *FileAppendTransaction, client: *Client) !TransactionResponse {
        if (self.file_id == null) {
            return error.FileIdRequired;
        }
        
        if (self.contents.len == 0) {
            return error.ContentsRequired;
        }
        
        // Handle chunking for large content
        if (self.contents.len > self.chunk_size) {
            return try self.executeChunked(client);
        }
        
        return try self.base.execute(client);
    }
    
    // Execute chunked file append
    fn executeChunked(self: *FileAppendTransaction, client: *Client) !TransactionResponse {
        const chunk_count = (self.contents.len + self.chunk_size - 1) / self.chunk_size;
        
        if (chunk_count > MAX_CHUNKS) {
            return error.TooManyChunks;
        }
        
        // Generate initial transaction ID for all chunks
        const initial_tx_id = try self.base.getTransactionId();
        
        var last_response: ?TransactionResponse = null;
        
        // Submit each chunk
        var i: usize = 0;
        while (i < chunk_count) : (i += 1) {
            const start = i * self.chunk_size;
            const end = @min(start + self.chunk_size, self.contents.len);
            const chunk_data = self.contents[start..end];
            
            // Create transaction for this chunk
            var chunk_tx = FileAppendTransaction.init(self.base.allocator);
            defer chunk_tx.deinit();
            
            chunk_tx.file_id = self.file_id;
            chunk_tx.contents = chunk_data;
            
            // Set transaction ID with nonce for chunks after the first
            if (i > 0) {
                const chunk_tx_id = initial_tx_id.withNonce(@intCast(i));
                try chunk_tx.base.setTransactionId(chunk_tx_id);
            } else {
                try chunk_tx.base.setTransactionId(initial_tx_id);
            }
            
            // Copy other transaction settings
            chunk_tx.base.node_account_ids = self.base.node_account_ids;
            chunk_tx.base.max_transaction_fee = self.base.max_transaction_fee;
            
            // Execute chunk transaction
            const response = try chunk_tx.base.execute(client);
            last_response = response;
        }
        
        return last_response orelse error.NoChunksSubmitted;
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *FileAppendTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Common transaction fields
        try self.writeCommonFields(&writer);
        
        // fileAppend = 16 (oneof data)
        var append_writer = ProtoWriter.init(self.base.allocator);
        defer append_writer.deinit();
        
        // fileID = 2
        if (self.file_id) |file| {
            var file_writer = ProtoWriter.init(self.base.allocator);
            defer file_writer.deinit();
            try file_writer.writeInt64(1, @intCast(file.entity.shard));
            try file_writer.writeInt64(2, @intCast(file.entity.realm));
            try file_writer.writeInt64(3, @intCast(file.entity.num));
            const file_bytes = try file_writer.toOwnedSlice();
            defer self.base.allocator.free(file_bytes);
            try append_writer.writeMessage(2, file_bytes);
        }
        
        // contents = 4
        if (self.contents.len > 0) {
            try append_writer.writeBytes(4, self.contents);
        }
        
        const append_bytes = try append_writer.toOwnedSlice();
        defer self.base.allocator.free(append_bytes);
        try writer.writeMessage(16, append_bytes);
        
        return writer.toOwnedSlice();
    }
    
    fn writeCommonFields(self: *FileAppendTransaction, writer: *ProtoWriter) !void {
        // transactionID = 1
        if (self.base.transaction_id) |tx_id| {
            var tx_id_writer = ProtoWriter.init(self.base.allocator);
            defer tx_id_writer.deinit();
            
            var timestamp_writer = ProtoWriter.init(self.base.allocator);
            defer timestamp_writer.deinit();
            try timestamp_writer.writeInt64(1, tx_id.valid_start.seconds);
            try timestamp_writer.writeInt32(2, tx_id.valid_start.nanos);
            const timestamp_bytes = try timestamp_writer.toOwnedSlice();
            defer self.base.allocator.free(timestamp_bytes);
            try tx_id_writer.writeMessage(1, timestamp_bytes);
            
            var account_writer = ProtoWriter.init(self.base.allocator);
            defer account_writer.deinit();
            try account_writer.writeInt64(1, @intCast(tx_id.account_id.entity.shard));
            try account_writer.writeInt64(2, @intCast(tx_id.account_id.entity.realm));
            try account_writer.writeInt64(3, @intCast(tx_id.account_id.entity.num));
            const account_bytes = try account_writer.toOwnedSlice();
            defer self.base.allocator.free(account_bytes);
            try tx_id_writer.writeMessage(2, account_bytes);
            
            if (tx_id.nonce) |n| {
                try tx_id_writer.writeInt32(4, @intCast(n));
            }
            
            const tx_id_bytes = try tx_id_writer.toOwnedSlice();
            defer self.base.allocator.free(tx_id_bytes);
            try writer.writeMessage(1, tx_id_bytes);
        }
        
        // nodeAccountID = 2
        if (self.base.node_account_ids.items.len > 0) {
            var node_writer = ProtoWriter.init(self.base.allocator);
            defer node_writer.deinit();
            const node = self.base.node_account_ids.items[0];
            try node_writer.writeInt64(1, @intCast(node.entity.shard));
            try node_writer.writeInt64(2, @intCast(node.entity.realm));
            try node_writer.writeInt64(3, @intCast(node.entity.num));
            const node_bytes = try node_writer.toOwnedSlice();
            defer self.base.allocator.free(node_bytes);
            try writer.writeMessage(2, node_bytes);
        }
        
        // transactionFee = 3
        if (self.base.max_transaction_fee) |fee| {
            try writer.writeUint64(3, @intCast(fee.toTinybars()));
        }
        
        // transactionValidDuration = 4
        var duration_writer = ProtoWriter.init(self.base.allocator);
        defer duration_writer.deinit();
        try duration_writer.writeInt64(1, self.base.transaction_valid_duration.seconds);
        const duration_bytes = try duration_writer.toOwnedSlice();
        defer self.base.allocator.free(duration_bytes);
        try writer.writeMessage(4, duration_bytes);
        
        // memo = 5
        if (self.base.transaction_memo.len > 0) {
            try writer.writeString(5, self.base.transaction_memo);
        }
    }
};