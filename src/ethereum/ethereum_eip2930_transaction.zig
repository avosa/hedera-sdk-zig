const std = @import("std");
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const errors = @import("../core/errors.zig");

// EIP-2930 Ethereum transaction with access list
pub const EthereumEip2930Transaction = struct {
    base: Transaction,
    chain_id: []const u8,
    nonce: u64,
    gas_price: []const u8,
    gas_limit: u64,
    to: ?[]const u8 = null,
    value: []const u8,
    data: []const u8,
    access_list: std.ArrayList(AccessListEntry),
    recovery_id: u8,
    signature_r: []const u8,
    signature_s: []const u8,
    
    const AccessListEntry = struct {
        address: []const u8,
        storage_keys: std.ArrayList([]const u8),
    };
    
    pub fn init(allocator: std.mem.Allocator) EthereumEip2930Transaction {
        return EthereumEip2930Transaction{
            .base = Transaction.init(allocator),
            .chain_id = &[_]u8{},
            .nonce = 0,
            .gas_price = &[_]u8{},
            .gas_limit = 21000,
            .value = &[_]u8{},
            .data = &[_]u8{},
            .access_list = std.ArrayList(AccessListEntry).init(allocator),
            .recovery_id = 0,
            .signature_r = &[_]u8{},
            .signature_s = &[_]u8{},
        };
    }
    
    pub fn deinit(self: *EthereumEip2930Transaction) void {
        self.base.deinit();
        if (self.chain_id.len > 0) self.base.allocator.free(self.chain_id);
        if (self.gas_price.len > 0) self.base.allocator.free(self.gas_price);
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
        if (self.signature_r.len > 0) self.base.allocator.free(self.signature_r);
        if (self.signature_s.len > 0) self.base.allocator.free(self.signature_s);
    }
    
    // Set chain ID
    pub fn setChainId(self: *EthereumEip2930Transaction, chain_id: []const u8) errors.HederaError!*EthereumEip2930Transaction {
        if (self.base.frozen) return errors.HederaError.InvalidTransaction;
        if (self.chain_id.len > 0) self.base.allocator.free(self.chain_id);
        self.chain_id = errors.handleDupeError(self.base.allocator, chain_id) catch return errors.HederaError.OutOfMemory;
        return self;
    }
    
    // Set nonce
    pub fn setNonce(self: *EthereumEip2930Transaction, nonce: u64) errors.HederaError!*EthereumEip2930Transaction {
        if (self.base.frozen) return errors.HederaError.InvalidTransaction;
        self.nonce = nonce;
        return self;
    }
    
    // Set gas price
    pub fn setGasPrice(self: *EthereumEip2930Transaction, gas_price: []const u8) errors.HederaError!*EthereumEip2930Transaction {
        if (self.base.frozen) return errors.HederaError.InvalidTransaction;
        if (self.gas_price.len > 0) self.base.allocator.free(self.gas_price);
        self.gas_price = errors.handleDupeError(self.base.allocator, gas_price) catch return errors.HederaError.OutOfMemory;
        return self;
    }
    
    // Set gas limit
    pub fn setGasLimit(self: *EthereumEip2930Transaction, gas_limit: u64) errors.HederaError!*EthereumEip2930Transaction {
        if (self.base.frozen) return errors.HederaError.InvalidTransaction;
        self.gas_limit = gas_limit;
        return self;
    }
    
    // Set to address
    pub fn setTo(self: *EthereumEip2930Transaction, to: []const u8) errors.HederaError!*EthereumEip2930Transaction {
        if (self.base.frozen) return errors.HederaError.InvalidTransaction;
        if (self.to) |old_to| self.base.allocator.free(old_to);
        self.to = errors.handleDupeError(self.base.allocator, to) catch return errors.HederaError.OutOfMemory;
        return self;
    }
    
    // Set value
    pub fn setValue(self: *EthereumEip2930Transaction, value: []const u8) errors.HederaError!*EthereumEip2930Transaction {
        if (self.base.frozen) return errors.HederaError.InvalidTransaction;
        if (self.value.len > 0) self.base.allocator.free(self.value);
        self.value = errors.handleDupeError(self.base.allocator, value) catch return errors.HederaError.OutOfMemory;
        return self;
    }
    
    // Set data
    pub fn setData(self: *EthereumEip2930Transaction, data: []const u8) errors.HederaError!*EthereumEip2930Transaction {
        if (self.base.frozen) return errors.HederaError.InvalidTransaction;
        if (self.data.len > 0) self.base.allocator.free(self.data);
        self.data = errors.handleDupeError(self.base.allocator, data) catch return errors.HederaError.OutOfMemory;
        return self;
    }
    
    // Add access list entry
    pub fn addAccessListEntry(self: *EthereumEip2930Transaction, address: []const u8, storage_keys: []const []const u8) errors.HederaError!void {
        if (self.base.frozen) return errors.HederaError.InvalidTransaction;
        
        var keys = std.ArrayList([]const u8).init(self.base.allocator);
        for (storage_keys) |key| {
            const duped_key = errors.handleDupeError(self.base.allocator, key) catch return errors.HederaError.OutOfMemory;
            errors.handleAppendError(&keys, duped_key) catch return errors.HederaError.OutOfMemory;
        }
        
        const duped_address = errors.handleDupeError(self.base.allocator, address) catch return errors.HederaError.OutOfMemory;
        errors.handleAppendError(&self.access_list, AccessListEntry{
            .address = duped_address,
            .storage_keys = keys,
        }) catch return errors.HederaError.OutOfMemory;
    }
    
    // Clear access list
    pub fn clearAccessList(self: *EthereumEip2930Transaction) errors.HederaError!void {
        if (self.base.frozen) return errors.HederaError.InvalidTransaction;
        
        for (self.access_list.items) |*entry| {
            self.base.allocator.free(entry.address);
            for (entry.storage_keys.items) |key| {
                self.base.allocator.free(key);
            }
            entry.storage_keys.deinit();
        }
        self.access_list.clearRetainingCapacity();
    }
    
    // Set signature
    pub fn setSignature(self: *EthereumEip2930Transaction, r: []const u8, s: []const u8, recovery_id: u8) errors.HederaError!*EthereumEip2930Transaction {
        if (self.base.frozen) return errors.HederaError.InvalidTransaction;
        
        if (self.signature_r.len > 0) self.base.allocator.free(self.signature_r);
        if (self.signature_s.len > 0) self.base.allocator.free(self.signature_s);
        
        self.signature_r = errors.handleDupeError(self.base.allocator, r) catch return errors.HederaError.OutOfMemory;
        self.signature_s = errors.handleDupeError(self.base.allocator, s) catch return errors.HederaError.OutOfMemory;
        self.recovery_id = recovery_id;
        return self;
    }
    
    // Execute the transaction
    pub fn execute(self: *EthereumEip2930Transaction, client: *Client) !TransactionResponse {
        return try self.base.execute(client);
    }
    
    // Build RLP-encoded transaction
    pub fn toRlp(self: *EthereumEip2930Transaction, allocator: std.mem.Allocator) ![]u8 {
        var rlp = std.ArrayList(u8).init(allocator);
        defer rlp.deinit();
        
        // EIP-2930 transaction type (0x01)
        try rlp.append(0x01);
        
        // Start RLP list encoding
        var list_data = std.ArrayList(u8).init(allocator);
        defer list_data.deinit();
        
        // Encode transaction fields
        try rlpEncodeBytes(&list_data, self.chain_id);
        try rlpEncodeUint(&list_data, self.nonce);
        try rlpEncodeBytes(&list_data, self.gas_price);
        try rlpEncodeUint(&list_data, self.gas_limit);
        
        if (self.to) |to| {
            try rlpEncodeBytes(&list_data, to);
        } else {
            try list_data.append(0x80); // Empty RLP
        }
        
        try rlpEncodeBytes(&list_data, self.value);
        try rlpEncodeBytes(&list_data, self.data);
        
        // Encode access list
        var access_list_data = std.ArrayList(u8).init(allocator);
        defer access_list_data.deinit();
        
        for (self.access_list.items) |entry| {
            var entry_data = std.ArrayList(u8).init(allocator);
            defer entry_data.deinit();
            
            // Encode address
            try rlpEncodeBytes(&entry_data, entry.address);
            
            // Encode storage keys
            var keys_data = std.ArrayList(u8).init(allocator);
            defer keys_data.deinit();
            
            for (entry.storage_keys.items) |key| {
                try rlpEncodeBytes(&keys_data, key);
            }
            
            // Encode storage keys as RLP list
            if (keys_data.items.len <= 55) {
                try entry_data.append(@intCast(0xc0 + keys_data.items.len));
                try entry_data.appendSlice(keys_data.items);
            } else {
                const len_bytes = bytesForInt(keys_data.items.len);
                try entry_data.append(@intCast(0xf7 + len_bytes));
                try writeInt(&entry_data, keys_data.items.len, len_bytes);
                try entry_data.appendSlice(keys_data.items);
            }
            
            // Encode entry as RLP list
            if (entry_data.items.len <= 55) {
                try access_list_data.append(@intCast(0xc0 + entry_data.items.len));
                try access_list_data.appendSlice(entry_data.items);
            } else {
                const len_bytes = bytesForInt(entry_data.items.len);
                try access_list_data.append(@intCast(0xf7 + len_bytes));
                try writeInt(&access_list_data, entry_data.items.len, len_bytes);
                try access_list_data.appendSlice(entry_data.items);
            }
        }
        
        // Encode access list as RLP list
        if (access_list_data.items.len <= 55) {
            try list_data.append(@intCast(0xc0 + access_list_data.items.len));
            try list_data.appendSlice(access_list_data.items);
        } else {
            const len_bytes = bytesForInt(access_list_data.items.len);
            try list_data.append(@intCast(0xf7 + len_bytes));
            try writeInt(&list_data, access_list_data.items.len, len_bytes);
            try list_data.appendSlice(access_list_data.items);
        }
        
        // Encode signature fields
        try rlpEncodeUint(&list_data, self.recovery_id);
        try rlpEncodeBytes(&list_data, self.signature_r);
        try rlpEncodeBytes(&list_data, self.signature_s);
        
        // Encode the complete list
        if (list_data.items.len <= 55) {
            try rlp.append(@intCast(0xc0 + list_data.items.len));
            try rlp.appendSlice(list_data.items);
        } else {
            const len_bytes = bytesForInt(list_data.items.len);
            try rlp.append(@intCast(0xf7 + len_bytes));
            try writeInt(&rlp, list_data.items.len, len_bytes);
            try rlp.appendSlice(list_data.items);
        }
        
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
    
    // Build transaction body for Hedera
    pub fn buildTransactionBody(self: *EthereumEip2930Transaction) ![]u8 {
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
    
    // Parse from RLP bytes
    pub fn fromRlp(allocator: std.mem.Allocator, bytes: []const u8) !EthereumEip2930Transaction {
        if (bytes.len == 0 or bytes[0] != 0x01) {
            return error.InvalidEip2930Transaction;
        }
        
        var transaction = EthereumEip2930Transaction.init(allocator);
        
        // Parse RLP-encoded transaction (skipping type byte)
        var offset: usize = 1;
        
        // Decode list header
        const list_info = try decodeRlpHeader(bytes[offset..]);
        offset += list_info.header_size;
        
        // Decode chain ID
        const chain_id_info = try decodeRlpHeader(bytes[offset..]);
        offset += chain_id_info.header_size;
        transaction.chain_id = try allocator.dupe(u8, bytes[offset..offset + chain_id_info.data_len]);
        offset += chain_id_info.data_len;
        
        // Decode nonce
        const nonce_info = try decodeRlpHeader(bytes[offset..]);
        offset += nonce_info.header_size;
        transaction.nonce = try bytesToU64(bytes[offset..offset + nonce_info.data_len]);
        offset += nonce_info.data_len;
        
        // Decode gas price
        const gas_price_info = try decodeRlpHeader(bytes[offset..]);
        offset += gas_price_info.header_size;
        transaction.gas_price = try allocator.dupe(u8, bytes[offset..offset + gas_price_info.data_len]);
        offset += gas_price_info.data_len;
        
        // Decode gas limit
        const gas_limit_info = try decodeRlpHeader(bytes[offset..]);
        offset += gas_limit_info.header_size;
        transaction.gas_limit = try bytesToU64(bytes[offset..offset + gas_limit_info.data_len]);
        offset += gas_limit_info.data_len;
        
        // Decode to address
        const to_info = try decodeRlpHeader(bytes[offset..]);
        offset += to_info.header_size;
        if (to_info.data_len > 0) {
            transaction.to = try allocator.dupe(u8, bytes[offset..offset + to_info.data_len]);
        }
        offset += to_info.data_len;
        
        // Decode value
        const value_info = try decodeRlpHeader(bytes[offset..]);
        offset += value_info.header_size;
        transaction.value = try allocator.dupe(u8, bytes[offset..offset + value_info.data_len]);
        offset += value_info.data_len;
        
        // Decode data
        const data_info = try decodeRlpHeader(bytes[offset..]);
        offset += data_info.header_size;
        transaction.data = try allocator.dupe(u8, bytes[offset..offset + data_info.data_len]);
        offset += data_info.data_len;
        
        // Decode access list
        const access_list_info = try decodeRlpHeader(bytes[offset..]);
        offset += access_list_info.header_size;
        const access_list_end = offset + access_list_info.data_len;
        
        while (offset < access_list_end) {
            // Decode entry header
            const entry_info = try decodeRlpHeader(bytes[offset..]);
            offset += entry_info.header_size;
            const entry_end = offset + entry_info.data_len;
            
            // Decode address
            const addr_info = try decodeRlpHeader(bytes[offset..]);
            offset += addr_info.header_size;
            const address = bytes[offset..offset + addr_info.data_len];
            offset += addr_info.data_len;
            
            // Decode storage keys list
            const keys_info = try decodeRlpHeader(bytes[offset..]);
            offset += keys_info.header_size;
            const keys_end = offset + keys_info.data_len;
            
            var storage_keys = std.ArrayList([]const u8).init(allocator);
            while (offset < keys_end) {
                const key_info = try decodeRlpHeader(bytes[offset..]);
                offset += key_info.header_size;
                const key = bytes[offset..offset + key_info.data_len];
                try storage_keys.append(try allocator.dupe(u8, key));
                offset += key_info.data_len;
            }
            
            try transaction.access_list.append(AccessListEntry{
                .address = try allocator.dupe(u8, address),
                .storage_keys = storage_keys,
            });
            
            offset = entry_end;
        }
        
        // Decode recovery ID
        const recovery_info = try decodeRlpHeader(bytes[offset..]);
        offset += recovery_info.header_size;
        transaction.recovery_id = if (recovery_info.data_len > 0) bytes[offset] else 0;
        offset += recovery_info.data_len;
        
        // Decode signature R
        const r_info = try decodeRlpHeader(bytes[offset..]);
        offset += r_info.header_size;
        transaction.signature_r = try allocator.dupe(u8, bytes[offset..offset + r_info.data_len]);
        offset += r_info.data_len;
        
        // Decode signature S
        const s_info = try decodeRlpHeader(bytes[offset..]);
        offset += s_info.header_size;
        transaction.signature_s = try allocator.dupe(u8, bytes[offset..offset + s_info.data_len]);
        
        return transaction;
    }
    
    const RlpInfo = struct {
        header_size: usize,
        data_len: usize,
    };
    
    fn decodeRlpHeader(bytes: []const u8) !RlpInfo {
        if (bytes.len == 0) return error.InvalidRlpData;
        
        const first_byte = bytes[0];
        
        if (first_byte < 0x80) {
            return RlpInfo{ .header_size = 0, .data_len = 1 };
        } else if (first_byte <= 0xb7) {
            return RlpInfo{ .header_size = 1, .data_len = first_byte - 0x80 };
        } else if (first_byte <= 0xbf) {
            const len_bytes = first_byte - 0xb7;
            if (bytes.len < 1 + len_bytes) return error.InvalidRlpData;
            const data_len = try bytesToUsize(bytes[1..1 + len_bytes]);
            return RlpInfo{ .header_size = 1 + len_bytes, .data_len = data_len };
        } else if (first_byte <= 0xf7) {
            return RlpInfo{ .header_size = 1, .data_len = first_byte - 0xc0 };
        } else {
            const len_bytes = first_byte - 0xf7;
            if (bytes.len < 1 + len_bytes) return error.InvalidRlpData;
            const data_len = try bytesToUsize(bytes[1..1 + len_bytes]);
            return RlpInfo{ .header_size = 1 + len_bytes, .data_len = data_len };
        }
    }
    
    fn bytesToU64(bytes: []const u8) !u64 {
        if (bytes.len == 0) return 0;
        if (bytes.len > 8) return error.ValueTooLarge;
        
        var value: u64 = 0;
        for (bytes) |byte| {
            value = (value << 8) | byte;
        }
        return value;
    }
    
    fn bytesToUsize(bytes: []const u8) !usize {
        const value = try bytesToU64(bytes);
        return @intCast(value);
    }
};