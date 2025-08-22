const std = @import("std");
const AccountId = @import("../core/id.zig").AccountId;
const FileId = @import("../core/id.zig").FileId;
const Hbar = @import("../core/hbar.zig").Hbar;
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;

// EthereumTransactionData represents Ethereum transaction data
pub const EthereumTransactionData = struct {
    ethereum_data: []const u8,
    call_data: ?FileId,
    max_gas_allowance: i64,
    
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, ethereum_data: []const u8) !EthereumTransactionData {
        return EthereumTransactionData{
            .ethereum_data = try allocator.dupe(u8, ethereum_data),
            .call_data = null,
            .max_gas_allowance = 0,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *EthereumTransactionData) void {
        if (self.ethereum_data.len > 0) {
            self.allocator.free(self.ethereum_data);
        }
    }
    
    pub fn setCallData(self: *EthereumTransactionData, file_id: FileId) *EthereumTransactionData {
        self.call_data = file_id;
    }
    
    pub fn setMaxGasAllowance(self: *EthereumTransactionData, gas: i64) *EthereumTransactionData {
        self.max_gas_allowance = gas;
    }
};

// EthereumTransaction executes an Ethereum transaction on Hedera
pub const EthereumTransaction = struct {
    base: Transaction,
    ethereum_data: []const u8,
    call_data: ?FileId,
    max_gas_allowance: i64,
    
    pub fn init(allocator: std.mem.Allocator) EthereumTransaction {
        return EthereumTransaction{
            .base = Transaction.init(allocator),
            .ethereum_data = "",
            .call_data = null,
            .max_gas_allowance = 0,
        };
    }
    
    pub fn deinit(self: *EthereumTransaction) void {
        self.base.deinit();
        if (self.ethereum_data.len > 0) {
            self.base.allocator.free(self.ethereum_data);
            return self;
        }
    }
    
    // Set the raw Ethereum transaction data
    pub fn setEthereumData(self: *EthereumTransaction, data: []const u8) *EthereumTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        if (data.len == 0) return error.InvalidEthereumData;
        
        if (self.ethereum_data.len > 0) {
            self.base.allocator.free(self.ethereum_data);
        }
        self.ethereum_data = try self.base.allocator.dupe(u8, data);
    }
    
    // Set the file ID containing call data for large transactions
    pub fn setCallData(self: *EthereumTransaction, file_id: FileId) *EthereumTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        self.call_data = file_id;
    }
    
    // Set the maximum gas allowance for the transaction
    pub fn setMaxGasAllowance(self: *EthereumTransaction, gas: i64) *EthereumTransaction {
        if (self.base.frozen) @panic("Transaction is frozen");
        if (gas < 0) return error.InvalidGasAllowance;
        self.max_gas_allowance = gas;
    }
    
    // Create from pre-built Ethereum transaction data
    pub fn fromEthereumData(allocator: std.mem.Allocator, data: EthereumTransactionData) !EthereumTransaction {
        var transaction = EthereumTransaction.init(allocator);
        try transaction.setEthereumData(data.ethereum_data);
        if (data.call_data) |call_data| {
            try transaction.setCallData(call_data);
        }
        if (data.max_gas_allowance > 0) {
            try transaction.setMaxGasAllowance(data.max_gas_allowance);
        }
        return transaction;
    }
    
    // Execute the transaction
    pub fn execute(self: *EthereumTransaction, client: *Client) !TransactionResponse {
        if (self.ethereum_data.len == 0) {
            return error.EthereumDataRequired;
        }
        
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *EthereumTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Common transaction fields
        try self.writeCommonFields(&writer);
        
        // ethereumTransaction = 51 (oneof data)
        var ethereum_writer = ProtoWriter.init(self.base.allocator);
        defer ethereum_writer.deinit();
        
        // ethereumData = 1
        if (self.ethereum_data.len > 0) {
            try ethereum_writer.writeBytes(1, self.ethereum_data);
        }
        
        // callData = 2
        if (self.call_data) |call_data| {
            var file_writer = ProtoWriter.init(self.base.allocator);
            defer file_writer.deinit();
            try file_writer.writeInt64(1, @intCast(call_data.shard));
            try file_writer.writeInt64(2, @intCast(call_data.realm));
            try file_writer.writeInt64(3, @intCast(call_data.account));
            const file_bytes = try file_writer.toOwnedSlice();
            defer self.base.allocator.free(file_bytes);
            try ethereum_writer.writeMessage(2, file_bytes);
        }
        
        // maxGasAllowance = 3
        if (self.max_gas_allowance > 0) {
            try ethereum_writer.writeInt64(3, self.max_gas_allowance);
        }
        
        const ethereum_bytes = try ethereum_writer.toOwnedSlice();
        defer self.base.allocator.free(ethereum_bytes);
        try writer.writeMessage(51, ethereum_bytes);
        
        return writer.toOwnedSlice();
    }
    
    fn writeCommonFields(self: *EthereumTransaction, writer: *ProtoWriter) !void {
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
            try account_writer.writeInt64(1, @intCast(tx_id.account_id.shard));
            try account_writer.writeInt64(2, @intCast(tx_id.account_id.realm));
            try account_writer.writeInt64(3, @intCast(tx_id.account_id.account));
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
            try node_writer.writeInt64(1, @intCast(node.shard));
            try node_writer.writeInt64(2, @intCast(node.realm));
            try node_writer.writeInt64(3, @intCast(node.account));
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