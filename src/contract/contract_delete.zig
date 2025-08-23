const std = @import("std");
const errors = @import("../core/errors.zig");
const ContractId = @import("../core/id.zig").ContractId;
const AccountId = @import("../core/id.zig").AccountId;
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;

// ContractDeleteTransaction marks a contract as deleted and transfers its hbars to another account
pub const ContractDeleteTransaction = struct {
    base: Transaction,
    contract_id: ?ContractId,
    transfer_account_id: ?AccountId,
    transfer_contract_id: ?ContractId,
    permanent_removal: bool,
    
    pub fn init(allocator: std.mem.Allocator) ContractDeleteTransaction {
        return ContractDeleteTransaction{
            .base = Transaction.init(allocator),
            .contract_id = null,
            .transfer_account_id = null,
            .transfer_contract_id = null,
            .permanent_removal = false,
        };
    }
    
    pub fn deinit(self: *ContractDeleteTransaction) void {
        self.base.deinit();
    }
    
    // SetContractID sets the contract to delete
    pub fn SetContractID(self: *ContractDeleteTransaction, contract_id: ContractId) errors.HederaError!*ContractDeleteTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        self.contract_id = contract_id;
        return self;
    }
    
    // GetContractID returns the contract to delete
    pub fn GetContractID(self: *const ContractDeleteTransaction) ContractId {
        return self.contract_id orelse ContractId{};
    }
    
    // SetTransferAccountID sets the account to transfer remaining balance to
    pub fn SetTransferAccountID(self: *ContractDeleteTransaction, account_id: AccountId) errors.HederaError!*ContractDeleteTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        self.transfer_account_id = account_id;
        self.transfer_contract_id = null; // Clear contract ID when setting account ID
        return self;
    }
    
    // GetTransferAccountID returns the account to transfer remaining balance to
    pub fn GetTransferAccountID(self: *const ContractDeleteTransaction) AccountId {
        return self.transfer_account_id orelse AccountId{};
    }
    
    // SetTransferContractID sets the contract to transfer remaining balance to
    pub fn SetTransferContractID(self: *ContractDeleteTransaction, contract_id: ContractId) errors.HederaError!*ContractDeleteTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        self.transfer_contract_id = contract_id;
        self.transfer_account_id = null; // Clear account ID when setting contract ID
        return self;
    }
    
    // GetTransferContractID returns the contract to transfer remaining balance to
    pub fn GetTransferContractID(self: *const ContractDeleteTransaction) ContractId {
        return self.transfer_contract_id orelse ContractId{};
    }
    
    // SetPermanentRemoval sets the permanent removal flag
    pub fn SetPermanentRemoval(self: *ContractDeleteTransaction, permanent: bool) errors.HederaError!*ContractDeleteTransaction {
        try errors.requireNotFrozen(self.base.frozen);
        self.permanent_removal = permanent;
        return self;
    }
    
    // GetPermanentRemoval returns the permanent removal flag
    pub fn GetPermanentRemoval(self: *const ContractDeleteTransaction) bool {
        return self.permanent_removal;
    }
    
    
    // Execute the transaction
    pub fn execute(self: *ContractDeleteTransaction, client: *Client) !TransactionResponse {
        if (self.contract_id == null) {
            return error.ContractIdRequired;
        }
        
        if (self.transfer_account_id == null and self.transfer_contract_id == null) {
            return error.TransferTargetRequired;
        }
        
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *ContractDeleteTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Common transaction fields
        try self.base.writeTransactionHeader(&writer);
        
        // contractDeleteInstance = 22 (oneof data)
        var delete_writer = ProtoWriter.init(self.base.allocator);
        defer delete_writer.deinit();
        
        // contractID = 1
        if (self.contract_id) |contract| {
            var contract_writer = ProtoWriter.init(self.base.allocator);
            defer contract_writer.deinit();
            try contract_writer.writeInt64(1, @intCast(contract.shard));
            try contract_writer.writeInt64(2, @intCast(contract.realm));
            try contract_writer.writeInt64(3, @intCast(contract.num));
            const contract_bytes = try contract_writer.toOwnedSlice();
            defer self.base.allocator.free(contract_bytes);
            try delete_writer.writeMessage(1, contract_bytes);
        }
        
        // obtainers = 2 (oneof)
        if (self.transfer_account_id) |account| {
            var account_writer = ProtoWriter.init(self.base.allocator);
            defer account_writer.deinit();
            try account_writer.writeInt64(1, @intCast(account.shard));
            try account_writer.writeInt64(2, @intCast(account.realm));
            try account_writer.writeInt64(3, @intCast(account.account));
            const account_bytes = try account_writer.toOwnedSlice();
            defer self.base.allocator.free(account_bytes);
            try delete_writer.writeMessage(2, account_bytes);
        } else if (self.transfer_contract_id) |contract| {
            var contract_writer = ProtoWriter.init(self.base.allocator);
            defer contract_writer.deinit();
            try contract_writer.writeInt64(1, @intCast(contract.shard));
            try contract_writer.writeInt64(2, @intCast(contract.realm));
            try contract_writer.writeInt64(3, @intCast(contract.num));
            const contract_bytes = try contract_writer.toOwnedSlice();
            defer self.base.allocator.free(contract_bytes);
            try delete_writer.writeMessage(3, contract_bytes);
        }
        
        // permanent_removal = 4
        if (self.permanent_removal) {
            try delete_writer.writeBool(4, true);
        }
        
        const delete_bytes = try delete_writer.toOwnedSlice();
        defer self.base.allocator.free(delete_bytes);
        try writer.writeMessage(22, delete_bytes);
        
        return writer.toOwnedSlice();
    }
};