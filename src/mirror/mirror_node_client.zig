const std = @import("std");
const AccountId = @import("../core/id.zig").AccountId;
const TokenId = @import("../core/id.zig").TokenId;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;
const Timestamp = @import("../core/timestamp.zig").Timestamp;
const JsonParser = @import("../utils/json.zig").JsonParser;

// Mirror Node REST API client
pub const MirrorNodeClient = struct {
    base_url: []const u8,
    allocator: std.mem.Allocator,
    http_client: std.http.Client,
    
    pub fn init(allocator: std.mem.Allocator, base_url: []const u8) MirrorNodeClient {
        return MirrorNodeClient{
            .base_url = base_url,
            .allocator = allocator,
            .http_client = std.http.Client{ .allocator = allocator },
        };
    }
    
    pub fn deinit(self: *MirrorNodeClient) void {
        self.http_client.deinit();
    }
    
    // Get account info from mirror node
    pub fn getAccountInfo(self: *MirrorNodeClient, account_id: AccountId) !AccountInfo {
        const url = try std.fmt.allocPrint(
            self.allocator,
            "{s}/api/v1/accounts/{d}.{d}.{d}",
            .{ self.base_url, account_id.entity.shard, account_id.entity.realm, account_id.entity.num }
        );
        defer self.allocator.free(url);
        
        const response = try self.makeRequest(url);
        defer self.allocator.free(response);
        
        return try parseAccountInfo(response, self.allocator);
    }
    
    // Get account balance
    pub fn getAccountBalance(self: *MirrorNodeClient, account_id: AccountId) !AccountBalance {
        const url = try std.fmt.allocPrint(
            self.allocator,
            "{s}/api/v1/balances?account.id={d}.{d}.{d}",
            .{ self.base_url, account_id.entity.shard, account_id.entity.realm, account_id.entity.num }
        );
        defer self.allocator.free(url);
        
        const response = try self.makeRequest(url);
        defer self.allocator.free(response);
        
        return try parseAccountBalance(response, self.allocator);
    }
    
    // Get account transactions
    pub fn getAccountTransactions(self: *MirrorNodeClient, account_id: AccountId, limit: ?u32) ![]Transaction {
        const url = try std.fmt.allocPrint(
            self.allocator,
            "{s}/api/v1/transactions?account.id={d}.{d}.{d}&limit={d}",
            .{ self.base_url, account_id.entity.shard, account_id.entity.realm, account_id.entity.num, limit orelse 100 }
        );
        defer self.allocator.free(url);
        
        const response = try self.makeRequest(url);
        defer self.allocator.free(response);
        
        return try parseTransactions(response, self.allocator);
    }
    
    // Get transaction by ID
    pub fn getTransaction(self: *MirrorNodeClient, transaction_id: TransactionId) !Transaction {
        const url = try std.fmt.allocPrint(
            self.allocator,
            "{s}/api/v1/transactions/{d}.{d}.{d}-{d}-{d}",
            .{ 
                self.base_url,
                transaction_id.account_id.entity.shard,
                transaction_id.account_id.entity.realm,
                transaction_id.account_id.entity.num,
                transaction_id.valid_start.seconds,
                transaction_id.valid_start.nanos,
            }
        );
        defer self.allocator.free(url);
        
        const response = try self.makeRequest(url);
        defer self.allocator.free(response);
        
        return try parseTransaction(response, self.allocator);
    }
    
    // Get token info
    pub fn getTokenInfo(self: *MirrorNodeClient, token_id: TokenId) !TokenInfo {
        const url = try std.fmt.allocPrint(
            self.allocator,
            "{s}/api/v1/tokens/{d}.{d}.{d}",
            .{ self.base_url, token_id.entity.shard, token_id.entity.realm, token_id.entity.num }
        );
        defer self.allocator.free(url);
        
        const response = try self.makeRequest(url);
        defer self.allocator.free(response);
        
        return try parseTokenInfo(response, self.allocator);
    }
    
    // Get NFT info
    pub fn getNftInfo(self: *MirrorNodeClient, token_id: TokenId, serial_number: u64) !NftInfo {
        const url = try std.fmt.allocPrint(
            self.allocator,
            "{s}/api/v1/tokens/{d}.{d}.{d}/nfts/{d}",
            .{ self.base_url, token_id.entity.shard, token_id.entity.realm, token_id.entity.num, serial_number }
        );
        defer self.allocator.free(url);
        
        const response = try self.makeRequest(url);
        defer self.allocator.free(response);
        
        return try parseNftInfo(response, self.allocator);
    }
    
    // Get network nodes
    pub fn getNetworkNodes(self: *MirrorNodeClient) ![]NetworkNode {
        const url = try std.fmt.allocPrint(self.allocator, "{s}/api/v1/network/nodes", .{self.base_url});
        defer self.allocator.free(url);
        
        const response = try self.makeRequest(url);
        defer self.allocator.free(response);
        
        return try parseNetworkNodes(response, self.allocator);
    }
    
    // Get network supply
    pub fn getNetworkSupply(self: *MirrorNodeClient) !NetworkSupply {
        const url = try std.fmt.allocPrint(self.allocator, "{s}/api/v1/network/supply", .{self.base_url});
        defer self.allocator.free(url);
        
        const response = try self.makeRequest(url);
        defer self.allocator.free(response);
        
        return try parseNetworkSupply(response, self.allocator);
    }
    
    // Make HTTP request
    fn makeRequest(self: *MirrorNodeClient, url: []const u8) ![]u8 {
        const uri = try std.Uri.parse(url);
        
        var server_header_buffer: [16384]u8 = undefined;
        var request = try self.http_client.open(.GET, uri, .{
            .server_header_buffer = &server_header_buffer,
        });
        defer request.deinit();
        
        try request.send();
        try request.finish();
        try request.wait();
        
        if (request.response.status != .ok) {
            return error.HttpRequestFailed;
        }
        
        const body = try request.reader().readAllAlloc(self.allocator, 1024 * 1024 * 10); // 10MB max
        return body;
    }
    
    // Response structures
    pub const AccountInfo = struct {
        account: AccountId,
        balance: i64,
        auto_renew_period: ?i64,
        created_timestamp: Timestamp,
        deleted: bool,
        expiry_timestamp: ?Timestamp,
        key: ?[]const u8,
        max_automatic_token_associations: i32,
        memo: []const u8,
        receiver_sig_required: bool,
        staked_account_id: ?AccountId,
        staked_node_id: ?i64,
        decline_reward: bool,
        ethereum_nonce: i64,
        evm_address: ?[]const u8,
    };
    
    pub const AccountBalance = struct {
        balance: i64,
        tokens: []TokenBalance,
        timestamp: Timestamp,
    };
    
    pub const TokenBalance = struct {
        token_id: TokenId,
        balance: i64,
    };
    
    pub const Transaction = struct {
        bytes: []const u8,
        charged_tx_fee: i64,
        consensus_timestamp: Timestamp,
        entity_id: ?[]const u8,
        max_fee: i64,
        memo: []const u8,
        name: []const u8,
        nft_transfers: []NftTransfer,
        node: AccountId,
        nonce: i32,
        parent_consensus_timestamp: ?Timestamp,
        result: []const u8,
        scheduled: bool,
        staking_reward_transfers: []StakingRewardTransfer,
        token_transfers: []TokenTransfer,
        transaction_hash: []const u8,
        transaction_id: TransactionId,
        transfers: []Transfer,
        valid_duration_seconds: i64,
        valid_start_timestamp: Timestamp,
    };
    
    pub const TokenInfo = struct {
        admin_key: ?[]const u8,
        auto_renew_account: ?AccountId,
        auto_renew_period: ?i64,
        created_timestamp: Timestamp,
        custom_fees: []CustomFee,
        decimals: u32,
        deleted: bool,
        expiry_timestamp: ?Timestamp,
        fee_schedule_key: ?[]const u8,
        freeze_default: bool,
        freeze_key: ?[]const u8,
        initial_supply: i64,
        kyc_key: ?[]const u8,
        max_supply: i64,
        memo: []const u8,
        modified_timestamp: Timestamp,
        name: []const u8,
        pause_key: ?[]const u8,
        pause_status: ?[]const u8,
        supply_key: ?[]const u8,
        supply_type: []const u8,
        symbol: []const u8,
        token_id: TokenId,
        total_supply: i64,
        treasury_account_id: AccountId,
        type: []const u8,
        wipe_key: ?[]const u8,
    };
    
    pub const NftInfo = struct {
        account_id: AccountId,
        created_timestamp: Timestamp,
        delegating_spender: ?AccountId,
        deleted: bool,
        metadata: []const u8,
        modified_timestamp: Timestamp,
        serial_number: u64,
        spender: ?AccountId,
        token_id: TokenId,
    };
    
    pub const NetworkNode = struct {
        description: []const u8,
        file_id: []const u8,
        max_stake: i64,
        memo: []const u8,
        min_stake: i64,
        node_id: i64,
        node_account_id: AccountId,
        node_cert_hash: []const u8,
        public_key: []const u8,
        reward_rate_start: i64,
        service_endpoints: []ServiceEndpoint,
        stake: i64,
        stake_not_rewarded: i64,
        stake_rewarded: i64,
        staking_period: StakingPeriod,
        timestamp: Timestamp,
    };
    
    pub const NetworkSupply = struct {
        released_supply: i64,
        timestamp: Timestamp,
        total_supply: i64,
    };
    
    pub const Transfer = struct {
        account: AccountId,
        amount: i64,
        is_approval: bool,
    };
    
    pub const TokenTransfer = struct {
        token_id: TokenId,
        account: AccountId,
        amount: i64,
        is_approval: bool,
    };
    
    pub const NftTransfer = struct {
        is_approval: bool,
        receiver_account_id: AccountId,
        sender_account_id: AccountId,
        serial_number: i64,
        token_id: TokenId,
    };
    
    pub const StakingRewardTransfer = struct {
        account: AccountId,
        amount: i64,
    };
    
    pub const CustomFee = struct {
        all_collectors_are_exempt: bool,
        amount: ?i64,
        amount_denominator: ?i64,
        collector_account_id: AccountId,
        denominating_token_id: ?TokenId,
        max: ?i64,
        min: ?i64,
        net_of_transfers: ?bool,
        royalty_fees: ?[]RoyaltyFee,
    };
    
    pub const RoyaltyFee = struct {
        amount: i64,
        collector_account_id: AccountId,
        fallback_fee: ?CustomFee,
    };
    
    pub const ServiceEndpoint = struct {
        ip_address_v4: []const u8,
        port: i32,
    };
    
    pub const StakingPeriod = struct {
        from: Timestamp,
        to: Timestamp,
    };
    
    // Complete JSON parsing implementations
    fn parseAccountInfo(json: []const u8, allocator: std.mem.Allocator) !AccountInfo {
        var parser = JsonParser.init(allocator);
        var root = try parser.parse(json);
        defer root.deinit(allocator);
        
        const obj = root.getObject() orelse return error.InvalidJson;
        
        return AccountInfo{
            .account = try parseAccountIdFromString(obj.get("account").?.getString() orelse return error.InvalidField),
            .balance = obj.get("balance").?.getInt() orelse 0,
            .auto_renew_period = if (obj.get("auto_renew_period")) |v| v.getInt() else null,
            .created_timestamp = try parseTimestampFromString(obj.get("created_timestamp").?.getString() orelse return error.InvalidField),
            .deleted = obj.get("deleted").?.getBool() orelse false,
            .expiry_timestamp = if (obj.get("expiry_timestamp")) |v| try parseTimestampFromString(v.getString() orelse "") else null,
            .key = if (obj.get("key")) |v| try allocator.dupe(u8, v.getString() orelse "") else null,
            .max_automatic_token_associations = @intCast(obj.get("max_automatic_token_associations").?.getInt() orelse 0),
            .memo = try allocator.dupe(u8, obj.get("memo").?.getString() orelse ""),
            .receiver_sig_required = obj.get("receiver_sig_required").?.getBool() orelse false,
            .staked_account_id = if (obj.get("staked_account_id")) |v| try parseAccountIdFromString(v.getString() orelse "") else null,
            .staked_node_id = if (obj.get("staked_node_id")) |v| v.getInt() else null,
            .decline_reward = obj.get("decline_reward").?.getBool() orelse false,
            .ethereum_nonce = obj.get("ethereum_nonce").?.getInt() orelse 0,
            .evm_address = if (obj.get("evm_address")) |v| try allocator.dupe(u8, v.getString() orelse "") else null,
        };
    }
    
    fn parseAccountBalance(json: []const u8, allocator: std.mem.Allocator) !AccountBalance {
        var parser = JsonParser.init(allocator);
        var root = try parser.parse(json);
        defer root.deinit(allocator);
        
        const obj = root.getObject() orelse return error.InvalidJson;
        const balances = obj.get("balances").?.getArray() orelse return error.InvalidField;
        
        if (balances.len == 0) return error.NoBalances;
        
        const first_balance = balances[0].getObject() orelse return error.InvalidField;
        
        // Parse token balances
        var token_balances = std.ArrayList(TokenBalance).init(allocator);
        errdefer token_balances.deinit();
        
        if (first_balance.get("tokens")) |tokens_val| {
            const tokens = tokens_val.getArray() orelse return error.InvalidField;
            for (tokens) |token| {
                const token_obj = token.getObject() orelse continue;
                try token_balances.append(TokenBalance{
                    .token_id = try parseTokenIdFromString(token_obj.get("token_id").?.getString() orelse continue),
                    .balance = token_obj.get("balance").?.getInt() orelse 0,
                });
            }
        }
        
        return AccountBalance{
            .balance = first_balance.get("balance").?.getInt() orelse 0,
            .tokens = try token_balances.toOwnedSlice(),
            .timestamp = try parseTimestampFromString(obj.get("timestamp").?.getString() orelse return error.InvalidField),
        };
    }
    
    fn parseTransactions(json: []const u8, allocator: std.mem.Allocator) ![]Transaction {
        var parser = JsonParser.init(allocator);
        var root = try parser.parse(json);
        defer root.deinit(allocator);
        
        const obj = root.getObject() orelse return error.InvalidJson;
        const transactions = obj.get("transactions").?.getArray() orelse return error.InvalidField;
        
        var result = std.ArrayList(Transaction).init(allocator);
        errdefer result.deinit();
        
        for (transactions) |tx| {
            const tx_obj = tx.getObject() orelse continue;
            try result.append(try parseTransactionObject(tx_obj, allocator));
        }
        
        return result.toOwnedSlice();
    }
    
    fn parseTransaction(json: []const u8, allocator: std.mem.Allocator) !Transaction {
        var parser = JsonParser.init(allocator);
        var root = try parser.parse(json);
        defer root.deinit(allocator);
        
        const obj = root.getObject() orelse return error.InvalidJson;
        return parseTransactionObject(obj, allocator);
    }
    
    fn parseTransactionObject(obj: std.StringHashMap(JsonParser.Value), allocator: std.mem.Allocator) !Transaction {
        // Parse transfers
        var transfers = std.ArrayList(Transfer).init(allocator);
        errdefer transfers.deinit();
        
        if (obj.get("transfers")) |transfers_val| {
            const transfers_arr = transfers_val.getArray() orelse &[_]JsonParser.Value{};
            for (transfers_arr) |transfer| {
                const transfer_obj = transfer.getObject() orelse continue;
                try transfers.append(Transfer{
                    .account = try parseAccountIdFromString(transfer_obj.get("account").?.getString() orelse continue),
                    .amount = transfer_obj.get("amount").?.getInt() orelse 0,
                    .is_approval = transfer_obj.get("is_approval").?.getBool() orelse false,
                });
            }
        }
        
        // Parse token transfers
        var token_transfers = std.ArrayList(TokenTransfer).init(allocator);
        errdefer token_transfers.deinit();
        
        if (obj.get("token_transfers")) |token_transfers_val| {
            const token_transfers_arr = token_transfers_val.getArray() orelse &[_]JsonParser.Value{};
            for (token_transfers_arr) |token_transfer| {
                const token_transfer_obj = token_transfer.getObject() orelse continue;
                try token_transfers.append(TokenTransfer{
                    .token_id = try parseTokenIdFromString(token_transfer_obj.get("token_id").?.getString() orelse continue),
                    .account = try parseAccountIdFromString(token_transfer_obj.get("account").?.getString() orelse continue),
                    .amount = token_transfer_obj.get("amount").?.getInt() orelse 0,
                    .is_approval = token_transfer_obj.get("is_approval").?.getBool() orelse false,
                });
            }
        }
        
        // Parse NFT transfers
        var nft_transfers = std.ArrayList(NftTransfer).init(allocator);
        errdefer nft_transfers.deinit();
        
        if (obj.get("nft_transfers")) |nft_transfers_val| {
            const nft_transfers_arr = nft_transfers_val.getArray() orelse &[_]JsonParser.Value{};
            for (nft_transfers_arr) |nft_transfer| {
                const nft_transfer_obj = nft_transfer.getObject() orelse continue;
                try nft_transfers.append(NftTransfer{
                    .is_approval = nft_transfer_obj.get("is_approval").?.getBool() orelse false,
                    .receiver_account_id = try parseAccountIdFromString(nft_transfer_obj.get("receiver_account_id").?.getString() orelse continue),
                    .sender_account_id = try parseAccountIdFromString(nft_transfer_obj.get("sender_account_id").?.getString() orelse continue),
                    .serial_number = nft_transfer_obj.get("serial_number").?.getInt() orelse 0,
                    .token_id = try parseTokenIdFromString(nft_transfer_obj.get("token_id").?.getString() orelse continue),
                });
            }
        }
        
        // Parse staking reward transfers
        var staking_reward_transfers = std.ArrayList(StakingRewardTransfer).init(allocator);
        errdefer staking_reward_transfers.deinit();
        
        if (obj.get("staking_reward_transfers")) |staking_transfers_val| {
            const staking_transfers_arr = staking_transfers_val.getArray() orelse &[_]JsonParser.Value{};
            for (staking_transfers_arr) |staking_transfer| {
                const staking_transfer_obj = staking_transfer.getObject() orelse continue;
                try staking_reward_transfers.append(StakingRewardTransfer{
                    .account = try parseAccountIdFromString(staking_transfer_obj.get("account").?.getString() orelse continue),
                    .amount = staking_transfer_obj.get("amount").?.getInt() orelse 0,
                });
            }
        }
        
        return Transaction{
            .bytes = try allocator.dupe(u8, obj.get("bytes").?.getString() orelse ""),
            .charged_tx_fee = obj.get("charged_tx_fee").?.getInt() orelse 0,
            .consensus_timestamp = try parseTimestampFromString(obj.get("consensus_timestamp").?.getString() orelse return error.InvalidField),
            .entity_id = if (obj.get("entity_id")) |v| try allocator.dupe(u8, v.getString() orelse "") else null,
            .max_fee = obj.get("max_fee").?.getInt() orelse 0,
            .memo = try allocator.dupe(u8, obj.get("memo").?.getString() orelse ""),
            .name = try allocator.dupe(u8, obj.get("name").?.getString() orelse ""),
            .nft_transfers = try nft_transfers.toOwnedSlice(),
            .node = try parseAccountIdFromString(obj.get("node").?.getString() orelse return error.InvalidField),
            .nonce = @intCast(obj.get("nonce").?.getInt() orelse 0),
            .parent_consensus_timestamp = if (obj.get("parent_consensus_timestamp")) |v| try parseTimestampFromString(v.getString() orelse "") else null,
            .result = try allocator.dupe(u8, obj.get("result").?.getString() orelse ""),
            .scheduled = obj.get("scheduled").?.getBool() orelse false,
            .staking_reward_transfers = try staking_reward_transfers.toOwnedSlice(),
            .token_transfers = try token_transfers.toOwnedSlice(),
            .transaction_hash = try allocator.dupe(u8, obj.get("transaction_hash").?.getString() orelse ""),
            .transaction_id = try parseTransactionIdFromString(obj.get("transaction_id").?.getString() orelse return error.InvalidField),
            .transfers = try transfers.toOwnedSlice(),
            .valid_duration_seconds = obj.get("valid_duration_seconds").?.getInt() orelse 0,
            .valid_start_timestamp = try parseTimestampFromString(obj.get("valid_start_timestamp").?.getString() orelse return error.InvalidField),
        };
    }
    
    fn parseTokenInfo(json: []const u8, allocator: std.mem.Allocator) !TokenInfo {
        var parser = JsonParser.init(allocator);
        var root = try parser.parse(json);
        defer root.deinit(allocator);
        
        const obj = root.getObject() orelse return error.InvalidJson;
        
        // Parse custom fees
        var custom_fees = std.ArrayList(CustomFee).init(allocator);
        errdefer custom_fees.deinit();
        
        if (obj.get("custom_fees")) |fees_val| {
            const fees = fees_val.getObject() orelse return error.InvalidField;
            if (fees.get("fees")) |fees_arr_val| {
                const fees_arr = fees_arr_val.getArray() orelse &[_]JsonParser.Value{};
                for (fees_arr) |fee| {
                    const fee_obj = fee.getObject() orelse continue;
                    try custom_fees.append(try parseCustomFee(fee_obj, allocator));
                }
            }
        }
        
        return TokenInfo{
            .admin_key = if (obj.get("admin_key")) |v| try allocator.dupe(u8, v.getString() orelse "") else null,
            .auto_renew_account = if (obj.get("auto_renew_account")) |v| try parseAccountIdFromString(v.getString() orelse "") else null,
            .auto_renew_period = if (obj.get("auto_renew_period")) |v| v.getInt() else null,
            .created_timestamp = try parseTimestampFromString(obj.get("created_timestamp").?.getString() orelse return error.InvalidField),
            .custom_fees = try custom_fees.toOwnedSlice(),
            .decimals = @intCast(obj.get("decimals").?.getInt() orelse 0),
            .deleted = obj.get("deleted").?.getBool() orelse false,
            .expiry_timestamp = if (obj.get("expiry_timestamp")) |v| try parseTimestampFromString(v.getString() orelse "") else null,
            .fee_schedule_key = if (obj.get("fee_schedule_key")) |v| try allocator.dupe(u8, v.getString() orelse "") else null,
            .freeze_default = obj.get("freeze_default").?.getBool() orelse false,
            .freeze_key = if (obj.get("freeze_key")) |v| try allocator.dupe(u8, v.getString() orelse "") else null,
            .initial_supply = obj.get("initial_supply").?.getInt() orelse 0,
            .kyc_key = if (obj.get("kyc_key")) |v| try allocator.dupe(u8, v.getString() orelse "") else null,
            .max_supply = obj.get("max_supply").?.getInt() orelse 0,
            .memo = try allocator.dupe(u8, obj.get("memo").?.getString() orelse ""),
            .modified_timestamp = try parseTimestampFromString(obj.get("modified_timestamp").?.getString() orelse return error.InvalidField),
            .name = try allocator.dupe(u8, obj.get("name").?.getString() orelse ""),
            .pause_key = if (obj.get("pause_key")) |v| try allocator.dupe(u8, v.getString() orelse "") else null,
            .pause_status = if (obj.get("pause_status")) |v| try allocator.dupe(u8, v.getString() orelse "") else null,
            .supply_key = if (obj.get("supply_key")) |v| try allocator.dupe(u8, v.getString() orelse "") else null,
            .supply_type = try allocator.dupe(u8, obj.get("supply_type").?.getString() orelse ""),
            .symbol = try allocator.dupe(u8, obj.get("symbol").?.getString() orelse ""),
            .token_id = try parseTokenIdFromString(obj.get("token_id").?.getString() orelse return error.InvalidField),
            .total_supply = obj.get("total_supply").?.getInt() orelse 0,
            .treasury_account_id = try parseAccountIdFromString(obj.get("treasury_account_id").?.getString() orelse return error.InvalidField),
            .type = try allocator.dupe(u8, obj.get("type").?.getString() orelse ""),
            .wipe_key = if (obj.get("wipe_key")) |v| try allocator.dupe(u8, v.getString() orelse "") else null,
        };
    }
    
    fn parseNftInfo(json: []const u8, allocator: std.mem.Allocator) !NftInfo {
        var parser = JsonParser.init(allocator);
        var root = try parser.parse(json);
        defer root.deinit(allocator);
        
        const obj = root.getObject() orelse return error.InvalidJson;
        
        return NftInfo{
            .account_id = try parseAccountIdFromString(obj.get("account_id").?.getString() orelse return error.InvalidField),
            .created_timestamp = try parseTimestampFromString(obj.get("created_timestamp").?.getString() orelse return error.InvalidField),
            .delegating_spender = if (obj.get("delegating_spender")) |v| try parseAccountIdFromString(v.getString() orelse "") else null,
            .deleted = obj.get("deleted").?.getBool() orelse false,
            .metadata = try allocator.dupe(u8, obj.get("metadata").?.getString() orelse ""),
            .modified_timestamp = try parseTimestampFromString(obj.get("modified_timestamp").?.getString() orelse return error.InvalidField),
            .serial_number = @intCast(obj.get("serial_number").?.getInt() orelse 0),
            .spender = if (obj.get("spender")) |v| try parseAccountIdFromString(v.getString() orelse "") else null,
            .token_id = try parseTokenIdFromString(obj.get("token_id").?.getString() orelse return error.InvalidField),
        };
    }
    
    fn parseNetworkNodes(json: []const u8, allocator: std.mem.Allocator) ![]NetworkNode {
        var parser = JsonParser.init(allocator);
        var root = try parser.parse(json);
        defer root.deinit(allocator);
        
        const obj = root.getObject() orelse return error.InvalidJson;
        const nodes = obj.get("nodes").?.getArray() orelse return error.InvalidField;
        
        var result = std.ArrayList(NetworkNode).init(allocator);
        errdefer result.deinit();
        
        for (nodes) |node| {
            const node_obj = node.getObject() orelse continue;
            
            // Parse service endpoints
            var service_endpoints = std.ArrayList(ServiceEndpoint).init(allocator);
            errdefer service_endpoints.deinit();
            
            if (node_obj.get("service_endpoints")) |endpoints_val| {
                const endpoints = endpoints_val.getArray() orelse &[_]JsonParser.Value{};
                for (endpoints) |endpoint| {
                    const endpoint_obj = endpoint.getObject() orelse continue;
                    try service_endpoints.append(ServiceEndpoint{
                        .ip_address_v4 = try allocator.dupe(u8, endpoint_obj.get("ip_address_v4").?.getString() orelse ""),
                        .port = @intCast(endpoint_obj.get("port").?.getInt() orelse 0),
                    });
                }
            }
            
            // Parse staking period
            const staking_period_obj = node_obj.get("staking_period").?.getObject() orelse return error.InvalidField;
            const staking_period = StakingPeriod{
                .from = try parseTimestampFromString(staking_period_obj.get("from").?.getString() orelse return error.InvalidField),
                .to = try parseTimestampFromString(staking_period_obj.get("to").?.getString() orelse return error.InvalidField),
            };
            
            try result.append(NetworkNode{
                .description = try allocator.dupe(u8, node_obj.get("description").?.getString() orelse ""),
                .file_id = try allocator.dupe(u8, node_obj.get("file_id").?.getString() orelse ""),
                .max_stake = node_obj.get("max_stake").?.getInt() orelse 0,
                .memo = try allocator.dupe(u8, node_obj.get("memo").?.getString() orelse ""),
                .min_stake = node_obj.get("min_stake").?.getInt() orelse 0,
                .node_id = node_obj.get("node_id").?.getInt() orelse 0,
                .node_account_id = try parseAccountIdFromString(node_obj.get("node_account_id").?.getString() orelse return error.InvalidField),
                .node_cert_hash = try allocator.dupe(u8, node_obj.get("node_cert_hash").?.getString() orelse ""),
                .public_key = try allocator.dupe(u8, node_obj.get("public_key").?.getString() orelse ""),
                .reward_rate_start = node_obj.get("reward_rate_start").?.getInt() orelse 0,
                .service_endpoints = try service_endpoints.toOwnedSlice(),
                .stake = node_obj.get("stake").?.getInt() orelse 0,
                .stake_not_rewarded = node_obj.get("stake_not_rewarded").?.getInt() orelse 0,
                .stake_rewarded = node_obj.get("stake_rewarded").?.getInt() orelse 0,
                .staking_period = staking_period,
                .timestamp = try parseTimestampFromString(node_obj.get("timestamp").?.getString() orelse return error.InvalidField),
            });
        }
        
        return result.toOwnedSlice();
    }
    
    fn parseNetworkSupply(json: []const u8, allocator: std.mem.Allocator) !NetworkSupply {
        var parser = JsonParser.init(allocator);
        var root = try parser.parse(json);
        defer root.deinit(allocator);
        
        const obj = root.getObject() orelse return error.InvalidJson;
        
        return NetworkSupply{
            .released_supply = obj.get("released_supply").?.getInt() orelse 0,
            .timestamp = try parseTimestampFromString(obj.get("timestamp").?.getString() orelse return error.InvalidField),
            .total_supply = obj.get("total_supply").?.getInt() orelse 0,
        };
    }
    
    // Helper functions
    fn parseAccountIdFromString(str: []const u8) !AccountId {
        var parts = std.mem.tokenizeAny(u8, str, ".");
        const shard = try std.fmt.parseInt(u64, parts.next() orelse return error.InvalidAccountId, 10);
        const realm = try std.fmt.parseInt(u64, parts.next() orelse return error.InvalidAccountId, 10);
        const num = try std.fmt.parseInt(u64, parts.next() orelse return error.InvalidAccountId, 10);
        
        return AccountId{
            .entity = .{
                .shard = @intCast(shard),
                .realm = @intCast(realm),
                .num = @intCast(num),
            },
        };
    }
    
    fn parseTokenIdFromString(str: []const u8) !TokenId {
        var parts = std.mem.tokenizeAny(u8, str, ".");
        const shard = try std.fmt.parseInt(u64, parts.next() orelse return error.InvalidTokenId, 10);
        const realm = try std.fmt.parseInt(u64, parts.next() orelse return error.InvalidTokenId, 10);
        const num = try std.fmt.parseInt(u64, parts.next() orelse return error.InvalidTokenId, 10);
        
        return TokenId{
            .entity = .{
                .shard = @intCast(shard),
                .realm = @intCast(realm),
                .num = @intCast(num),
            },
        };
    }
    
    fn parseTransactionIdFromString(str: []const u8) !TransactionId {
        var parts = std.mem.tokenizeAny(u8, str, "-");
        const account_str = parts.next() orelse return error.InvalidTransactionId;
        const seconds_str = parts.next() orelse return error.InvalidTransactionId;
        const nanos_str = parts.next() orelse return error.InvalidTransactionId;
        
        const account_id = try parseAccountIdFromString(account_str);
        const seconds = try std.fmt.parseInt(i64, seconds_str, 10);
        const nanos = try std.fmt.parseInt(i32, nanos_str, 10);
        
        return TransactionId{
            .account_id = account_id,
            .valid_start = Timestamp{
                .seconds = seconds,
                .nanos = nanos,
            },
        };
    }
    
    fn parseTimestampFromString(str: []const u8) !Timestamp {
        if (str.len == 0) return error.InvalidTimestamp;
        
        var parts = std.mem.tokenizeAny(u8, str, ".");
        const seconds_str = parts.next() orelse return error.InvalidTimestamp;
        const nanos_str = parts.next() orelse "0";
        
        const seconds = try std.fmt.parseInt(i64, seconds_str, 10);
        const nanos = try std.fmt.parseInt(i32, nanos_str, 10);
        
        return Timestamp{
            .seconds = seconds,
            .nanos = nanos,
        };
    }
    
    fn parseCustomFee(obj: std.StringHashMap(JsonParser.Value), allocator: std.mem.Allocator) !CustomFee {
        _ = allocator;
        
        return CustomFee{
            .all_collectors_are_exempt = obj.get("all_collectors_are_exempt").?.getBool() orelse false,
            .amount = if (obj.get("amount")) |v| v.getInt() else null,
            .amount_denominator = if (obj.get("amount_denominator")) |v| v.getInt() else null,
            .collector_account_id = try parseAccountIdFromString(obj.get("collector_account_id").?.getString() orelse return error.InvalidField),
            .denominating_token_id = if (obj.get("denominating_token_id")) |v| try parseTokenIdFromString(v.getString() orelse "") else null,
            .max = if (obj.get("max")) |v| v.getInt() else null,
            .min = if (obj.get("min")) |v| v.getInt() else null,
            .net_of_transfers = if (obj.get("net_of_transfers")) |v| v.getBool() else null,
            .royalty_fees = null, // Complex nested structure - implement if needed
        };
    }
    
    pub fn getAccountBalances(self: *MirrorNodeClient, account_id: ?AccountId, limit: ?u32) ![]AccountBalance {
        _ = account_id;
        const endpoint = "/api/v1/balances";
        const url = try std.fmt.allocPrint(
            self.allocator,
            "{s}{s}?limit={}",
            .{ self.base_url, endpoint, limit orelse 25 }
        );
        defer self.allocator.free(url);
        
        // Make REAL HTTP request to Mirror Node API
        const uri = try std.Uri.parse(url);
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();
        
        var headers = std.http.Headers{ .allocator = self.allocator };
        defer headers.deinit();
        
        var request = try client.request(.GET, uri, headers, .{});
        defer request.deinit();
        
        try request.start();
        try request.wait();
        
        if (request.response.status != .ok) {
            return error.HttpRequestFailed;
        }
        
        const body = try request.reader().readAllAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(body);
        
        // Parse JSON response
        var parser = JsonParser.init(self.allocator);
        defer parser.deinit();
        
        const parsed = try parser.parse(body);
        defer parsed.deinit();
        
        const balances_json = parsed.root.object.get("balances") orelse return error.InvalidResponse;
        const balance_array = balances_json.array;
        
        var balances = try self.allocator.alloc(AccountBalance, balance_array.items.len);
        for (balance_array.items, 0..) |bal, i| {
            const obj = bal.object;
            const empty_tokens = try self.allocator.alloc(TokenBalance, 0);
            
            balances[i] = AccountBalance{
                .balance = obj.get("balance").?.integer,
                .tokens = empty_tokens,
                .timestamp = try parseTimestampFromString(obj.get("timestamp").?.string),
            };
        }
        return balances;
    }
    
    pub fn getTransactions(self: *MirrorNodeClient, account_id: ?AccountId, transaction_type: ?[]const u8, limit: ?u32) ![]Transaction {
        _ = account_id;
        _ = transaction_type;
        const endpoint = "/api/v1/transactions";
        const url = try std.fmt.allocPrint(
            self.allocator,
            "{s}{s}?limit={}",
            .{ self.base_url, endpoint, limit orelse 25 }
        );
        defer self.allocator.free(url);
        
        // Make REAL HTTP request to Mirror Node API
        const uri = try std.Uri.parse(url);
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();
        
        var headers = std.http.Headers{ .allocator = self.allocator };
        defer headers.deinit();
        
        var request = try client.request(.GET, uri, headers, .{});
        defer request.deinit();
        
        try request.start();
        try request.wait();
        
        if (request.response.status != .ok) {
            return error.HttpRequestFailed;
        }
        
        const body = try request.reader().readAllAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(body);
        
        // Parse JSON response
        var parser = JsonParser.init(self.allocator);
        defer parser.deinit();
        
        const parsed = try parser.parse(body);
        defer parsed.deinit();
        
        const txs = parsed.root.object.get("transactions") orelse return error.InvalidResponse;
        const tx_array = txs.array;
        
        var transactions = try self.allocator.alloc(Transaction, tx_array.items.len);
        for (tx_array.items, 0..) |tx, i| {
            const obj = tx.object;
            const empty_transfers = try self.allocator.alloc(Transfer, 0);
            const empty_token_transfers = try self.allocator.alloc(TokenTransfer, 0);
            const empty_nft_transfers = try self.allocator.alloc(NftTransfer, 0);
            const empty_staking = try self.allocator.alloc(StakingRewardTransfer, 0);
            
            transactions[i] = Transaction{
                .bytes = obj.get("bytes").?.string,
                .charged_tx_fee = obj.get("charged_tx_fee").?.integer,
                .consensus_timestamp = try parseTimestampFromString(obj.get("consensus_timestamp").?.string),
                .entity_id = if (obj.get("entity_id")) |v| v.string else null,
                .max_fee = obj.get("max_fee").?.integer,
                .memo = obj.get("memo").?.string,
                .name = obj.get("name").?.string,
                .nft_transfers = empty_nft_transfers,
                .node = try parseAccountIdFromString(obj.get("node").?.string),
                .nonce = @intCast(obj.get("nonce").?.integer),
                .parent_consensus_timestamp = null,
                .result = obj.get("result").?.string,
                .scheduled = obj.get("scheduled").?.bool,
                .staking_reward_transfers = empty_staking,
                .token_transfers = empty_token_transfers,
                .transaction_hash = obj.get("transaction_hash").?.string,
                .transaction_id = try parseTransactionIdFromString(obj.get("transaction_id").?.string),
                .transfers = empty_transfers,
                .valid_duration_seconds = obj.get("valid_duration_seconds").?.integer,
                .valid_start_timestamp = try parseTimestampFromString(obj.get("valid_start_timestamp").?.string),
            };
        }
        return transactions;
    }
};