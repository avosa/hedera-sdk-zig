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
    
    // SetContractID sets the contract ID to update
    pub fn SetContractID(self: *ContractUpdateTransaction, contract_id: ContractId) *ContractUpdateTransaction {
        if (self.base.frozen) @panic("transaction is frozen");
        self.contract_id = contract_id;
        return self;
    }
    
    // GetContractID returns the contract ID to update
    pub fn GetContractID(self: *const ContractUpdateTransaction) ContractId {
        return self.contract_id orelse ContractId{};
    }
    
    // SetExpirationTime sets the expiration time for the contract
    pub fn SetExpirationTime(self: *ContractUpdateTransaction, expiration_time: Timestamp) *ContractUpdateTransaction {
        if (self.base.frozen) @panic("transaction is frozen");
        self.expiration_time = expiration_time;
        return self;
    }
    
    // GetExpirationTime returns the expiration time for the contract
    pub fn GetExpirationTime(self: *const ContractUpdateTransaction) Timestamp {
        return self.expiration_time orelse Timestamp{};
    }
    
    // SetAdminKey sets the admin key for the contract
    pub fn SetAdminKey(self: *ContractUpdateTransaction, key: Key) *ContractUpdateTransaction {
        if (self.base.frozen) @panic("transaction is frozen");
        self.admin_key = key;
        return self;
    }
    
    // GetAdminKey returns the admin key for the contract
    pub fn GetAdminKey(self: *const ContractUpdateTransaction) ?Key {
        return self.admin_key;
    }
    
    // SetProxyAccountID sets the proxy account ID (deprecated)
    pub fn SetProxyAccountID(self: *ContractUpdateTransaction, proxy_account_id: AccountId) *ContractUpdateTransaction {
        if (self.base.frozen) @panic("transaction is frozen");
        self.proxy_account_id = proxy_account_id;
        return self;
    }
    
    // GetProxyAccountID returns the proxy account ID (deprecated)
    pub fn GetProxyAccountID(self: *const ContractUpdateTransaction) AccountId {
        return self.proxy_account_id orelse AccountId{};
    }
    
    // SetAutoRenewPeriod sets the auto renew period for the contract
    pub fn SetAutoRenewPeriod(self: *ContractUpdateTransaction, period: Duration) *ContractUpdateTransaction {
        if (self.base.frozen) @panic("transaction is frozen");
        self.auto_renew_period = period;
        return self;
    }
    
    // GetAutoRenewPeriod returns the auto renew period for the contract
    pub fn GetAutoRenewPeriod(self: *const ContractUpdateTransaction) Duration {
        return self.auto_renew_period orelse Duration{};
    }
    
    // SetBytecodeFileID sets the file ID containing new bytecode (deprecated)
    pub fn SetBytecodeFileID(self: *ContractUpdateTransaction, file_id: FileId) *ContractUpdateTransaction {
        if (self.base.frozen) @panic("transaction is frozen");
        self.file_id = file_id;
        return self;
    }
    
    // GetBytecodeFileID returns the file ID containing new bytecode (deprecated)
    pub fn GetBytecodeFileID(self: *const ContractUpdateTransaction) FileId {
        return self.file_id orelse FileId{};
    }
    
    // SetContractMemo sets the memo for the contract
    pub fn SetContractMemo(self: *ContractUpdateTransaction, memo: []const u8) *ContractUpdateTransaction {
        if (self.base.frozen) @panic("transaction is frozen");
        
        if (self.contract_memo) |old_memo| {
            self.base.allocator.free(old_memo);
        }
        
        self.contract_memo = self.base.allocator.dupe(u8, memo) catch @panic("allocation failed");
    }
    
    // GetContractMemo returns the memo for the contract
    pub fn GetContractMemo(self: *const ContractUpdateTransaction) []const u8 {
        return self.contract_memo orelse "";
    }
    
    // ClearContractMemo clears the contract memo
    pub fn ClearContractMemo(self: *ContractUpdateTransaction) *ContractUpdateTransaction {
        if (self.base.frozen) @panic("transaction is frozen");
        
        if (self.contract_memo) |memo| {
            self.base.allocator.free(memo);
        }
        
        self.contract_memo = null;
        return self;
    }
    
    // SetMaxAutomaticTokenAssociations sets the maximum number of automatic token associations
    pub fn SetMaxAutomaticTokenAssociations(self: *ContractUpdateTransaction, max: i32) *ContractUpdateTransaction {
        if (self.base.frozen) @panic("transaction is frozen");
        self.max_automatic_token_associations = max;
        return self;
    }
    
    // GetMaxAutomaticTokenAssociations returns the maximum number of automatic token associations
    pub fn GetMaxAutomaticTokenAssociations(self: *const ContractUpdateTransaction) i32 {
        return self.max_automatic_token_associations orelse 0;
    }
    
    // SetAutoRenewAccountID sets the auto renew account ID for the contract
    pub fn SetAutoRenewAccountID(self: *ContractUpdateTransaction, account_id: AccountId) *ContractUpdateTransaction {
        if (self.base.frozen) @panic("transaction is frozen");
        self.auto_renew_account_id = account_id;
        return self;
    }
    
    // GetAutoRenewAccountID returns the auto renew account ID for the contract
    pub fn GetAutoRenewAccountID(self: *const ContractUpdateTransaction) AccountId {
        return self.auto_renew_account_id orelse AccountId{};
    }
    
    // ClearAutoRenewAccountID clears the auto renew account ID
    pub fn ClearAutoRenewAccountID(self: *ContractUpdateTransaction) *ContractUpdateTransaction {
        if (self.base.frozen) @panic("transaction is frozen");
        self.auto_renew_account_id = null;
        return self;
    }
    
    // SetStakedAccountID sets the staked account ID for the contract
    pub fn SetStakedAccountID(self: *ContractUpdateTransaction, account_id: AccountId) *ContractUpdateTransaction {
        if (self.base.frozen) @panic("transaction is frozen");
        self.staked_account_id = account_id;
        self.staked_node_id = null; // Clear node ID when setting account ID
        return self;
    }
    
    // GetStakedAccountID returns the staked account ID for the contract
    pub fn GetStakedAccountID(self: *const ContractUpdateTransaction) AccountId {
        return self.staked_account_id orelse AccountId{};
    }
    
    // SetStakedNodeID sets the staked node ID for the contract
    pub fn SetStakedNodeID(self: *ContractUpdateTransaction, node_id: i64) *ContractUpdateTransaction {
        if (self.base.frozen) @panic("transaction is frozen");
        self.staked_node_id = node_id;
        self.staked_account_id = null; // Clear account ID when setting node ID
        return self;
    }
    
    // GetStakedNodeID returns the staked node ID for the contract
    pub fn GetStakedNodeID(self: *const ContractUpdateTransaction) i64 {
        return self.staked_node_id orelse 0;
    }
    
    // ClearStakedAccountID clears the staked account ID
    pub fn ClearStakedAccountID(self: *ContractUpdateTransaction) *ContractUpdateTransaction {
        if (self.base.frozen) @panic("transaction is frozen");
        self.staked_account_id = AccountId{ .account = 0 };
        return self;
    }
    
    // ClearStakedNodeID clears the staked node ID
    pub fn ClearStakedNodeID(self: *ContractUpdateTransaction) *ContractUpdateTransaction {
        if (self.base.frozen) @panic("transaction is frozen");
        self.staked_node_id = -1;
        return self;
    }
    
    // SetDeclineStakingReward sets whether to decline staking rewards
    pub fn SetDeclineStakingReward(self: *ContractUpdateTransaction, decline: bool) *ContractUpdateTransaction {
        if (self.base.frozen) @panic("transaction is frozen");
        self.decline_staking_reward = decline;
        return self;
    }
    
    // GetDeclineStakingReward returns whether to decline staking rewards
    pub fn GetDeclineStakingReward(self: *const ContractUpdateTransaction) bool {
        return self.decline_staking_reward orelse false;
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
            try id_writer.writeInt64(1, @intCast(contract_id.shard));
            try id_writer.writeInt64(2, @intCast(contract_id.realm));
            try id_writer.writeInt64(3, @intCast(contract_id.num));
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
            try proxy_writer.writeInt64(1, @intCast(proxy.shard));
            try proxy_writer.writeInt64(2, @intCast(proxy.realm));
            try proxy_writer.writeInt64(3, @intCast(proxy.account));
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
            try file_writer.writeInt64(1, @intCast(file_id.shard));
            try file_writer.writeInt64(2, @intCast(file_id.realm));
            try file_writer.writeInt64(3, @intCast(file_id.num));
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
            try account_writer.writeInt64(1, @intCast(account_id.shard));
            try account_writer.writeInt64(2, @intCast(account_id.realm));
            try account_writer.writeInt64(3, @intCast(account_id.account));
            const account_bytes = try account_writer.toOwnedSlice();
            defer self.base.allocator.free(account_bytes);
            try contract_writer.writeMessage(11, account_bytes);
        }
        
        // stakedAccountId = 13 or stakedNodeId = 14 (oneof staked_id)
        if (self.staked_account_id) |account_id| {
            var staked_writer = ProtoWriter.init(self.base.allocator);
            defer staked_writer.deinit();
            try staked_writer.writeInt64(1, @intCast(account_id.shard));
            try staked_writer.writeInt64(2, @intCast(account_id.realm));
            try staked_writer.writeInt64(3, @intCast(account_id.account));
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