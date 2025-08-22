const std = @import("std");
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
    
    // Set the contract to delete
    pub fn setContractId(self: *ContractDeleteTransaction, contract_id: ContractId) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.contract_id = contract_id;
    }
    
    // Match Go SDK's SetContractID
    pub fn set_contract_id(self: *ContractDeleteTransaction, contract_id: ContractId) !*ContractDeleteTransaction {
        try self.setContractId(contract_id);
        return self;
    }
    
    // Set account to transfer remaining balance to
    pub fn setTransferAccountId(self: *ContractDeleteTransaction, account_id: AccountId) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        if (self.transfer_contract_id != null) {
            return error.CannotSetBothTransferAccountAndContract;
        }
        self.transfer_account_id = account_id;
    }
    
    // Match Go SDK's SetTransferAccountID
    pub fn set_transfer_account_id(self: *ContractDeleteTransaction, account_id: AccountId) !*ContractDeleteTransaction {
        try self.setTransferAccountId(account_id);
        return self;
    }
    
    // Set contract to transfer remaining balance to
    pub fn setTransferContractId(self: *ContractDeleteTransaction, contract_id: ContractId) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        if (self.transfer_account_id != null) {
            return error.CannotSetBothTransferAccountAndContract;
        }
        self.transfer_contract_id = contract_id;
    }
    
    // Match Go SDK's SetTransferContractID
    pub fn set_transfer_contract_id(self: *ContractDeleteTransaction, contract_id: ContractId) !*ContractDeleteTransaction {
        try self.setTransferContractId(contract_id);
        return self;
    }
    
    // Set permanent removal flag
    pub fn setPermanentRemoval(self: *ContractDeleteTransaction, permanent: bool) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.permanent_removal = permanent;
    }
    
    // Match Go SDK's SetPermanentRemoval
    pub fn set_permanent_removal(self: *ContractDeleteTransaction, permanent: bool) !*ContractDeleteTransaction {
        try self.setPermanentRemoval(permanent);
        return self;
    }
    
    // Freeze the transaction
    pub fn freeze(self: *ContractDeleteTransaction) !void {
        try self.base.freeze();
    }
    
    // Freeze with client
    pub fn freezeWith(self: *ContractDeleteTransaction, client: *Client) !void {
        try self.base.freezeWith(client);
    }
    
    // Sign the transaction
    pub fn sign(self: *ContractDeleteTransaction, private_key: anytype) !void {
        try self.base.sign(private_key);
    }
    
    // Sign with operator
    pub fn signWithOperator(self: *ContractDeleteTransaction, client: *Client) !void {
        try self.base.signWithOperator(client);
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
            try contract_writer.writeInt64(1, @intCast(contract.entity.shard));
            try contract_writer.writeInt64(2, @intCast(contract.entity.realm));
            try contract_writer.writeInt64(3, @intCast(contract.entity.num));
            const contract_bytes = try contract_writer.toOwnedSlice();
            defer self.base.allocator.free(contract_bytes);
            try delete_writer.writeMessage(1, contract_bytes);
        }
        
        // obtainers = 2 (oneof)
        if (self.transfer_account_id) |account| {
            var account_writer = ProtoWriter.init(self.base.allocator);
            defer account_writer.deinit();
            try account_writer.writeInt64(1, @intCast(account.entity.shard));
            try account_writer.writeInt64(2, @intCast(account.entity.realm));
            try account_writer.writeInt64(3, @intCast(account.entity.num));
            const account_bytes = try account_writer.toOwnedSlice();
            defer self.base.allocator.free(account_bytes);
            try delete_writer.writeMessage(2, account_bytes);
        } else if (self.transfer_contract_id) |contract| {
            var contract_writer = ProtoWriter.init(self.base.allocator);
            defer contract_writer.deinit();
            try contract_writer.writeInt64(1, @intCast(contract.entity.shard));
            try contract_writer.writeInt64(2, @intCast(contract.entity.realm));
            try contract_writer.writeInt64(3, @intCast(contract.entity.num));
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