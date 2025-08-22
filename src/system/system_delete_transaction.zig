const std = @import("std");
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const ContractId = @import("../core/id.zig").ContractId;
const FileId = @import("../core/id.zig").FileId;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const Timestamp = @import("../core/timestamp.zig").Timestamp;

// SystemDeleteTransaction deletes a file or smart contract (admin only)
pub const SystemDeleteTransaction = struct {
    base: Transaction,
    contract_id: ?ContractId = null,
    file_id: ?FileId = null,
    expiration_time: ?Timestamp = null,
    
    pub fn init(allocator: std.mem.Allocator) SystemDeleteTransaction {
        return SystemDeleteTransaction{
            .base = Transaction.init(allocator),
        };
    }
    
    pub fn deinit(self: *SystemDeleteTransaction) void {
        self.base.deinit();
    }
    
    // Set the contract ID to delete
    pub fn setContractId(self: *SystemDeleteTransaction, contract_id: ContractId) *SystemDeleteTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        self.contract_id = contract_id;
        self.file_id = null; // Clear file ID when setting contract ID
        return self;
    }
    
    // Set the file ID to delete
    pub fn setFileId(self: *SystemDeleteTransaction, file_id: FileId) *SystemDeleteTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        self.file_id = file_id;
        self.contract_id = null; // Clear contract ID when setting file ID
        return self;
    }
    
    // Set the expiration time
    pub fn setExpirationTime(self: *SystemDeleteTransaction, expiration_time: Timestamp) *SystemDeleteTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        self.expiration_time = expiration_time;
        return self;
    }
    
    // Execute the transaction
    pub fn execute(self: *SystemDeleteTransaction, client: *Client) !TransactionResponse {
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *SystemDeleteTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Write common transaction fields
        try self.base.writeCommonFields(&writer);
        
        // systemDelete = 35 (oneof data)
        var delete_writer = ProtoWriter.init(self.base.allocator);
        defer delete_writer.deinit();
        
        // expirationTime = 2
        if (self.expiration_time) |expiration| {
            var timestamp_writer = ProtoWriter.init(self.base.allocator);
            defer timestamp_writer.deinit();
            try timestamp_writer.writeInt64(1, expiration.seconds);
            const timestamp_bytes = try timestamp_writer.toOwnedSlice();
            defer self.base.allocator.free(timestamp_bytes);
            try delete_writer.writeMessage(2, timestamp_bytes);
            return self;
        }
        
        // Either contractID = 1 or fileID = 3 (oneof id)
        if (self.contract_id) |contract_id| {
            var contract_writer = ProtoWriter.init(self.base.allocator);
            defer contract_writer.deinit();
            try contract_writer.writeInt64(1, @intCast(contract_id.shard));
            try contract_writer.writeInt64(2, @intCast(contract_id.realm));
            try contract_writer.writeInt64(3, @intCast(contract_id.num));
            const contract_bytes = try contract_writer.toOwnedSlice();
            defer self.base.allocator.free(contract_bytes);
            try delete_writer.writeMessage(1, contract_bytes);
        } else if (self.file_id) |file_id| {
            var file_writer = ProtoWriter.init(self.base.allocator);
            defer file_writer.deinit();
            try file_writer.writeInt64(1, @intCast(file_id.shard));
            try file_writer.writeInt64(2, @intCast(file_id.realm));
            try file_writer.writeInt64(3, @intCast(file_id.num));
            const file_bytes = try file_writer.toOwnedSlice();
            defer self.base.allocator.free(file_bytes);
            try delete_writer.writeMessage(3, file_bytes);
        }
        
        const delete_bytes = try delete_writer.toOwnedSlice();
        defer self.base.allocator.free(delete_bytes);
        try writer.writeMessage(35, delete_bytes);
        
        return writer.toOwnedSlice();
    }
    
    // Validate the transaction
    pub fn validate(self: *SystemDeleteTransaction) !void {
        if (self.contract_id == null and self.file_id == null) {
            return error.MustSetEitherContractIdOrFileId;
        }
        
        if (self.contract_id != null and self.file_id != null) {
            return error.CannotSetBothContractIdAndFileId;
        }
    }
};