const std = @import("std");
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const AccountId = @import("../core/id.zig").AccountId;
const ContractId = @import("../core/id.zig").ContractId;
const FileId = @import("../core/id.zig").FileId;
const Key = @import("../crypto/key.zig").Key;
const Duration = @import("../core/duration.zig").Duration;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const Timestamp = @import("../core/timestamp.zig").Timestamp;

// ContractUpdateTransaction updates a smart contract's properties
pub const ContractUpdateTransaction = struct {
    base: Transaction,
    contract_id: ?ContractId = null,
    expiration_time: ?Timestamp = null,
    admin_key: ?Key = null,
    proxy_account_id: ?AccountId = null,
    auto_renew_period: ?Duration = null,
    file_id: ?FileId = null,
    contract_memo: ?[]const u8 = null,
    max_automatic_token_associations: ?i32 = null,
    auto_renew_account_id: ?AccountId = null,
    staked_account_id: ?AccountId = null,
    staked_node_id: ?i64 = null,
    decline_staking_reward: ?bool = null,
    
    pub fn init(allocator: std.mem.Allocator) ContractUpdateTransaction {
        return ContractUpdateTransaction{
            .base = Transaction.init(allocator),
        };
    }
    
    pub fn deinit(self: *ContractUpdateTransaction) void {
        self.base.deinit();
        if (self.contract_memo) |memo| {
            self.base.allocator.free(memo);
        }
    }
    
    // Set the contract ID to update
    pub fn setContractId(self: *ContractUpdateTransaction, contract_id: ContractId) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.contract_id = contract_id;
    }
    
    // Set expiration time
    pub fn setExpirationTime(self: *ContractUpdateTransaction, expiration_time: Timestamp) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.expiration_time = expiration_time;
    }
    
    // Set admin key
    pub fn setAdminKey(self: *ContractUpdateTransaction, key: Key) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.admin_key = key;
    }
    
    // Set proxy account ID (deprecated)
    pub fn setProxyAccountId(self: *ContractUpdateTransaction, proxy_account_id: AccountId) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.proxy_account_id = proxy_account_id;
    }
    
    // Set auto renew period
    pub fn setAutoRenewPeriod(self: *ContractUpdateTransaction, period: Duration) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.auto_renew_period = period;
    }
    
    // Set file ID
    pub fn setFileId(self: *ContractUpdateTransaction, file_id: FileId) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.file_id = file_id;
    }
    
    // Set contract memo
    pub fn setContractMemo(self: *ContractUpdateTransaction, memo: []const u8) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        
        if (self.contract_memo) |old_memo| {
            self.base.allocator.free(old_memo);
        }
        
        self.contract_memo = try self.base.allocator.dupe(u8, memo);
    }
    
    // Clear contract memo
    pub fn clearContractMemo(self: *ContractUpdateTransaction) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        
        if (self.contract_memo) |memo| {
            self.base.allocator.free(memo);
        }
        
        self.contract_memo = null;
    }
    
    // Set max automatic token associations
    pub fn setMaxAutomaticTokenAssociations(self: *ContractUpdateTransaction, max: i32) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.max_automatic_token_associations = max;
    }
    
    // Set auto renew account ID
    pub fn setAutoRenewAccountId(self: *ContractUpdateTransaction, account_id: AccountId) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.auto_renew_account_id = account_id;
    }
    
    // Clear auto renew account ID
    pub fn clearAutoRenewAccountId(self: *ContractUpdateTransaction) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.auto_renew_account_id = null;
    }
    
    // Set staked account ID
    pub fn setStakedAccountId(self: *ContractUpdateTransaction, account_id: AccountId) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.staked_account_id = account_id;
        self.staked_node_id = null; // Clear node ID when setting account ID
    }
    
    // Set staked node ID
    pub fn setStakedNodeId(self: *ContractUpdateTransaction, node_id: i64) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.staked_node_id = node_id;
        self.staked_account_id = null; // Clear account ID when setting node ID
    }
    
    // Clear staking info
    pub fn clearStakingInfo(self: *ContractUpdateTransaction) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.staked_account_id = null;
        self.staked_node_id = null;
    }
    
    // Set decline staking reward
    pub fn setDeclineStakingReward(self: *ContractUpdateTransaction, decline: bool) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.decline_staking_reward = decline;
    }
    
    // Execute the transaction
    pub fn execute(self: *ContractUpdateTransaction, client: *Client) !TransactionResponse {
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *ContractUpdateTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Write common transaction fields
        try self.base.writeCommonFields(&writer);
        
        // contractUpdateInstance = 9 (oneof data)
        var contract_writer = ProtoWriter.init(self.base.allocator);
        defer contract_writer.deinit();
        
        // contractID = 1
        if (self.contract_id) |contract_id| {
            var id_writer = ProtoWriter.init(self.base.allocator);
            defer id_writer.deinit();
            try id_writer.writeInt64(1, @intCast(contract_id.entity.shard));
            try id_writer.writeInt64(2, @intCast(contract_id.entity.realm));
            try id_writer.writeInt64(3, @intCast(contract_id.entity.num));
            const id_bytes = try id_writer.toOwnedSlice();
            defer self.base.allocator.free(id_bytes);
            try contract_writer.writeMessage(1, id_bytes);
        }
        
        // expirationTime = 2
        if (self.expiration_time) |expiration| {
            var timestamp_writer = ProtoWriter.init(self.base.allocator);
            defer timestamp_writer.deinit();
            try timestamp_writer.writeInt64(1, expiration.seconds);
            try timestamp_writer.writeInt32(2, expiration.nanos);
            const timestamp_bytes = try timestamp_writer.toOwnedSlice();
            defer self.base.allocator.free(timestamp_bytes);
            try contract_writer.writeMessage(2, timestamp_bytes);
        }
        
        // adminKey = 3
        if (self.admin_key) |key| {
            const key_bytes = try key.toProtobuf(self.base.allocator);
            defer self.base.allocator.free(key_bytes);
            try contract_writer.writeMessage(3, key_bytes);
        }
        
        // proxyAccountID = 6 (deprecated)
        if (self.proxy_account_id) |proxy| {
            var proxy_writer = ProtoWriter.init(self.base.allocator);
            defer proxy_writer.deinit();
            try proxy_writer.writeInt64(1, @intCast(proxy.entity.shard));
            try proxy_writer.writeInt64(2, @intCast(proxy.entity.realm));
            try proxy_writer.writeInt64(3, @intCast(proxy.entity.num));
            const proxy_bytes = try proxy_writer.toOwnedSlice();
            defer self.base.allocator.free(proxy_bytes);
            try contract_writer.writeMessage(6, proxy_bytes);
        }
        
        // autoRenewPeriod = 7
        if (self.auto_renew_period) |period| {
            var duration_writer = ProtoWriter.init(self.base.allocator);
            defer duration_writer.deinit();
            try duration_writer.writeInt64(1, period.seconds);
            const duration_bytes = try duration_writer.toOwnedSlice();
            defer self.base.allocator.free(duration_bytes);
            try contract_writer.writeMessage(7, duration_bytes);
        }
        
        // fileID = 8
        if (self.file_id) |file_id| {
            var file_writer = ProtoWriter.init(self.base.allocator);
            defer file_writer.deinit();
            try file_writer.writeInt64(1, @intCast(file_id.entity.shard));
            try file_writer.writeInt64(2, @intCast(file_id.entity.realm));
            try file_writer.writeInt64(3, @intCast(file_id.entity.num));
            const file_bytes = try file_writer.toOwnedSlice();
            defer self.base.allocator.free(file_bytes);
            try contract_writer.writeMessage(8, file_bytes);
        }
        
        // memoWrapper = 9
        if (self.contract_memo) |memo| {
            // Wrap in StringValue
            var memo_writer = ProtoWriter.init(self.base.allocator);
            defer memo_writer.deinit();
            try memo_writer.writeString(1, memo);
            const memo_bytes = try memo_writer.toOwnedSlice();
            defer self.base.allocator.free(memo_bytes);
            try contract_writer.writeMessage(9, memo_bytes);
        }
        
        // maxAutomaticTokenAssociations = 10
        if (self.max_automatic_token_associations) |max| {
            // Wrap in Int32Value
            var max_writer = ProtoWriter.init(self.base.allocator);
            defer max_writer.deinit();
            try max_writer.writeInt32(1, max);
            const max_bytes = try max_writer.toOwnedSlice();
            defer self.base.allocator.free(max_bytes);
            try contract_writer.writeMessage(10, max_bytes);
        }
        
        // autoRenewAccountId = 11
        if (self.auto_renew_account_id) |account_id| {
            var account_writer = ProtoWriter.init(self.base.allocator);
            defer account_writer.deinit();
            try account_writer.writeInt64(1, @intCast(account_id.entity.shard));
            try account_writer.writeInt64(2, @intCast(account_id.entity.realm));
            try account_writer.writeInt64(3, @intCast(account_id.entity.num));
            const account_bytes = try account_writer.toOwnedSlice();
            defer self.base.allocator.free(account_bytes);
            try contract_writer.writeMessage(11, account_bytes);
        }
        
        // stakedAccountId = 13 or stakedNodeId = 14 (oneof staked_id)
        if (self.staked_account_id) |account_id| {
            var staked_writer = ProtoWriter.init(self.base.allocator);
            defer staked_writer.deinit();
            try staked_writer.writeInt64(1, @intCast(account_id.entity.shard));
            try staked_writer.writeInt64(2, @intCast(account_id.entity.realm));
            try staked_writer.writeInt64(3, @intCast(account_id.entity.num));
            const staked_bytes = try staked_writer.toOwnedSlice();
            defer self.base.allocator.free(staked_bytes);
            try contract_writer.writeMessage(13, staked_bytes);
        } else if (self.staked_node_id) |node_id| {
            try contract_writer.writeInt64(14, node_id);
        }
        
        // declineReward = 15
        if (self.decline_staking_reward) |decline| {
            // Wrap in BoolValue
            var decline_writer = ProtoWriter.init(self.base.allocator);
            defer decline_writer.deinit();
            try decline_writer.writeBool(1, decline);
            const decline_bytes = try decline_writer.toOwnedSlice();
            defer self.base.allocator.free(decline_bytes);
            try contract_writer.writeMessage(15, decline_bytes);
        }
        
        const contract_bytes = try contract_writer.toOwnedSlice();
        defer self.base.allocator.free(contract_bytes);
        try writer.writeMessage(9, contract_bytes);
        
        return writer.toOwnedSlice();
    }
};