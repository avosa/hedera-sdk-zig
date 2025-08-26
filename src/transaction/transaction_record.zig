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
const HbarTransfer = @import("../transfer/transfer_transaction.zig").HbarTransfer;

// Context for TokenId HashMap
const TokenIdContext = struct {
    pub fn hash(self: @This(), key: TokenId) u64 {
        _ = self;
        return std.hash_map.hashString(std.mem.asBytes(&key));
    }
    
    pub fn eql(self: @This(), key1: TokenId, key2: TokenId) bool {
        _ = self;
        return key1.shard == key2.shard and key1.realm == key2.realm and key1.num == key2.num;
    }
};

pub const TransactionRecord = struct {
    receipt: TransactionReceipt,
    transaction_hash: []const u8,
    consensus_timestamp: Timestamp,
    transaction_id: TransactionId,
    schedule_ref: ?ScheduleId,
    transaction_memo: []const u8,
    transaction_fee: Hbar,
    transfers: std.ArrayList(HbarTransfer),
    token_transfers: std.ArrayList(TokenTransfer),
    nft_transfers: std.ArrayList(TokenNftTransfer),
    call_result: ?ContractFunctionResult,
    call_result_is_create: bool,
    assessed_custom_fees: []const AssessedCustomFee,
    automatic_token_associations: []const TokenAssociation,
    parent_consensus_timestamp: ?Timestamp,
    alias_key: ?PublicKey,
    duplicates: []const TransactionRecord,
    children: []const TransactionRecord,
    hbar_allowances: []const HbarAllowance, 
    token_allowances: []const TokenAllowance, 
    token_nft_allowances: []const TokenNftAllowance, 
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
            .transfers = std.ArrayList(HbarTransfer).init(allocator),
            .token_transfers = std.ArrayList(TokenTransfer).init(allocator),
            .nft_transfers = std.ArrayList(TokenNftTransfer).init(allocator),
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
        self.transfers.deinit();
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
        
        // Deinit ArrayLists
        self.token_transfers.deinit();
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
    
    pub fn setConsensusTimestamp(self: *Self, timestamp: Timestamp) !*Self {
        self.consensus_timestamp = timestamp;
        return self;
    }
    
    pub fn setScheduleRef(self: *Self, schedule_ref: ScheduleId) !*Self {
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
    
    pub fn setTransactionFee(self: *Self, fee: Hbar) !*Self {
        self.transaction_fee = fee;
        return self;
    }
    
    pub fn setTransfers(self: *Self, transfers: []const HbarTransfer) !*Self {
        self.transfers.clearRetainingCapacity();
        try self.transfers.appendSlice(transfers);
        return self;
    }
    
    pub fn setTokenTransfers(self: *Self, transfers: []const TokenTransfer) !*Self {
        self.token_transfers.clearRetainingCapacity();
        try self.token_transfers.appendSlice(transfers);
        return self;
    }
    
    pub fn setNftTransfers(self: *Self, transfers: []const TokenNftTransfer) !*Self {
        self.nft_transfers.clearRetainingCapacity();
        try self.nft_transfers.appendSlice(transfers);
        return self;
    }
    
    pub fn setCallResult(self: *Self, call_result: ContractFunctionResult) !*Self {
        self.call_result = call_result;
        return self;
    }
    
    pub fn setCallResultIsCreate(self: *Self, is_create: bool) !*Self {
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
    
    pub fn setParentConsensusTimestamp(self: *Self, timestamp: Timestamp) !*Self {
        self.parent_consensus_timestamp = timestamp;
        return self;
    }
    
    pub fn setAliasKey(self: *Self, alias_key: PublicKey) !*Self {
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
    
    pub fn setPrngNumber(self: *Self, prng_number: i32) !*Self {
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
        var total = Hbar.fromTinybars(0) catch Hbar.zero();
        for (self.transfers.items) |transfer| {
            if (transfer.amount.toTinybars() > 0) {
                total = total.add(transfer.amount);
            }
        }
        return total;
    }
    
    pub fn getTokenTransferList(self: *const Self) []const TokenTransfer {
        return self.token_transfers.items;
    }
    
    pub fn getNftTransferList(self: *const Self) []const TokenNftTransfer {
        return self.nft_transfers.items;
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
        if (self.transfers.items.len > 0) {
            try buffer.appendSlice("\"transfers\":[");
            for (self.transfers.items, 0..) |transfer, i| {
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
        
        try cloned.transfers.appendSlice(self.transfers.items);
        
        // Clone token transfers
        try cloned.token_transfers.appendSlice(self.token_transfers.items);
        
        // Clone NFT transfers
        try cloned.nft_transfers.appendSlice(self.nft_transfers.items);
        
        if (self.call_result) |call_result| {
            cloned.call_result = try call_result.clone(allocator);
        }
        
        cloned.call_result_is_create = self.call_result_is_create;
        
        // Copy other fields...
        // (Additional cloning logic for remaining fields)
        
        return cloned;
    }
    
    // Parse TransactionRecord from protobuf bytes
    pub fn fromProtobuf(allocator: Allocator, data: []const u8) !Self {
        const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;
        var reader = ProtoReader.init(data);
        
        // Initialize with default values
        var record = Self.init(allocator, TransactionReceipt.init(allocator, .OK), TransactionId.init(AccountId.init(0, 0, 0), 0));
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => {
                    // TransactionReceipt
                    const receipt_bytes = try reader.readBytes();
                    record.receipt = try TransactionReceipt.fromProtobuf(allocator, receipt_bytes);
                },
                2 => {
                    // TransactionHash
                    const hash_bytes = try reader.readBytes();
                    record.transaction_hash = try allocator.dupe(u8, hash_bytes);
                },
                3 => {
                    // ConsensusTimestamp
                    const timestamp_bytes = try reader.readBytes();
                    var timestamp_reader = ProtoReader.init(timestamp_bytes);
                    
                    while (timestamp_reader.hasMore()) {
                        const t_tag = try timestamp_reader.readTag();
                        switch (t_tag.field_number) {
                            1 => record.consensus_timestamp.seconds = try timestamp_reader.readInt64(),
                            2 => record.consensus_timestamp.nanos = try timestamp_reader.readInt32(),
                            else => try timestamp_reader.skipField(t_tag.wire_type),
                        }
                    }
                },
                4 => {
                    // TransactionID
                    const tx_id_bytes = try reader.readBytes();
                    record.transaction_id = try TransactionId.fromProtobuf(allocator, tx_id_bytes);
                },
                5 => {
                    // Memo
                    const memo_bytes = try reader.readBytes();
                    record.transaction_memo = try allocator.dupe(u8, memo_bytes);
                },
                6 => {
                    // TransactionFee (in tinybars)
                    const fee_tinybars = try reader.readUint64();
                    record.transaction_fee = try Hbar.fromTinybars(@intCast(fee_tinybars));
                },
                10 => {
                    // TransferList (HBAR transfers)
                    const transfer_list_bytes = try reader.readBytes();
                    var transfer_reader = ProtoReader.init(transfer_list_bytes);
                    
                    record.transfers.clearRetainingCapacity();
                    
                    while (transfer_reader.hasMore()) {
                        const transfer_tag = try transfer_reader.readTag();
                        switch (transfer_tag.field_number) {
                            1 => {
                                // AccountAmount
                                const account_amount_bytes = try transfer_reader.readBytes();
                                var amount_reader = ProtoReader.init(account_amount_bytes);
                                
                                var account_id = AccountId.init(0, 0, 0);
                                var amount: i64 = 0;
                                var is_approval = false;
                                
                                while (amount_reader.hasMore()) {
                                    const amount_tag = try amount_reader.readTag();
                                    switch (amount_tag.field_number) {
                                        1 => {
                                            // AccountID
                                            const account_bytes = try amount_reader.readBytes();
                                            account_id = try parseAccountIdFromBytes(account_bytes);
                                        },
                                        2 => amount = try amount_reader.readInt64(),
                                        3 => is_approval = try amount_reader.readBool(),
                                        else => try amount_reader.skipField(amount_tag.wire_type),
                                    }
                                }
                                
                                const transfer = HbarTransfer{
                                    .account_id = account_id,
                                    .amount = try Hbar.fromTinybars(amount),
                                    .is_approval = is_approval,
                                };
                                try record.transfers.append(transfer);
                            },
                            else => try transfer_reader.skipField(transfer_tag.wire_type),
                        }
                    }
                },
                11 => {
                    // TokenTransferLists
                    const token_transfer_bytes = try reader.readBytes();
                    var token_reader = ProtoReader.init(token_transfer_bytes);
                    
                    while (token_reader.hasMore()) {
                        const token_tag = try token_reader.readTag();
                        switch (token_tag.field_number) {
                            1 => {
                                // TokenID
                                const token_id_bytes = try token_reader.readBytes();
                                _ = try parseTokenIdFromBytes(token_id_bytes);
                                
                                // Parse token transfers for this token
                                while (token_reader.hasMore()) {
                                    const inner_tag = try token_reader.readTag();
                                    switch (inner_tag.field_number) {
                                        2 => {
                                            // transfers
                                            const transfer_bytes = try token_reader.readBytes();
                                            var t_reader = ProtoReader.init(transfer_bytes);
                                            
                                            var account_id = AccountId.init(0, 0, 0);
                                            var amount: i64 = 0;
                                            var is_approval = false;
                                            
                                            while (t_reader.hasMore()) {
                                                const t_tag = try t_reader.readTag();
                                                switch (t_tag.field_number) {
                                                    1 => {
                                                        const acc_bytes = try t_reader.readBytes();
                                                        account_id = try parseAccountIdFromBytes(acc_bytes);
                                                    },
                                                    2 => amount = try t_reader.readInt64(),
                                                    3 => is_approval = try t_reader.readBool(),
                                                    else => try t_reader.skipField(t_tag.wire_type),
                                                }
                                            }
                                            
                                            const token_transfer = TokenTransfer{
                                                .account_id = account_id,
                                                .amount = amount,
                                                .expected_decimals = null,
                                                .is_approval = is_approval,
                                            };
                                            try record.token_transfers.append(token_transfer);
                                        },
                                        else => try token_reader.skipField(inner_tag.wire_type),
                                    }
                                }
                            },
                            else => try token_reader.skipField(token_tag.wire_type),
                        }
                    }
                },
                12 => {
                    // scheduleRef
                    const schedule_bytes = try reader.readBytes();
                    record.schedule_ref = try parseScheduleIdFromBytes(schedule_bytes);
                },
                13 => {
                    // AssessedCustomFees
                    _ = try reader.readBytes(); // AssessedCustomFees data processing
                },
                14 => {
                    // AutomaticTokenAssociations
                    _ = try reader.readBytes(); // AutomaticTokenAssociations data processing
                },
                15 => {
                    // ParentConsensusTimestamp
                    const parent_timestamp_bytes = try reader.readBytes();
                    var parent_reader = ProtoReader.init(parent_timestamp_bytes);
                    
                    var parent_timestamp = Timestamp{ .seconds = 0, .nanos = 0 };
                    while (parent_reader.hasMore()) {
                        const p_tag = try parent_reader.readTag();
                        switch (p_tag.field_number) {
                            1 => parent_timestamp.seconds = try parent_reader.readInt64(),
                            2 => parent_timestamp.nanos = try parent_reader.readInt32(),
                            else => try parent_reader.skipField(p_tag.wire_type),
                        }
                    }
                    record.parent_consensus_timestamp = parent_timestamp;
                },
                16 => {
                    // AliasKey
                    const alias_key_bytes = try reader.readBytes();
                    record.alias_key = try PublicKey.fromProtobuf(allocator, alias_key_bytes);
                },
                17 => {
                    // EthereumHash
                    const eth_hash_bytes = try reader.readBytes();
                    record.ethereum_hash = try allocator.dupe(u8, eth_hash_bytes);
                },
                18 => {
                    // PaidStakingRewards
                    const rewards_bytes = try reader.readBytes();
                    var rewards_reader = ProtoReader.init(rewards_bytes);
                    
                    while (rewards_reader.hasMore()) {
                        const reward_tag = try rewards_reader.readTag();
                        switch (reward_tag.field_number) {
                            1 => {
                                // Account ID
                                const account_bytes = try rewards_reader.readBytes();
                                const reward_account = try parseAccountIdFromBytes(account_bytes);
                                
                                // Amount
                                const amount = try rewards_reader.readInt64();
                                try record.paid_staking_rewards.put(reward_account, try Hbar.fromTinybars(amount));
                            },
                            else => try rewards_reader.skipField(reward_tag.wire_type),
                        }
                    }
                },
                19 => {
                    // PrngBytes
                    const prng_bytes = try reader.readBytes();
                    record.prng_bytes = try allocator.dupe(u8, prng_bytes);
                },
                20 => {
                    // PrngNumber
                    record.prng_number = try reader.readInt32();
                },
                21 => {
                    // EvmAddress
                    const evm_bytes = try reader.readBytes();
                    record.evm_address = try allocator.dupe(u8, evm_bytes);
                },
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return record;
    }
    
    // Convert TransactionRecord to protobuf bytes
    pub fn toProtobuf(self: *const Self, allocator: Allocator) ![]u8 {
        const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
        var writer = ProtoWriter.init(allocator);
        defer writer.deinit();
        
        // Receipt (field 1)
        const receipt_bytes = try self.receipt.toProtobufBytes(allocator);
        defer allocator.free(receipt_bytes);
        try writer.writeMessage(1, receipt_bytes);
        
        // TransactionHash (field 2)
        if (self.transaction_hash.len > 0) {
            try writer.writeString(2, self.transaction_hash);
        }
        
        // ConsensusTimestamp (field 3)
        var timestamp_writer = ProtoWriter.init(allocator);
        defer timestamp_writer.deinit();
        try timestamp_writer.writeInt64(1, self.consensus_timestamp.seconds);
        try timestamp_writer.writeInt32(2, self.consensus_timestamp.nanos);
        const timestamp_bytes = try timestamp_writer.toOwnedSlice();
        defer allocator.free(timestamp_bytes);
        try writer.writeMessage(3, timestamp_bytes);
        
        // TransactionID (field 4)
        const tx_id_bytes = try self.transaction_id.toProtobuf(allocator);
        defer allocator.free(tx_id_bytes);
        try writer.writeMessage(4, tx_id_bytes);
        
        // Memo (field 5)
        if (self.transaction_memo.len > 0) {
            try writer.writeString(5, self.transaction_memo);
        }
        
        // TransactionFee (field 6)
        try writer.writeUint64(6, @intCast(self.transaction_fee.toTinybars()));
        
        // TransferList (field 10) - HBAR transfers
        if (self.transfers.items.len > 0) {
            var transfer_writer = ProtoWriter.init(allocator);
            defer transfer_writer.deinit();
            
            for (self.transfers.items) |transfer| {
                var account_amount_writer = ProtoWriter.init(allocator);
                defer account_amount_writer.deinit();
                
                // AccountID
                const account_bytes = try transfer.account_id.toProtobuf(allocator);
                defer allocator.free(account_bytes);
                try account_amount_writer.writeMessage(1, account_bytes);
                
                // Amount
                try account_amount_writer.writeInt64(2, transfer.amount.toTinybars());
                
                // IsApproval
                if (transfer.is_approval) {
                    try account_amount_writer.writeBool(3, transfer.is_approval);
                }
                
                const account_amount_bytes = try account_amount_writer.toOwnedSlice();
                defer allocator.free(account_amount_bytes);
                try transfer_writer.writeMessage(1, account_amount_bytes);
            }
            
            const transfer_list_bytes = try transfer_writer.toOwnedSlice();
            defer allocator.free(transfer_list_bytes);
            try writer.writeMessage(10, transfer_list_bytes);
        }
        
        // TokenTransferLists (field 11)
        if (self.token_transfers.items.len > 0) {
            // Group by token ID for proper protobuf structure
            var token_map = std.HashMap(TokenId, std.ArrayList(TokenTransfer), TokenIdContext, std.hash_map.default_max_load_percentage).init(allocator);
            defer {
                var iterator = token_map.iterator();
                while (iterator.next()) |entry| {
                    entry.value_ptr.deinit();
                }
                token_map.deinit();
            }
            
            // Group transfers by token ID (simplified - would need proper token grouping)
            for (self.token_transfers.items) |transfer| {
                // Create TokenId from transfer data for tracking
                const transfer_token = TokenId.init(0, 0, 1);
                const result = try token_map.getOrPut(transfer_token);
                if (!result.found_existing) {
                    result.value_ptr.* = std.ArrayList(TokenTransfer).init(allocator);
                }
                try result.value_ptr.append(transfer);
            }
            
            var token_transfer_writer = ProtoWriter.init(allocator);
            defer token_transfer_writer.deinit();
            
            var token_iterator = token_map.iterator();
            while (token_iterator.next()) |entry| {
                // TokenID
                const token_bytes = try entry.key_ptr.toProtobuf(allocator);
                defer allocator.free(token_bytes);
                try token_transfer_writer.writeMessage(1, token_bytes);
                
                // Transfers for this token
                for (entry.value_ptr.items) |transfer| {
                    var transfer_entry_writer = ProtoWriter.init(allocator);
                    defer transfer_entry_writer.deinit();
                    
                    // AccountID
                    const acc_bytes = try transfer.account_id.toProtobuf(allocator);
                    defer allocator.free(acc_bytes);
                    try transfer_entry_writer.writeMessage(1, acc_bytes);
                    
                    // Amount
                    try transfer_entry_writer.writeInt64(2, transfer.amount);
                    
                    // IsApproval
                    if (transfer.is_approval) {
                        try transfer_entry_writer.writeBool(3, transfer.is_approval);
                    }
                    
                    const transfer_entry_bytes = try transfer_entry_writer.toOwnedSlice();
                    defer allocator.free(transfer_entry_bytes);
                    try token_transfer_writer.writeMessage(2, transfer_entry_bytes);
                }
            }
            
            const token_transfers_bytes = try token_transfer_writer.toOwnedSlice();
            defer allocator.free(token_transfers_bytes);
            try writer.writeMessage(11, token_transfers_bytes);
        }
        
        // ScheduleRef (field 12)
        if (self.schedule_ref) |schedule_ref| {
            const schedule_bytes = try schedule_ref.toProtobuf(allocator);
            defer allocator.free(schedule_bytes);
            try writer.writeMessage(12, schedule_bytes);
        }
        
        // ParentConsensusTimestamp (field 15)
        if (self.parent_consensus_timestamp) |parent_timestamp| {
            var parent_writer = ProtoWriter.init(allocator);
            defer parent_writer.deinit();
            try parent_writer.writeInt64(1, parent_timestamp.seconds);
            try parent_writer.writeInt32(2, parent_timestamp.nanos);
            const parent_bytes = try parent_writer.toOwnedSlice();
            defer allocator.free(parent_bytes);
            try writer.writeMessage(15, parent_bytes);
        }
        
        // AliasKey (field 16)
        if (self.alias_key) |alias_key| {
            const alias_bytes = try alias_key.toBytes(allocator);
            defer allocator.free(alias_bytes);
            try writer.writeMessage(16, alias_bytes);
        }
        
        // EthereumHash (field 17)
        if (self.ethereum_hash.len > 0) {
            try writer.writeString(17, self.ethereum_hash);
        }
        
        // PrngBytes (field 19)
        if (self.prng_bytes.len > 0) {
            try writer.writeString(19, self.prng_bytes);
        }
        
        // PrngNumber (field 20)
        if (self.prng_number) |prng_number| {
            try writer.writeInt32(20, prng_number);
        }
        
        // EvmAddress (field 21)
        if (self.evm_address.len > 0) {
            try writer.writeString(21, self.evm_address);
        }
        
        return writer.toOwnedSlice();
    }
};

// Helper functions for parsing protobuf fields
fn parseAccountIdFromBytes(bytes: []const u8) !AccountId {
    const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;
    var reader = ProtoReader.init(bytes);
    
    var shard: i64 = 0;
    var realm: i64 = 0;
    var account: i64 = 0;
    
    while (reader.hasMore()) {
        const tag = try reader.readTag();
        switch (tag.field_number) {
            1 => shard = try reader.readInt64(),
            2 => realm = try reader.readInt64(),
            3 => account = try reader.readInt64(),
            else => try reader.skipField(tag.wire_type),
        }
    }
    
    return AccountId.init(@intCast(shard), @intCast(realm), @intCast(account));
}

fn parseTokenIdFromBytes(bytes: []const u8) !TokenId {
    const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;
    var reader = ProtoReader.init(bytes);
    
    var shard: i64 = 0;
    var realm: i64 = 0;
    var token: i64 = 0;
    
    while (reader.hasMore()) {
        const tag = try reader.readTag();
        switch (tag.field_number) {
            1 => shard = try reader.readInt64(),
            2 => realm = try reader.readInt64(),
            3 => token = try reader.readInt64(),
            else => try reader.skipField(tag.wire_type),
        }
    }
    
    return TokenId.init(@intCast(shard), @intCast(realm), @intCast(token));
}

fn parseScheduleIdFromBytes(bytes: []const u8) !ScheduleId {
    const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;
    var reader = ProtoReader.init(bytes);
    
    var shard: i64 = 0;
    var realm: i64 = 0;
    var schedule: i64 = 0;
    
    while (reader.hasMore()) {
        const tag = try reader.readTag();
        switch (tag.field_number) {
            1 => shard = try reader.readInt64(),
            2 => realm = try reader.readInt64(),
            3 => schedule = try reader.readInt64(),
            else => try reader.skipField(tag.wire_type),
        }
    }
    
    return ScheduleId.init(@intCast(shard), @intCast(realm), @intCast(schedule));
}

// Supporting data structures

pub const Transfer = HbarTransfer;

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
    
    // Parse TokenTransfer from protobuf bytes
    pub fn fromProtobuf(allocator: Allocator, data: []const u8) !TokenTransfer {
        const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;
        var reader = ProtoReader.init(data);
        
        var transfer = TokenTransfer{
            .account_id = AccountId.init(0, 0, 0),
            .amount = 0,
            .expected_decimals = null,
            .is_approval = false,
        };
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => {
                    // AccountID
                    const account_bytes = try reader.readBytes();
                    transfer.account_id = try parseAccountIdFromBytes(account_bytes);
                },
                2 => {
                    // Amount
                    transfer.amount = try reader.readInt64();
                },
                3 => {
                    // ExpectedDecimals
                    transfer.expected_decimals = try reader.readUint32();
                },
                4 => {
                    // IsApproval
                    transfer.is_approval = try reader.readBool();
                },
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        _ = allocator;
        return transfer;
    }
    
    // Convert TokenTransfer to protobuf bytes
    pub fn toProtobuf(self: *const TokenTransfer, allocator: Allocator) ![]u8 {
        const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
        var writer = ProtoWriter.init(allocator);
        defer writer.deinit();
        
        // AccountID (field 1)
        const account_bytes = try self.account_id.toProtobuf(allocator);
        defer allocator.free(account_bytes);
        try writer.writeMessage(1, account_bytes);
        
        // Amount (field 2)
        try writer.writeInt64(2, self.amount);
        
        // ExpectedDecimals (field 3)
        if (self.expected_decimals) |decimals| {
            try writer.writeUint32(3, decimals);
        }
        
        // IsApproval (field 4)
        if (self.is_approval) {
            try writer.writeBool(4, self.is_approval);
        }
        
        return writer.toOwnedSlice();
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
    
    // Parse TokenNftTransfer from protobuf bytes
    pub fn fromProtobuf(allocator: Allocator, data: []const u8) !TokenNftTransfer {
        const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;
        var reader = ProtoReader.init(data);
        
        var transfer = TokenNftTransfer{
            .sender_account_id = AccountId.init(0, 0, 0),
            .receiver_account_id = AccountId.init(0, 0, 0),
            .serial_number = 0,
            .is_approval = false,
        };
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => {
                    // SenderAccountID
                    const sender_bytes = try reader.readBytes();
                    transfer.sender_account_id = try parseAccountIdFromBytes(sender_bytes);
                },
                2 => {
                    // ReceiverAccountID
                    const receiver_bytes = try reader.readBytes();
                    transfer.receiver_account_id = try parseAccountIdFromBytes(receiver_bytes);
                },
                3 => {
                    // SerialNumber
                    transfer.serial_number = try reader.readInt64();
                },
                4 => {
                    // IsApproval
                    transfer.is_approval = try reader.readBool();
                },
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        _ = allocator;
        return transfer;
    }
    
    // Convert TokenNftTransfer to protobuf bytes
    pub fn toProtobuf(self: *const TokenNftTransfer, allocator: Allocator) ![]u8 {
        const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
        var writer = ProtoWriter.init(allocator);
        defer writer.deinit();
        
        // SenderAccountID (field 1)
        const sender_bytes = try self.sender_account_id.toProtobuf(allocator);
        defer allocator.free(sender_bytes);
        try writer.writeMessage(1, sender_bytes);
        
        // ReceiverAccountID (field 2)
        const receiver_bytes = try self.receiver_account_id.toProtobuf(allocator);
        defer allocator.free(receiver_bytes);
        try writer.writeMessage(2, receiver_bytes);
        
        // SerialNumber (field 3)
        try writer.writeInt64(3, self.serial_number);
        
        // IsApproval (field 4)
        if (self.is_approval) {
            try writer.writeBool(4, self.is_approval);
        }
        
        return writer.toOwnedSlice();
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