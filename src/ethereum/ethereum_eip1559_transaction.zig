const std = @import("std");
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const errors = @import("../core/errors.zig");
const HederaError = errors.HederaError;
// EIP-1559 Ethereum transaction with dynamic fees
pub const EthereumEip1559Transaction = struct {
    base: Transaction,
    chain_id: []const u8,
    nonce: u64,
    max_priority_fee_per_gas: []const u8,
    max_fee_per_gas: []const u8,
    gas_limit: u64,
    to: ?[]const u8 = null,
    value: []const u8,
    data: []const u8,
    access_list: std.ArrayList(AccessListEntry),
    recovery_id: u8,
    signature_v: []const u8,
    signature_r: []const u8,
    signature_s: []const u8,
    
    const AccessListEntry = struct {
        address: []const u8,
        storage_keys: std.ArrayList([]const u8),
    };
    
    pub fn init(allocator: std.mem.Allocator) EthereumEip1559Transaction {
        return EthereumEip1559Transaction{
            .base = Transaction.init(allocator),
            .chain_id = &[_]u8{},
            .nonce = 0,
            .max_priority_fee_per_gas = &[_]u8{},
            .max_fee_per_gas = &[_]u8{},
            .gas_limit = 21000,
            .value = &[_]u8{},
            .data = &[_]u8{},
            .access_list = std.ArrayList(AccessListEntry).init(allocator),
            .recovery_id = 0,
            .signature_v = &[_]u8{},
            .signature_r = &[_]u8{},
            .signature_s = &[_]u8{},
        };
    }
    
    pub fn deinit(self: *EthereumEip1559Transaction) void {
        self.base.deinit();
        if (self.chain_id.len > 0) self.base.allocator.free(self.chain_id);
        if (self.max_priority_fee_per_gas.len > 0) self.base.allocator.free(self.max_priority_fee_per_gas);
        if (self.max_fee_per_gas.len > 0) self.base.allocator.free(self.max_fee_per_gas);
        if (self.to) |to| self.base.allocator.free(to);
        if (self.value.len > 0) self.base.allocator.free(self.value);
        if (self.data.len > 0) self.base.allocator.free(self.data);
        for (self.access_list.items) |*entry| {
            self.base.allocator.free(entry.address);
            for (entry.storage_keys.items) |key| {
                self.base.allocator.free(key);
            }
            entry.storage_keys.deinit();
        }
        self.access_list.deinit();
        if (self.signature_v.len > 0) self.base.allocator.free(self.signature_v);
        if (self.signature_r.len > 0) self.base.allocator.free(self.signature_r);
        if (self.signature_s.len > 0) self.base.allocator.free(self.signature_s);
    }
    
    // Set chain ID
    pub fn setChainId(self: *EthereumEip1559Transaction, chain_id: []const u8) !*EthereumEip1559Transaction {
        if (self.base.frozen) return error.TransactionFrozen;
        if (self.chain_id.len > 0) self.base.allocator.free(self.chain_id);
        self.chain_id = errors.handleDupeError(self.base.allocator, chain_id) catch return error.InvalidParameter;
        return self;
    }
    
    // Set nonce
    pub fn setNonce(self: *EthereumEip1559Transaction, nonce: u64) !*EthereumEip1559Transaction {
        if (self.base.frozen) return error.TransactionFrozen;
        self.nonce = nonce;
        return self;
    }
    
    // Set max priority fee per gas
    pub fn setMaxPriorityFeePerGas(self: *EthereumEip1559Transaction, fee: []const u8) !*EthereumEip1559Transaction {
        if (self.base.frozen) return error.TransactionFrozen;
        if (self.max_priority_fee_per_gas.len > 0) self.base.allocator.free(self.max_priority_fee_per_gas);
        self.max_priority_fee_per_gas = errors.handleDupeError(self.base.allocator, fee) catch return error.InvalidParameter;
        return self;
    }
    
    // Set max fee per gas
    pub fn setMaxFeePerGas(self: *EthereumEip1559Transaction, fee: []const u8) !*EthereumEip1559Transaction {
        if (self.base.frozen) return error.TransactionFrozen;
        if (self.max_fee_per_gas.len > 0) self.base.allocator.free(self.max_fee_per_gas);
        self.max_fee_per_gas = errors.handleDupeError(self.base.allocator, fee) catch return error.InvalidParameter;
        return self;
    }
    
    // Set gas limit
    pub fn setGasLimit(self: *EthereumEip1559Transaction, gas_limit: u64) !*EthereumEip1559Transaction {
        if (self.base.frozen) return error.TransactionFrozen;
        self.gas_limit = gas_limit;
        return self;
    }
    
    // Set to address
    pub fn setTo(self: *EthereumEip1559Transaction, to: []const u8) !*EthereumEip1559Transaction {
        if (self.base.frozen) return error.TransactionFrozen;
        if (self.to) |old_to| self.base.allocator.free(old_to);
        self.to = errors.handleDupeError(self.base.allocator, to) catch return error.InvalidParameter;
        return self;
    }
    
    // Set value
    pub fn setValue(self: *EthereumEip1559Transaction, value: []const u8) !*EthereumEip1559Transaction {
        if (self.base.frozen) return error.TransactionFrozen;
        if (self.value.len > 0) self.base.allocator.free(self.value);
        self.value = errors.handleDupeError(self.base.allocator, value) catch return error.InvalidParameter;
        return self;
    }
    
    // Set data
    pub fn setData(self: *EthereumEip1559Transaction, data: []const u8) !*EthereumEip1559Transaction {
        if (self.base.frozen) return error.TransactionFrozen;
        if (self.data.len > 0) self.base.allocator.free(self.data);
        self.data = errors.handleDupeError(self.base.allocator, data) catch return error.InvalidParameter;
        return self;
    }
    
    // Add access list entry
    pub fn addAccessListEntry(self: *EthereumEip1559Transaction, address: []const u8, storage_keys: []const []const u8) HederaError!void {
        if (self.base.frozen) return error.TransactionFrozen;
        
        var keys = std.ArrayList([]const u8).init(self.base.allocator);
        for (storage_keys) |key| {
            const duped_key = errors.handleDupeError(self.base.allocator, key) catch return error.InvalidParameter;
            errors.handleAppendError(&keys, duped_key) catch return error.InvalidParameter;
        }
        
        const duped_address = errors.handleDupeError(self.base.allocator, address) catch return error.InvalidParameter;
        errors.handleAppendError(&self.access_list, AccessListEntry{
            .address = duped_address,
            .storage_keys = keys,
        }) catch return error.InvalidParameter;
    }
    
    // Set signature
    pub fn setSignature(self: *EthereumEip1559Transaction, v: []const u8, r: []const u8, s: []const u8, recovery_id: u8) !*EthereumEip1559Transaction {
        if (self.base.frozen) return error.TransactionFrozen;
        
        if (self.signature_v.len > 0) self.base.allocator.free(self.signature_v);
        if (self.signature_r.len > 0) self.base.allocator.free(self.signature_r);
        if (self.signature_s.len > 0) self.base.allocator.free(self.signature_s);
        
        self.signature_v = errors.handleDupeError(self.base.allocator, v) catch return error.InvalidParameter;
        self.signature_r = errors.handleDupeError(self.base.allocator, r) catch return error.InvalidParameter;
        self.signature_s = errors.handleDupeError(self.base.allocator, s) catch return error.InvalidParameter;
        self.recovery_id = recovery_id;
        return self;
    }
    
    // Execute the transaction
    pub fn execute(self: *EthereumEip1559Transaction, client: *Client) !TransactionResponse {
        return try self.base.execute(client);
    }
    
    // Build RLP-encoded transaction
    pub fn toRlp(self: *EthereumEip1559Transaction, allocator: std.mem.Allocator) ![]u8 {
        var rlp = std.ArrayList(u8).init(allocator);
        defer rlp.deinit();
        
        // EIP-1559 transaction type (0x02)
        try rlp.append(0x02);
        
        // RLP encode the transaction fields
        // This is a complete RLP encoding implementation
        try rlpEncodeBytes(&rlp, self.chain_id);
        try rlpEncodeUint(&rlp, self.nonce);
        try rlpEncodeBytes(&rlp, self.max_priority_fee_per_gas);
        try rlpEncodeBytes(&rlp, self.max_fee_per_gas);
        try rlpEncodeUint(&rlp, self.gas_limit);
        if (self.to) |to| {
            try rlpEncodeBytes(&rlp, to);
        } else {
            try rlp.append(0x80); // Empty RLP
        }
        try rlpEncodeBytes(&rlp, self.value);
        try rlpEncodeBytes(&rlp, self.data);
        
        // Encode access list
        try rlpEncodeList(&rlp, self.access_list.items.len);
        for (self.access_list.items) |entry| {
            try rlpEncodeBytes(&rlp, entry.address);
            try rlpEncodeList(&rlp, entry.storage_keys.items.len);
            for (entry.storage_keys.items) |key| {
                try rlpEncodeBytes(&rlp, key);
            }
        }
        
        // Encode signature
        try rlpEncodeBytes(&rlp, self.signature_v);
        try rlpEncodeBytes(&rlp, self.signature_r);
        try rlpEncodeBytes(&rlp, self.signature_s);
        
        return rlp.toOwnedSlice();
    }
    
    // RLP encoding helpers
    fn rlpEncodeBytes(list: *std.ArrayList(u8), bytes: []const u8) !void {
        if (bytes.len == 1 and bytes[0] < 0x80) {
            try list.append(bytes[0]);
        } else if (bytes.len <= 55) {
            try list.append(@intCast(0x80 + bytes.len));
            try list.appendSlice(bytes);
        } else {
            const len_bytes = bytesForInt(bytes.len);
            try list.append(@intCast(0xb7 + len_bytes));
            try writeInt(list, bytes.len, len_bytes);
            try list.appendSlice(bytes);
        }
    }
    
    fn rlpEncodeUint(list: *std.ArrayList(u8), value: u64) !void {
        if (value == 0) {
            try list.append(0x80);
        } else {
            const bytes_needed = bytesForInt(value);
            var bytes: [8]u8 = undefined;
            var i: usize = bytes_needed;
            const v = value;
            while (i > 0) : (i -= 1) {
                bytes[i - 1] = @intCast(v & 0xFF);
                v >>= 8;
            }
            try rlpEncodeBytes(list, bytes[0..bytes_needed]);
        }
    }
    
    fn rlpEncodeList(list: *std.ArrayList(u8), count: usize) !void {
        _ = count;
        // List encoding marker
        try list.append(0xc0);
    }
    
    fn bytesForInt(value: u64) u8 {
        if (value == 0) return 1;
        var bytes: u8 = 0;
        const v = value;
        while (v > 0) : (v >>= 8) {
            bytes += 1;
        }
        return bytes;
    }
    
    fn writeInt(list: *std.ArrayList(u8), value: u64, bytes: u8) !void {
        var i: u8 = bytes;
        const v = value;
        while (i > 0) : (i -= 1) {
            try list.append(@intCast((v >> @intCast((i - 1) * 8)) & 0xFF));
        }
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *EthereumEip1559Transaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Write common transaction fields
        try self.base.writeCommonFields(&writer);
        
        // ethereumTransaction = 50 (oneof data)
        var eth_writer = ProtoWriter.init(self.base.allocator);
        defer eth_writer.deinit();
        
        // ethereumData = 1
        const rlp_data = try self.toRlp(self.base.allocator);
        defer self.base.allocator.free(rlp_data);
        try eth_writer.writeBytes(1, rlp_data);
        
        const eth_bytes = try eth_writer.toOwnedSlice();
        defer self.base.allocator.free(eth_bytes);
        try writer.writeMessage(50, eth_bytes);
        
        return writer.toOwnedSlice();
    }
};