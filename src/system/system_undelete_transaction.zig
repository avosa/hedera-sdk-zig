const std = @import("std");
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const ContractId = @import("../core/id.zig").ContractId;
const FileId = @import("../core/id.zig").FileId;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;

// SystemUndeleteTransaction undeletes a file or smart contract (admin only)
pub const SystemUndeleteTransaction = struct {
    base: Transaction,
    contract_id: ?ContractId = null,
    file_id: ?FileId = null,
    
    pub fn init(allocator: std.mem.Allocator) SystemUndeleteTransaction {
        return SystemUndeleteTransaction{
            .base = Transaction.init(allocator),
        };
    }
    
    pub fn deinit(self: *SystemUndeleteTransaction) void {
        self.base.deinit();
    }
    
    // Set the contract ID to undelete
    pub fn setContractId(self: *SystemUndeleteTransaction, contract_id: ContractId) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.contract_id = contract_id;
        self.file_id = null; // Clear file ID when setting contract ID
    }
    
    // Set the file ID to undelete
    pub fn setFileId(self: *SystemUndeleteTransaction, file_id: FileId) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.file_id = file_id;
        self.contract_id = null; // Clear contract ID when setting file ID
    }
    
    // Execute the transaction
    pub fn execute(self: *SystemUndeleteTransaction, client: *Client) !TransactionResponse {
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *SystemUndeleteTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Write common transaction fields
        try self.base.writeCommonFields(&writer);
        
        // systemUndelete = 36 (oneof data)
        var undelete_writer = ProtoWriter.init(self.base.allocator);
        defer undelete_writer.deinit();
        
        // Either contractID = 1 or fileID = 2 (oneof id)
        if (self.contract_id) |contract_id| {
            var contract_writer = ProtoWriter.init(self.base.allocator);
            defer contract_writer.deinit();
            try contract_writer.writeInt64(1, @intCast(contract_id.entity.shard));
            try contract_writer.writeInt64(2, @intCast(contract_id.entity.realm));
            try contract_writer.writeInt64(3, @intCast(contract_id.entity.num));
            const contract_bytes = try contract_writer.toOwnedSlice();
            defer self.base.allocator.free(contract_bytes);
            try undelete_writer.writeMessage(1, contract_bytes);
        } else if (self.file_id) |file_id| {
            var file_writer = ProtoWriter.init(self.base.allocator);
            defer file_writer.deinit();
            try file_writer.writeInt64(1, @intCast(file_id.entity.shard));
            try file_writer.writeInt64(2, @intCast(file_id.entity.realm));
            try file_writer.writeInt64(3, @intCast(file_id.entity.num));
            const file_bytes = try file_writer.toOwnedSlice();
            defer self.base.allocator.free(file_bytes);
            try undelete_writer.writeMessage(2, file_bytes);
        }
        
        const undelete_bytes = try undelete_writer.toOwnedSlice();
        defer self.base.allocator.free(undelete_bytes);
        try writer.writeMessage(36, undelete_bytes);
        
        return writer.toOwnedSlice();
    }
    
    // Validate the transaction
    pub fn validate(self: *SystemUndeleteTransaction) !void {
        if (self.contract_id == null and self.file_id == null) {
            return error.MustSetEitherContractIdOrFileId;
        }
        
        if (self.contract_id != null and self.file_id != null) {
            return error.CannotSetBothContractIdAndFileId;
        }
    }
};