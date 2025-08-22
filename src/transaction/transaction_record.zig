const std = @import("std");
const Allocator = std.mem.Allocator;
const TransactionReceipt = @import("transaction_receipt.zig").TransactionReceipt;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;
const ScheduleId = @import("../core/id.zig").ScheduleId;
const Timestamp = @import("../core/timestamp.zig").Timestamp;
const Hbar = @import("../core/hbar.zig").Hbar;
const AccountId = @import("../core/id.zig").AccountId;
const TokenId = @import("../core/id.zig").TokenId;
const PublicKey = @import("../crypto/key.zig").PublicKey;
const ContractFunctionResult = @import("../contract/contract_execute.zig").ContractFunctionResult;

pub const TransactionRecord = struct {
    receipt: TransactionReceipt,
    transaction_hash: []const u8,
    consensus_timestamp: Timestamp,
    transaction_id: TransactionId,
    schedule_ref: ?ScheduleId,
    transaction_memo: []const u8,
    transaction_fee: Hbar,
    transfers: []const Transfer,
    token_transfers: std.HashMap(TokenId, []const TokenTransfer, TokenId.HashContext, std.hash_map.default_max_load_percentage),
    nft_transfers: std.HashMap(TokenId, []const TokenNftTransfer, TokenId.HashContext, std.hash_map.default_max_load_percentage),
    call_result: ?ContractFunctionResult,
    call_result_is_create: bool,
    assessed_custom_fees: []const AssessedCustomFee,
    automatic_token_associations: []const TokenAssociation,
    parent_consensus_timestamp: ?Timestamp,
    alias_key: ?PublicKey,
    duplicates: []const TransactionRecord,
    children: []const TransactionRecord,
    hbar_allowances: []const HbarAllowance, // Deprecated but kept for compatibility
    token_allowances: []const TokenAllowance, // Deprecated but kept for compatibility
    token_nft_allowances: []const TokenNftAllowance, // Deprecated but kept for compatibility
    ethereum_hash: []const u8,
    paid_staking_rewards: std.AutoHashMap(AccountId, Hbar),
    prng_bytes: []const u8,
    prng_number: ?i32,
    evm_address: []const u8,
    pending_airdrop_records: []const PendingAirdropRecord,
    allocator: Allocator,
    
    const Self = @This();
    
    pub fn init(allocator: Allocator, receipt: TransactionReceipt, transaction_id: TransactionId) Self {
        return Self{
            .receipt = receipt,
            .transaction_hash = "",
            .consensus_timestamp = Timestamp.now(),
            .transaction_id = transaction_id,
            .schedule_ref = null,
            .transaction_memo = "",
            .transaction_fee = Hbar.fromTinybars(0) catch Hbar.zero(),
            .transfers = &[_]Transfer{},
            .token_transfers = std.HashMap(TokenId, []const TokenTransfer, TokenId.HashContext, std.hash_map.default_max_load_percentage).init(allocator),
            .nft_transfers = std.HashMap(TokenId, []const TokenNftTransfer, TokenId.HashContext, std.hash_map.default_max_load_percentage).init(allocator),
            .call_result = null,
            .call_result_is_create = false,
            .assessed_custom_fees = &[_]AssessedCustomFee{},
            .automatic_token_associations = &[_]TokenAssociation{},
            .parent_consensus_timestamp = null,
            .alias_key = null,
            .duplicates = &[_]TransactionRecord{},
            .children = &[_]TransactionRecord{},
            .hbar_allowances = &[_]HbarAllowance{},
            .token_allowances = &[_]TokenAllowance{},
            .token_nft_allowances = &[_]TokenNftAllowance{},
            .ethereum_hash = "",
            .paid_staking_rewards = std.AutoHashMap(AccountId, Hbar).init(allocator),
            .prng_bytes = "",
            .prng_number = null,
            .evm_address = "",
            .pending_airdrop_records = &[_]PendingAirdropRecord{},
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.receipt.deinit();
        
        if (self.transaction_hash.len > 0) {
            self.allocator.free(self.transaction_hash);
        }
        if (self.transaction_memo.len > 0) {
            self.allocator.free(self.transaction_memo);
        }
        if (self.transfers.len > 0) {
            self.allocator.free(self.transfers);
        }
        if (self.assessed_custom_fees.len > 0) {
            self.allocator.free(self.assessed_custom_fees);
        }
        if (self.automatic_token_associations.len > 0) {
            self.allocator.free(self.automatic_token_associations);
        }
        if (self.duplicates.len > 0) {
            for (self.duplicates) |duplicate| {
                // Note: const items don't need explicit deinit for slices
                _ = duplicate;
            }
            self.allocator.free(self.duplicates);
        }
        if (self.children.len > 0) {
            for (self.children) |child| {
                // Note: const items don't need explicit deinit for slices
                _ = child;
            }
            self.allocator.free(self.children);
        }
        if (self.hbar_allowances.len > 0) {
            self.allocator.free(self.hbar_allowances);
        }
        if (self.token_allowances.len > 0) {
            self.allocator.free(self.token_allowances);
        }
        if (self.token_nft_allowances.len > 0) {
            self.allocator.free(self.token_nft_allowances);
        }
        if (self.ethereum_hash.len > 0) {
            self.allocator.free(self.ethereum_hash);
        }
        if (self.prng_bytes.len > 0) {
            self.allocator.free(self.prng_bytes);
        }
        if (self.evm_address.len > 0) {
            self.allocator.free(self.evm_address);
        }
        if (self.pending_airdrop_records.len > 0) {
            self.allocator.free(self.pending_airdrop_records);
        }
        
        // Deinit hashmaps
        var token_transfers_iter = self.token_transfers.iterator();
        while (token_transfers_iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.token_transfers.deinit();
        
        var nft_transfers_iter = self.nft_transfers.iterator();
        while (nft_transfers_iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.nft_transfers.deinit();
        
        self.paid_staking_rewards.deinit();
    }
    
    pub fn setTransactionHash(self: *Self, allocator: Allocator, hash: []const u8) !*Self {
        if (self.transaction_hash.len > 0) {
            allocator.free(self.transaction_hash);
        }
        self.transaction_hash = try allocator.dupe(u8, hash);
        return self;
    }
    
    pub fn setConsensusTimestamp(self: *Self, timestamp: Timestamp) *Self {
        self.consensus_timestamp = timestamp;
        return self;
    }
    
    pub fn setScheduleRef(self: *Self, schedule_ref: ScheduleId) *Self {
        self.schedule_ref = schedule_ref;
        return self;
    }
    
    pub fn setTransactionMemo(self: *Self, allocator: Allocator, memo: []const u8) !*Self {
        if (self.transaction_memo.len > 0) {
            allocator.free(self.transaction_memo);
        }
        self.transaction_memo = try allocator.dupe(u8, memo);
        return self;
    }
    
    pub fn setTransactionFee(self: *Self, fee: Hbar) *Self {
        self.transaction_fee = fee;
        return self;
    }
    
    pub fn setTransfers(self: *Self, allocator: Allocator, transfers: []const Transfer) !*Self {
        if (self.transfers.len > 0) {
            allocator.free(self.transfers);
        }
        self.transfers = try allocator.dupe(Transfer, transfers);
        return self;
    }
    
    pub fn setTokenTransfers(self: *Self, token_id: TokenId, transfers: []const TokenTransfer) !*Self {
        const owned_transfers = try self.allocator.dupe(TokenTransfer, transfers);
        try self.token_transfers.put(token_id, owned_transfers);
        return self;
    }
    
    pub fn setNftTransfers(self: *Self, token_id: TokenId, transfers: []const TokenNftTransfer) !*Self {
        const owned_transfers = try self.allocator.dupe(TokenNftTransfer, transfers);
        try self.nft_transfers.put(token_id, owned_transfers);
        return self;
    }
    
    pub fn setCallResult(self: *Self, call_result: ContractFunctionResult) *Self {
        self.call_result = call_result;
        return self;
    }
    
    pub fn setCallResultIsCreate(self: *Self, is_create: bool) *Self {
        self.call_result_is_create = is_create;
        return self;
    }
    
    pub fn setAssessedCustomFees(self: *Self, allocator: Allocator, fees: []const AssessedCustomFee) !*Self {
        if (self.assessed_custom_fees.len > 0) {
            allocator.free(self.assessed_custom_fees);
        }
        self.assessed_custom_fees = try allocator.dupe(AssessedCustomFee, fees);
        return self;
    }
    
    pub fn setAutomaticTokenAssociations(self: *Self, allocator: Allocator, associations: []const TokenAssociation) !*Self {
        if (self.automatic_token_associations.len > 0) {
            allocator.free(self.automatic_token_associations);
        }
        self.automatic_token_associations = try allocator.dupe(TokenAssociation, associations);
        return self;
    }
    
    pub fn setParentConsensusTimestamp(self: *Self, timestamp: Timestamp) *Self {
        self.parent_consensus_timestamp = timestamp;
        return self;
    }
    
    pub fn setAliasKey(self: *Self, alias_key: PublicKey) *Self {
        self.alias_key = alias_key;
        return self;
    }
    
    pub fn setEthereumHash(self: *Self, allocator: Allocator, hash: []const u8) !*Self {
        if (self.ethereum_hash.len > 0) {
            allocator.free(self.ethereum_hash);
        }
        self.ethereum_hash = try allocator.dupe(u8, hash);
        return self;
    }
    
    pub fn setPaidStakingReward(self: *Self, account_id: AccountId, reward: Hbar) !*Self {
        try self.paid_staking_rewards.put(account_id, reward);
        return self;
    }
    
    pub fn setPrngBytes(self: *Self, allocator: Allocator, prng_bytes: []const u8) !*Self {
        if (self.prng_bytes.len > 0) {
            allocator.free(self.prng_bytes);
        }
        self.prng_bytes = try allocator.dupe(u8, prng_bytes);
        return self;
    }
    
    pub fn setPrngNumber(self: *Self, prng_number: i32) *Self {
        self.prng_number = prng_number;
        return self;
    }
    
    pub fn setEvmAddress(self: *Self, allocator: Allocator, evm_address: []const u8) !*Self {
        if (self.evm_address.len > 0) {
            allocator.free(self.evm_address);
        }
        self.evm_address = try allocator.dupe(u8, evm_address);
        return self;
    }
    
    pub fn setPendingAirdropRecords(self: *Self, allocator: Allocator, records: []const PendingAirdropRecord) !*Self {
        if (self.pending_airdrop_records.len > 0) {
            allocator.free(self.pending_airdrop_records);
        }
        self.pending_airdrop_records = try allocator.dupe(PendingAirdropRecord, records);
        return self;
    }
    
    pub fn getTotalTransferredHbars(self: *const Self) Hbar {
        var total = Hbar.fromTinybars(0);
        for (self.transfers) |transfer| {
            if (transfer.amount.toTinybars() > 0) {
                total = total.add(transfer.amount);
            }
        }
        return total;
    }
    
    pub fn getTokenTransferList(self: *const Self, token_id: TokenId) ?[]const TokenTransfer {
        return self.token_transfers.get(token_id);
    }
    
    pub fn getNftTransferList(self: *const Self, token_id: TokenId) ?[]const TokenNftTransfer {
        return self.nft_transfers.get(token_id);
    }
    
    pub fn getPaidStakingReward(self: *const Self, account_id: AccountId) ?Hbar {
        return self.paid_staking_rewards.get(account_id);
    }
    
    pub fn getAllPaidStakingRewards(self: *const Self, allocator: Allocator) ![]StakingReward {
        const count = self.paid_staking_rewards.count();
        var rewards = try allocator.alloc(StakingReward, count);
        
        var iterator = self.paid_staking_rewards.iterator();
        var i: usize = 0;
        while (iterator.next()) |entry| {
            rewards[i] = StakingReward{
                .account_id = entry.key_ptr.*,
                .amount = entry.value_ptr.*,
            };
            i += 1;
        }
        
        return rewards;
    }
    
    pub fn isSuccess(self: *const Self) bool {
        return self.receipt.isSuccess();
    }
    
    pub fn validateStatus(self: *const Self) !void {
        try self.receipt.validateStatus();
    }
    
    pub fn toString(self: *const Self, allocator: Allocator) ![]u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        defer buffer.deinit();
        
        const tx_id_str = try self.transaction_id.toString(allocator);
        defer allocator.free(tx_id_str);
        
        try buffer.writer().print("TransactionRecord{{transaction_id={s}, status={s}", .{
            tx_id_str,
            @tagName(self.receipt.status)
        });
        
        if (self.transaction_hash.len > 0) {
            try buffer.writer().print(", hash={s}", .{std.fmt.fmtSliceHexLower(self.transaction_hash)});
        }
        
        try buffer.writer().print(", consensus_timestamp={d}.{d:0>9}", .{
            self.consensus_timestamp.seconds,
            self.consensus_timestamp.nanos
        });
        
        try buffer.writer().print(", fee={s}", .{try self.transaction_fee.toString(allocator)});
        
        if (self.transaction_memo.len > 0) {
            try buffer.writer().print(", memo=\"{s}\"", .{self.transaction_memo});
        }
        
        if (self.transfers.len > 0) {
            try buffer.writer().print(", transfers={d}", .{self.transfers.len});
        }
        
        if (self.token_transfers.count() > 0) {
            try buffer.writer().print(", token_transfers={d}", .{self.token_transfers.count()});
        }
        
        if (self.nft_transfers.count() > 0) {
            try buffer.writer().print(", nft_transfers={d}", .{self.nft_transfers.count()});
        }
        
        if (self.call_result != null) {
            try buffer.appendSlice(", has_contract_result=true");
        }
        
        if (self.duplicates.len > 0) {
            try buffer.writer().print(", duplicates={d}", .{self.duplicates.len});
        }
        
        if (self.children.len > 0) {
            try buffer.writer().print(", children={d}", .{self.children.len});
        }
        
        try buffer.appendSlice("}");
        
        return try allocator.dupe(u8, buffer.items);
    }
    
    pub fn toJson(self: *const Self, allocator: Allocator) ![]u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        defer buffer.deinit();
        
        try buffer.appendSlice("{");
        
        // Transaction ID
        const tx_id_str = try self.transaction_id.toString(allocator);
        defer allocator.free(tx_id_str);
        try buffer.writer().print("\"transactionId\":\"{s}\",", .{tx_id_str});
        
        // Receipt
        const receipt_json = try self.receipt.toJson(allocator);
        defer allocator.free(receipt_json);
        try buffer.writer().print("\"receipt\":{s},", .{receipt_json});
        
        // Transaction hash
        if (self.transaction_hash.len > 0) {
            try buffer.appendSlice("\"transactionHash\":\"");
            for (self.transaction_hash) |byte| {
                try buffer.writer().print("{x:0>2}", .{byte});
            }
            try buffer.appendSlice("\",");
        }
        
        // Consensus timestamp
        try buffer.writer().print("\"consensusTimestamp\":\"{d}.{d:0>9}\",", .{
            self.consensus_timestamp.seconds,
            self.consensus_timestamp.nanos
        });
        
        // Transaction fee
        const fee_str = try self.transaction_fee.toString(allocator);
        defer allocator.free(fee_str);
        try buffer.writer().print("\"transactionFee\":\"{s}\",", .{fee_str});
        
        // Transaction memo
        if (self.transaction_memo.len > 0) {
            try buffer.writer().print("\"transactionMemo\":\"{s}\",", .{self.transaction_memo});
        }
        
        // Transfers
        if (self.transfers.len > 0) {
            try buffer.appendSlice("\"transfers\":[");
            for (self.transfers, 0..) |transfer, i| {
                if (i > 0) try buffer.appendSlice(",");
                const transfer_json = try transfer.toJson(allocator);
                defer allocator.free(transfer_json);
                try buffer.appendSlice(transfer_json);
            }
            try buffer.appendSlice("],");
        }
        
        // Remove trailing comma and close
        if (buffer.items[buffer.items.len - 1] == ',') {
            _ = buffer.pop();
        }
        try buffer.appendSlice("}");
        
        return try allocator.dupe(u8, buffer.items);
    }
    
    pub fn clone(self: *const Self, allocator: Allocator) !Self {
        var cloned = Self.init(allocator, try self.receipt.clone(allocator), self.transaction_id);
        
        if (self.transaction_hash.len > 0) {
            cloned.transaction_hash = try allocator.dupe(u8, self.transaction_hash);
        }
        
        cloned.consensus_timestamp = self.consensus_timestamp;
        
        if (self.schedule_ref) |schedule_ref| {
            cloned.schedule_ref = schedule_ref;
        }
        
        if (self.transaction_memo.len > 0) {
            cloned.transaction_memo = try allocator.dupe(u8, self.transaction_memo);
        }
        
        cloned.transaction_fee = self.transaction_fee;
        
        if (self.transfers.len > 0) {
            cloned.transfers = try allocator.dupe(Transfer, self.transfers);
        }
        
        // Clone token transfers
        var token_transfers_iter = self.token_transfers.iterator();
        while (token_transfers_iter.next()) |entry| {
            const transfers_copy = try allocator.dupe(TokenTransfer, entry.value_ptr.*);
            try cloned.token_transfers.put(entry.key_ptr.*, transfers_copy);
        }
        
        // Clone NFT transfers
        var nft_transfers_iter = self.nft_transfers.iterator();
        while (nft_transfers_iter.next()) |entry| {
            const transfers_copy = try allocator.dupe(TokenNftTransfer, entry.value_ptr.*);
            try cloned.nft_transfers.put(entry.key_ptr.*, transfers_copy);
        }
        
        if (self.call_result) |call_result| {
            cloned.call_result = try call_result.clone(allocator);
        }
        
        cloned.call_result_is_create = self.call_result_is_create;
        
        // Copy other fields...
        // (Additional cloning logic for remaining fields)
        
        return cloned;
    }
};

// Supporting data structures
pub const Transfer = struct {
    account_id: AccountId,
    amount: Hbar,
    is_approval: bool,
    
    pub fn toJson(self: *const Transfer, allocator: Allocator) ![]u8 {
        const account_str = try self.account_id.toString(allocator);
        defer allocator.free(account_str);
        const amount_str = try self.amount.toString(allocator);
        defer allocator.free(amount_str);
        
        return try std.fmt.allocPrint(allocator,
            "{{\"accountId\":\"{s}\",\"amount\":\"{s}\",\"isApproval\":{}}}",
            .{ account_str, amount_str, self.is_approval }
        );
    }
};

pub const TokenTransfer = struct {
    account_id: AccountId,
    amount: i64,
    expected_decimals: ?u32,
    is_approval: bool,
    
    pub fn toJson(self: *const TokenTransfer, allocator: Allocator) ![]u8 {
        const account_str = try self.account_id.toString(allocator);
        defer allocator.free(account_str);
        
        return try std.fmt.allocPrint(allocator,
            "{{\"accountId\":\"{s}\",\"amount\":{d},\"isApproval\":{}}}",
            .{ account_str, self.amount, self.is_approval }
        );
    }
};

pub const TokenNftTransfer = struct {
    sender_account_id: AccountId,
    receiver_account_id: AccountId,
    serial_number: i64,
    is_approval: bool,
    
    pub fn toJson(self: *const TokenNftTransfer, allocator: Allocator) ![]u8 {
        const sender_str = try self.sender_account_id.toString(allocator);
        defer allocator.free(sender_str);
        const receiver_str = try self.receiver_account_id.toString(allocator);
        defer allocator.free(receiver_str);
        
        return try std.fmt.allocPrint(allocator,
            "{{\"senderAccountId\":\"{s}\",\"receiverAccountId\":\"{s}\",\"serialNumber\":{d},\"isApproval\":{}}}",
            .{ sender_str, receiver_str, self.serial_number, self.is_approval }
        );
    }
};

pub const AssessedCustomFee = struct {
    amount: i64,
    token_id: ?TokenId,
    fee_collector_account_id: AccountId,
    payer_account_ids: []const AccountId,
};

pub const TokenAssociation = struct {
    token_id: TokenId,
    account_id: AccountId,
};

pub const HbarAllowance = struct {
    spender_account_id: AccountId,
    owner_account_id: AccountId,
    amount: Hbar,
};

pub const TokenAllowance = struct {
    token_id: TokenId,
    spender_account_id: AccountId,
    owner_account_id: AccountId,
    amount: i64,
    expected_decimals: ?u32,
};

pub const TokenNftAllowance = struct {
    token_id: TokenId,
    spender_account_id: AccountId,
    owner_account_id: AccountId,
    serial_numbers: []const i64,
    approved_for_all: bool,
};

pub const PendingAirdropRecord = struct {
    pending_airdrop_id: PendingAirdropId,
    pending_airdrop_value: PendingAirdropValue,
};

pub const PendingAirdropId = struct {
    sender_id: AccountId,
    receiver_id: AccountId,
    token_reference: union(enum) {
        fungible_token_type: TokenId,
        non_fungible_token: struct {
            token_id: TokenId,
            serial_number: i64,
        },
    },
};

pub const PendingAirdropValue = struct {
    amount: i64,
};

pub const StakingReward = struct {
    account_id: AccountId,
    amount: Hbar,
};