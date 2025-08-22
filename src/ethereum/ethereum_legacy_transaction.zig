const std = @import("std");
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;

// Legacy Ethereum transaction (pre-EIP-1559)
pub const EthereumLegacyTransaction = struct {
    base: Transaction,
    nonce: u64,
    gas_price: []const u8,
    gas_limit: u64,
    to: ?[]const u8 = null,
    value: []const u8,
    data: []const u8,
    v: []const u8,
    r: []const u8,
    s: []const u8,
    
    pub fn init(allocator: std.mem.Allocator) EthereumLegacyTransaction {
        return EthereumLegacyTransaction{
            .base = Transaction.init(allocator),
            .nonce = 0,
            .gas_price = &[_]u8{},
            .gas_limit = 21000,
            .value = &[_]u8{},
            .data = &[_]u8{},
            .v = &[_]u8{},
            .r = &[_]u8{},
            .s = &[_]u8{},
        };
    }
    
    pub fn deinit(self: *EthereumLegacyTransaction) void {
        self.base.deinit();
        if (self.gas_price.len > 0) self.base.allocator.free(self.gas_price);
        if (self.to) |to| self.base.allocator.free(to);
        if (self.value.len > 0) self.base.allocator.free(self.value);
        if (self.data.len > 0) self.base.allocator.free(self.data);
        if (self.v.len > 0) self.base.allocator.free(self.v);
        if (self.r.len > 0) self.base.allocator.free(self.r);
        if (self.s.len > 0) self.base.allocator.free(self.s);
    }
    
    // Set nonce
    pub fn setNonce(self: *EthereumLegacyTransaction, nonce: u64) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.nonce = nonce;
    }
    
    // Set gas price
    pub fn setGasPrice(self: *EthereumLegacyTransaction, gas_price: []const u8) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        if (self.gas_price.len > 0) self.base.allocator.free(self.gas_price);
        self.gas_price = try self.base.allocator.dupe(u8, gas_price);
    }
    
    // Set gas limit
    pub fn setGasLimit(self: *EthereumLegacyTransaction, gas_limit: u64) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.gas_limit = gas_limit;
    }
    
    // Set to address
    pub fn setTo(self: *EthereumLegacyTransaction, to: []const u8) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        if (self.to) |old_to| self.base.allocator.free(old_to);
        self.to = try self.base.allocator.dupe(u8, to);
    }
    
    // Set value
    pub fn setValue(self: *EthereumLegacyTransaction, value: []const u8) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        if (self.value.len > 0) self.base.allocator.free(self.value);
        self.value = try self.base.allocator.dupe(u8, value);
    }
    
    // Set data
    pub fn setData(self: *EthereumLegacyTransaction, data: []const u8) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        if (self.data.len > 0) self.base.allocator.free(self.data);
        self.data = try self.base.allocator.dupe(u8, data);
    }
    
    // Set signature
    pub fn setSignature(self: *EthereumLegacyTransaction, v: []const u8, r: []const u8, s: []const u8) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        
        if (self.v.len > 0) self.base.allocator.free(self.v);
        if (self.r.len > 0) self.base.allocator.free(self.r);
        if (self.s.len > 0) self.base.allocator.free(self.s);
        
        self.v = try self.base.allocator.dupe(u8, v);
        self.r = try self.base.allocator.dupe(u8, r);
        self.s = try self.base.allocator.dupe(u8, s);
    }
    
    // Execute the transaction
    pub fn execute(self: *EthereumLegacyTransaction, client: *Client) !TransactionResponse {
        return try self.base.execute(client);
    }
    
    // Build RLP-encoded transaction
    pub fn toRlp(self: *EthereumLegacyTransaction, allocator: std.mem.Allocator) ![]u8 {
        var list_data = std.ArrayList(u8).init(allocator);
        defer list_data.deinit();
        
        // Encode all fields in order
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
        try rlpEncodeBytes(&list_data, self.v);
        try rlpEncodeBytes(&list_data, self.r);
        try rlpEncodeBytes(&list_data, self.s);
        
        // Encode as RLP list
        var rlp = std.ArrayList(u8).init(allocator);
        
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
    pub fn buildTransactionBody(self: *EthereumLegacyTransaction) ![]u8 {
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
    pub fn fromRlp(allocator: std.mem.Allocator, bytes: []const u8) !EthereumLegacyTransaction {
        var transaction = EthereumLegacyTransaction.init(allocator);
        var offset: usize = 0;
        
        // Decode list header
        const list_info = try decodeRlpHeader(bytes[offset..]);
        offset += list_info.header_size;
        
        // Decode nonce
        const nonce_info = try decodeRlpHeader(bytes[offset..]);
        offset += nonce_info.header_size;
        if (nonce_info.data_len > 0) {
            transaction.nonce = try bytesToU64(bytes[offset..offset + nonce_info.data_len]);
        }
        offset += nonce_info.data_len;
        
        // Decode gas price
        const gas_price_info = try decodeRlpHeader(bytes[offset..]);
        offset += gas_price_info.header_size;
        transaction.gas_price = try allocator.dupe(u8, bytes[offset..offset + gas_price_info.data_len]);
        offset += gas_price_info.data_len;
        
        // Decode gas limit
        const gas_limit_info = try decodeRlpHeader(bytes[offset..]);
        offset += gas_limit_info.header_size;
        if (gas_limit_info.data_len > 0) {
            transaction.gas_limit = try bytesToU64(bytes[offset..offset + gas_limit_info.data_len]);
        }
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
        
        // Decode V
        const v_info = try decodeRlpHeader(bytes[offset..]);
        offset += v_info.header_size;
        transaction.v = try allocator.dupe(u8, bytes[offset..offset + v_info.data_len]);
        offset += v_info.data_len;
        
        // Decode R
        const r_info = try decodeRlpHeader(bytes[offset..]);
        offset += r_info.header_size;
        transaction.r = try allocator.dupe(u8, bytes[offset..offset + r_info.data_len]);
        offset += r_info.data_len;
        
        // Decode S
        const s_info = try decodeRlpHeader(bytes[offset..]);
        offset += s_info.header_size;
        transaction.s = try allocator.dupe(u8, bytes[offset..offset + s_info.data_len]);
        
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
    
    // Create from separate components
    pub fn fromComponents(
        allocator: std.mem.Allocator,
        nonce: u64,
        gas_price: []const u8,
        gas_limit: u64,
        to: ?[]const u8,
        value: []const u8,
        data: []const u8,
        v: []const u8,
        r: []const u8,
        s: []const u8,
    ) !EthereumLegacyTransaction {
        var transaction = EthereumLegacyTransaction.init(allocator);
        
        transaction.nonce = nonce;
        transaction.gas_price = try allocator.dupe(u8, gas_price);
        transaction.gas_limit = gas_limit;
        if (to) |to_addr| {
            transaction.to = try allocator.dupe(u8, to_addr);
        }
        transaction.value = try allocator.dupe(u8, value);
        transaction.data = try allocator.dupe(u8, data);
        transaction.v = try allocator.dupe(u8, v);
        transaction.r = try allocator.dupe(u8, r);
        transaction.s = try allocator.dupe(u8, s);
        
        return transaction;
    }
};