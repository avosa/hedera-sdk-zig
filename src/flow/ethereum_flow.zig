const std = @import("std");
const AccountId = @import("../core/id.zig").AccountId;
const FileId = @import("../core/id.zig").FileId;
const Hbar = @import("../core/hbar.zig").Hbar;
const Client = @import("../network/client.zig").Client;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const EthereumTransaction = @import("../ethereum/ethereum_transaction.zig").EthereumTransaction;
const EthereumTransactionData = @import("../ethereum/ethereum_transaction.zig").EthereumTransactionData;
const FileCreateTransaction = @import("../file/file_create.zig").FileCreateTransaction;
const FileAppendTransaction = @import("../file/file_append.zig").FileAppendTransaction;
const Key = @import("../crypto/key.zig").Key;

const jumbo_transaction_limit = 128_000;

// EthereumFlow executes an Ethereum transaction on Hedera with automatic file creation for large calldata
pub const EthereumFlow = struct {
    ethereum_data: ?*EthereumTransactionData = null,
    call_data_file_id: ?FileId = null,
    max_gas_allowance: ?Hbar = null,
    node_account_ids: std.ArrayList(AccountId),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) EthereumFlow {
        return EthereumFlow{
            .node_account_ids = std.ArrayList(AccountId).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *EthereumFlow) void {
        self.node_account_ids.deinit();
        if (self.ethereum_data) |data| {
            data.deinit();
            self.allocator.destroy(data);
        }
    }
    
    // Set Ethereum data
    pub fn setEthereumData(self: *EthereumFlow, data: *EthereumTransactionData) void {
        if (self.ethereum_data) |old_data| {
            old_data.deinit();
            self.allocator.destroy(old_data);
        }
        self.ethereum_data = data;
    }
    
    // Set Ethereum data from bytes
    pub fn setEthereumDataBytes(self: *EthereumFlow, data: []const u8) !void {
        if (self.ethereum_data) |old_data| {
            old_data.deinit();
            self.allocator.destroy(old_data);
        }
        
        const ethereum_data = try self.allocator.create(EthereumTransactionData);
        ethereum_data.* = try EthereumTransactionData.init(self.allocator, data);
        self.ethereum_data = ethereum_data;
    }
    
    // Set call data file ID
    pub fn setCallDataFileId(self: *EthereumFlow, file_id: FileId) void {
        self.call_data_file_id = file_id;
    }
    
    // Set max gas allowance
    pub fn setMaxGasAllowance(self: *EthereumFlow, max: Hbar) void {
        self.max_gas_allowance = max;
    }
    
    // Set node account IDs
    pub fn setNodeAccountIds(self: *EthereumFlow, nodes: []const AccountId) !void {
        self.node_account_ids.clearRetainingCapacity();
        try self.node_account_ids.appendSlice(nodes);
    }
    
    // Create file for large call data
    fn createFile(self: *EthereumFlow, call_data: []const u8, client: *Client) !FileId {
        // The calldata in the file needs to be hex encoded
        var hex_buffer = try self.allocator.alloc(u8, call_data.len * 2);
        defer self.allocator.free(hex_buffer);
        
        const hex_chars = "0123456789abcdef";
        for (call_data, 0..) |byte, i| {
            hex_buffer[i * 2] = hex_chars[byte >> 4];
            hex_buffer[i * 2 + 1] = hex_chars[byte & 0x0F];
        }
        
        var file_create = FileCreateTransaction.init(self.allocator);
        defer file_create.deinit();
        
        // Set operator public key as file key
        if (client.operator_public_key) |key| {
            var keys = std.ArrayList(Key).init(self.allocator);
            defer keys.deinit();
            try keys.append(key);
            try file_create.setKeys(keys);
        }
        
        if (self.node_account_ids.items.len > 0) {
            file_create.base.node_account_ids = try self.node_account_ids.clone();
        }
        
        // If data is small enough, create in one transaction
        if (hex_buffer.len < 4097) {
            try file_create.setContents(hex_buffer);
            const response = try file_create.execute(client);
            const receipt = try response.getReceipt(client);
            
            if (receipt.file_id == null) {
                return error.FileIdNotReceived;
            }
            
            return receipt.file_id.?;
        }
        
        // For large data, create file with first chunk and append the rest
        try file_create.setContents(hex_buffer[0..4097]);
        const create_response = try file_create.execute(client);
        const create_receipt = try create_response.getReceipt(client);
        
        if (create_receipt.file_id == null) {
            return error.FileIdNotReceived;
        }
        
        const file_id = create_receipt.file_id.?;
        
        // Append remaining data
        var file_append = FileAppendTransaction.init(self.allocator);
        defer file_append.deinit();
        
        try file_append.setFileId(file_id);
        try file_append.setContents(hex_buffer[4097..]);
        file_append.max_chunks = 1000;
        
        const append_response = try file_append.execute(client);
        _ = try append_response.getReceipt(client);
        
        return file_id;
    }
    
    // Execute the flow
    pub fn execute(self: *EthereumFlow, client: *Client) !TransactionResponse {
        if (self.ethereum_data == null) {
            return error.NoEthereumDataProvided;
        }
        
        var ethereum_transaction = EthereumTransaction.init(self.allocator);
        defer ethereum_transaction.deinit();
        
        if (self.node_account_ids.items.len > 0) {
            ethereum_transaction.base.node_account_ids = try self.node_account_ids.clone();
        }
        
        const data_bytes = self.ethereum_data.?.ethereum_data;
        
        if (self.max_gas_allowance) |max_gas| {
            try ethereum_transaction.setMaxGasAllowance(max_gas.toTinybars());
        }
        
        if (self.call_data_file_id) |file_id| {
            // Check that ethereum data doesn't already contain call data
            if (data_bytes.len != 0) {
                return error.CallDataAlreadyPresent;
            }
            
            try ethereum_transaction.setEthereumData(data_bytes);
            try ethereum_transaction.setCallData(file_id);
        } else if (data_bytes.len <= jumbo_transaction_limit) {
            // Data fits in a single transaction
            try ethereum_transaction.setEthereumData(data_bytes);
        } else {
            // Data is too large, need to create a file
            // Extract call data from ethereum data
            const call_data = self.ethereum_data.?.ethereum_data;
            
            // Create file with call data
            const file_id = try self.createFile(call_data, client);
            
            // Clear call data from ethereum data and set file ID
            self.ethereum_data.?.ethereum_data = &[_]u8{};
            try ethereum_transaction.setEthereumData(&[_]u8{});
            try ethereum_transaction.setCallData(file_id);
        }
        
        const response = try ethereum_transaction.execute(client);
        _ = try response.getReceipt(client);
        
        return response;
    }
};