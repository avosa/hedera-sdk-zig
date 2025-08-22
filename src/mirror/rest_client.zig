const std = @import("std");
const AccountId = @import("../core/id.zig").AccountId;
const TokenId = @import("../core/id.zig").TokenId;
const ContractId = @import("../core/id.zig").ContractId;
const TopicId = @import("../core/id.zig").TopicId;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;
const Timestamp = @import("../core/timestamp.zig").Timestamp;
const Hbar = @import("../core/hbar.zig").Hbar;

// MirrorNodeRestClient provides access to Hedera Mirror Node REST API
pub const MirrorNodeRestClient = struct {
    base_url: []const u8,
    allocator: std.mem.Allocator,
    http_client: std.http.Client,
    
    pub fn init(allocator: std.mem.Allocator, base_url: []const u8) !MirrorNodeRestClient {
        return MirrorNodeRestClient{
            .base_url = try allocator.dupe(u8, base_url),
            .allocator = allocator,
            .http_client = std.http.Client{ .allocator = allocator },
        };
    }
    
    pub fn deinit(self: *MirrorNodeRestClient) void {
        self.allocator.free(self.base_url);
        self.http_client.deinit();
    }
    
    // Get account information from mirror node
    pub fn getAccount(self: *MirrorNodeRestClient, account_id: AccountId) !AccountInfo {
        const url = try std.fmt.allocPrint(self.allocator, "{s}/api/v1/accounts/{d}.{d}.{d}", .{ self.base_url, account_id.shard, account_id.realm, account_id.account });
        defer self.allocator.free(url);
        
        const response = try self.makeRequest(url);
        defer self.allocator.free(response);
        
        return try self.parseAccountInfo(response);
    }
    
    // Get account balances from mirror node
    pub fn getAccountBalances(self: *MirrorNodeRestClient, account_id: ?AccountId, limit: ?u32) ![]AccountBalance {
        var url_buffer = std.ArrayList(u8).init(self.allocator);
        defer url_buffer.deinit();
        
        try url_buffer.appendSlice(self.base_url);
        try url_buffer.appendSlice("/api/v1/balances");
        
        var first_param = true;
        if (account_id) |acc| {
            try url_buffer.appendSlice(if (first_param) "?" else "&");
            try std.fmt.format(url_buffer.writer(), "account.id={d}.{d}.{d}", .{ acc.shard, acc.realm, acc.account });
            first_param = false;
        }
        
        if (limit) |l| {
            try url_buffer.appendSlice(if (first_param) "?" else "&");
            try std.fmt.format(url_buffer.writer(), "limit={d}", .{l});
        }
        
        const response = try self.makeRequest(url_buffer.items);
        defer self.allocator.free(response);
        
        return try self.parseAccountBalances(response);
    }
    
    // Get transactions from mirror node
    pub fn getTransactions(self: *MirrorNodeRestClient, account_id: ?AccountId, transaction_type: ?[]const u8, limit: ?u32) ![]TransactionRecord {
        var url_buffer = std.ArrayList(u8).init(self.allocator);
        defer url_buffer.deinit();
        
        try url_buffer.appendSlice(self.base_url);
        try url_buffer.appendSlice("/api/v1/transactions");
        
        var first_param = true;
        if (account_id) |acc| {
            try url_buffer.appendSlice(if (first_param) "?" else "&");
            try std.fmt.format(url_buffer.writer(), "account.id={d}.{d}.{d}", .{ acc.shard, acc.realm, acc.account });
            first_param = false;
        }
        
        if (transaction_type) |tx_type| {
            try url_buffer.appendSlice(if (first_param) "?" else "&");
            try std.fmt.format(url_buffer.writer(), "transactiontype={s}", .{tx_type});
            first_param = false;
        }
        
        if (limit) |l| {
            try url_buffer.appendSlice(if (first_param) "?" else "&");
            try std.fmt.format(url_buffer.writer(), "limit={d}", .{l});
        }
        
        const response = try self.makeRequest(url_buffer.items);
        defer self.allocator.free(response);
        
        return try self.parseTransactions(response);
    }
    
    // Get specific transaction by ID
    pub fn getTransaction(self: *MirrorNodeRestClient, transaction_id: TransactionId) !TransactionRecord {
        const tx_id_str = try transaction_id.toString(self.allocator);
        defer self.allocator.free(tx_id_str);
        
        const url = try std.fmt.allocPrint(self.allocator, "{s}/api/v1/transactions/{s}", .{ self.base_url, tx_id_str });
        defer self.allocator.free(url);
        
        const response = try self.makeRequest(url);
        defer self.allocator.free(response);
        
        return try self.parseTransaction(response);
    }
    
    // Get token information
    pub fn getToken(self: *MirrorNodeRestClient, token_id: TokenId) !TokenInfo {
        const url = try std.fmt.allocPrint(self.allocator, "{s}/api/v1/tokens/{d}.{d}.{d}", .{ self.base_url, token_id.shard, token_id.realm, token_id.num });
        defer self.allocator.free(url);
        
        const response = try self.makeRequest(url);
        defer self.allocator.free(response);
        
        return try self.parseTokenInfo(response);
    }
    
    // Get topic messages
    pub fn getTopicMessages(self: *MirrorNodeRestClient, topic_id: TopicId, sequence_number: ?u64, limit: ?u32) ![]TopicMessage {
        var url_buffer = std.ArrayList(u8).init(self.allocator);
        defer url_buffer.deinit();
        
        try std.fmt.format(url_buffer.writer(), "{s}/api/v1/topics/{d}.{d}.{d}/messages", .{ self.base_url, topic_id.shard, topic_id.realm, topic_id.num });
        
        var first_param = true;
        if (sequence_number) |seq| {
            try url_buffer.appendSlice("?");
            try std.fmt.format(url_buffer.writer(), "sequencenumber={d}", .{seq});
            first_param = false;
        }
        
        if (limit) |l| {
            try url_buffer.appendSlice(if (first_param) "?" else "&");
            try std.fmt.format(url_buffer.writer(), "limit={d}", .{l});
        }
        
        const response = try self.makeRequest(url_buffer.items);
        defer self.allocator.free(response);
        
        return try self.parseTopicMessages(response);
    }
    
    // Get contract information
    pub fn getContract(self: *MirrorNodeRestClient, contract_id: ContractId) !ContractInfo {
        const url = try std.fmt.allocPrint(self.allocator, "{s}/api/v1/contracts/{d}.{d}.{d}", .{ self.base_url, contract_id.shard, contract_id.realm, contract_id.num });
        defer self.allocator.free(url);
        
        const response = try self.makeRequest(url);
        defer self.allocator.free(response);
        
        return try self.parseContractInfo(response);
    }
    
    // Get contract results
    pub fn getContractResults(self: *MirrorNodeRestClient, contract_id: ?ContractId, limit: ?u32) ![]ContractResult {
        var url_buffer = std.ArrayList(u8).init(self.allocator);
        defer url_buffer.deinit();
        
        try url_buffer.appendSlice(self.base_url);
        try url_buffer.appendSlice("/api/v1/contracts/results");
        
        var first_param = true;
        if (contract_id) |contract| {
            try url_buffer.appendSlice("?");
            try std.fmt.format(url_buffer.writer(), "contract.id={d}.{d}.{d}", .{ contract.shard, contract.realm, contract.num });
            first_param = false;
        }
        
        if (limit) |l| {
            try url_buffer.appendSlice(if (first_param) "?" else "&");
            try std.fmt.format(url_buffer.writer(), "limit={d}", .{l});
        }
        
        const response = try self.makeRequest(url_buffer.items);
        defer self.allocator.free(response);
        
        return try self.parseContractResults(response);
    }
    
    // Make HTTP request to mirror node
    fn makeRequest(self: *MirrorNodeRestClient, url: []const u8) ![]u8 {
        const uri = std.Uri.parse(url) catch return error.InvalidUrl;
        
        var headers = std.http.Headers{ .allocator = self.allocator };
        defer headers.deinit();
        
        try headers.append("accept", "application/json");
        try headers.append("user-agent", "hedera-sdk-zig/1.0.0");
        
        var request = try self.http_client.open(.GET, uri, headers, .{});
        defer request.deinit();
        
        try request.send();
        try request.finish();
        try request.wait();
        
        if (request.response.status != .ok) {
            return error.HttpRequestFailed;
        }
        
        const body = try request.reader().readAllAlloc(self.allocator, 10 * 1024 * 1024); // 10MB limit
        return body;
    }
    
    // JSON parsing functions
    fn parseAccountInfo(self: *MirrorNodeRestClient, json_data: []const u8) !AccountInfo {
        var parser = std.json.Parser.init(self.allocator, .alloc_always);
        defer parser.deinit();
        
        var tree = try parser.parse(json_data);
        defer tree.deinit();
        
        const root = tree.root.object;
        
        var account_info = AccountInfo{
            .account_id = AccountId.init(0, 0, 0),
            .balance = try Hbar.fromTinybars(0),
            .auto_renew_period = 0,
            .deleted = false,
            .memo = "",
            .allocator = self.allocator,
        };
        
        if (root.get("account")) |account_field| {
            const account_str = account_field.string;
            const parts = std.mem.split(u8, account_str, ".");
            const shard = try std.fmt.parseInt(u64, parts.next().?, 10);
            const realm = try std.fmt.parseInt(u64, parts.next().?, 10);
            const num = try std.fmt.parseInt(u64, parts.next().?, 10);
            account_info.account_id = AccountId.init(shard, realm, num);
        }
        
        if (root.get("balance")) |balance_field| {
            const balance_obj = balance_field.object;
            if (balance_obj.get("balance")) |bal| {
                account_info.balance = try Hbar.fromTinybars(bal.integer);
            }
        }
        
        if (root.get("auto_renew_period")) |period_field| {
            account_info.auto_renew_period = period_field.integer;
        }
        
        if (root.get("deleted")) |deleted_field| {
            account_info.deleted = deleted_field.bool;
        }
        
        if (root.get("memo")) |memo_field| {
            account_info.memo = try self.allocator.dupe(u8, memo_field.string);
        }
        
        return account_info;
    }
    
    fn parseAccountBalances(self: *MirrorNodeRestClient, json_data: []const u8) ![]AccountBalance {
        var parser = std.json.Parser.init(self.allocator, .alloc_always);
        defer parser.deinit();
        
        var tree = try parser.parse(json_data);
        defer tree.deinit();
        
        const root = tree.root.object;
        const balances_array = root.get("balances").?.array;
        
        var balances = std.ArrayList(AccountBalance).init(self.allocator);
        
        for (balances_array.items) |balance_item| {
            const balance_obj = balance_item.object;
            
            var account_balance = AccountBalance{
                .account_id = AccountId.init(0, 0, 0),
                .balance = try Hbar.fromTinybars(0),
            };
            
            if (balance_obj.get("account")) |account_field| {
                const account_str = account_field.string;
                const parts = std.mem.split(u8, account_str, ".");
                const shard = try std.fmt.parseInt(u64, parts.next().?, 10);
                const realm = try std.fmt.parseInt(u64, parts.next().?, 10);
                const num = try std.fmt.parseInt(u64, parts.next().?, 10);
                account_balance.account_id = AccountId.init(shard, realm, num);
            }
            
            if (balance_obj.get("balance")) |balance_field| {
                account_balance.balance = try Hbar.fromTinybars(balance_field.integer);
            }
            
            try balances.append(account_balance);
        }
        
        return balances.toOwnedSlice();
    }
    
    fn parseTransactions(self: *MirrorNodeRestClient, json_data: []const u8) ![]TransactionRecord {
        var parser = std.json.Parser.init(self.allocator, .alloc_always);
        defer parser.deinit();
        
        var tree = try parser.parse(json_data);
        defer tree.deinit();
        
        const root = tree.root.object;
        const transactions_array = root.get("transactions").?.array;
        
        var transactions = std.ArrayList(TransactionRecord).init(self.allocator);
        
        for (transactions_array.items) |tx_item| {
            const tx_record = try self.parseTransactionItem(tx_item);
            try transactions.append(tx_record);
        }
        
        return transactions.toOwnedSlice();
    }
    
    fn parseTransaction(self: *MirrorNodeRestClient, json_data: []const u8) !TransactionRecord {
        var parser = std.json.Parser.init(self.allocator, .alloc_always);
        defer parser.deinit();
        
        var tree = try parser.parse(json_data);
        defer tree.deinit();
        
        const root = tree.root.object;
        const transactions_array = root.get("transactions").?.array;
        
        if (transactions_array.items.len == 0) {
            return error.TransactionNotFound;
        }
        
        return try self.parseTransactionItem(transactions_array.items[0]);
    }
    
    fn parseTransactionItem(self: *MirrorNodeRestClient, tx_item: std.json.Value) !TransactionRecord {
        const tx_obj = tx_item.object;
        
        var tx_record = TransactionRecord{
            .transaction_id = TransactionId.init(AccountId.init(0, 0, 0)),
            .consensus_timestamp = Timestamp{ .seconds = 0, .nanos = 0 },
            .transaction_hash = "",
            .memo = "",
            .transaction_fee = try Hbar.fromTinybars(0),
            .transfers = std.ArrayList(@import("../transfer/transfer_transaction.zig").Transfer).init(self.allocator),
            .token_transfers = std.ArrayList(@import("../transfer/transfer_transaction.zig").TokenTransfer).init(self.allocator),
            .nft_transfers = std.ArrayList(@import("../transfer/transfer_transaction.zig").NftTransfer).init(self.allocator),
            .receipt = undefined,
            .contract_function_result = null,
            .contract_create_result = null,
            .automatic_token_associations = std.ArrayList(@import("../query/transaction_record_query.zig").TransactionRecord.TokenAssociation).init(self.allocator),
            .alias_key = null,
            .children = std.ArrayList(@import("../query/transaction_record_query.zig").TransactionRecord).init(self.allocator),
            .duplicates = std.ArrayList(@import("../query/transaction_record_query.zig").TransactionRecord).init(self.allocator),
            .parent_consensus_timestamp = null,
            .ethereum_hash = null,
            .prng_bytes = null,
            .prng_number = null,
            .evm_address = null,
            .allocator = self.allocator,
        };
        
        if (tx_obj.get("transaction_id")) |tx_id_field| {
            tx_record.transaction_id = try TransactionId.fromString(tx_id_field.string, self.allocator);
        }
        
        if (tx_obj.get("consensus_timestamp")) |timestamp_field| {
            const timestamp_str = timestamp_field.string;
            const timestamp_float = try std.fmt.parseFloat(f64, timestamp_str);
            tx_record.consensus_timestamp.seconds = @intFromFloat(timestamp_float);
            tx_record.consensus_timestamp.nanos = @intFromFloat((timestamp_float - @floor(timestamp_float)) * 1_000_000_000);
        }
        
        if (tx_obj.get("transaction_hash")) |hash_field| {
            tx_record.transaction_hash = try self.allocator.dupe(u8, hash_field.string);
        }
        
        if (tx_obj.get("memo_base64")) |memo_field| {
            const decoded = try std.base64.standard.Decoder.decode(self.allocator, memo_field.string);
            tx_record.memo = decoded;
        }
        
        if (tx_obj.get("charged_tx_fee")) |fee_field| {
            tx_record.transaction_fee = try Hbar.fromTinybars(fee_field.integer);
        }
        
        return tx_record;
    }
    
    fn parseTokenInfo(self: *MirrorNodeRestClient, json_data: []const u8) !TokenInfo {
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, json_data, .{});
        defer parsed.deinit();
        
        const root = parsed.value.object;
        
        const token_id = try parseEntityId(root.get("token_id").?.string, TokenId);
        const name = try self.allocator.dupe(u8, root.get("name").?.string);
        const symbol = try self.allocator.dupe(u8, root.get("symbol").?.string);
        const decimals = @intCast(u32, root.get("decimals").?.integer);
        const total_supply = @intCast(u64, std.json.parseInt(u64, root.get("total_supply").?.string, 10) catch 0);
        const treasury_account_id = try parseEntityId(root.get("treasury_account_id").?.string, AccountId);
        
        const token_type_str = root.get("type").?.string;
        const token_type = if (std.mem.eql(u8, token_type_str, "FUNGIBLE_COMMON"))
            TokenType.FungibleCommon
        else
            TokenType.NonFungibleUnique;
        
        const supply_type_str = root.get("supply_type").?.string;
        const supply_type = if (std.mem.eql(u8, supply_type_str, "INFINITE"))
            TokenSupplyType.Infinite
        else
            TokenSupplyType.Finite;
        
        const max_supply = if (root.get("max_supply")) |max| 
            @intCast(u64, std.json.parseInt(u64, max.string, 10) catch 0)
        else
            0;
        
        const freeze_default = root.get("freeze_default").?.bool;
        const kyc_default = root.get("kyc_key") != null;
        const pause_status = root.get("pause_key") != null;
        
        const expiry = root.get("expiry_timestamp").?.string;
        const expiry_seconds = std.fmt.parseInt(i64, expiry[0..10], 10) catch 0;
        const expiry_timestamp = Timestamp.fromUnixSeconds(expiry_seconds);
        
        const auto_renew_period = Duration.fromSeconds(
            std.json.parseInt(i64, root.get("auto_renew_period").?.string, 10) catch 7776000
        );
        
        const memo = try self.allocator.dupe(u8, root.get("memo").?.string);
        const deleted = root.get("deleted").?.bool;
        
        return TokenInfo{
            .token_id = token_id,
            .name = name,
            .symbol = symbol,
            .decimals = decimals,
            .total_supply = total_supply,
            .treasury_account_id = treasury_account_id,
            .admin_key = null,
            .kyc_key = null,
            .freeze_key = null,
            .wipe_key = null,
            .supply_key = null,
            .pause_key = null,
            .fee_schedule_key = null,
            .default_freeze_status = freeze_default,
            .default_kyc_status = kyc_default,
            .deleted = deleted,
            .auto_renew_account = null,
            .auto_renew_period = auto_renew_period,
            .expiry = expiry_timestamp,
            .memo = memo,
            .token_type = token_type,
            .supply_type = supply_type,
            .max_supply = max_supply,
            .custom_fees = std.ArrayList(CustomFee).init(self.allocator),
            .pause_status = pause_status,
            .allocator = self.allocator,
        };
    }
    
    fn parseTopicMessages(self: *MirrorNodeRestClient, json_data: []const u8) ![]TopicMessage {
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, json_data, .{});
        defer parsed.deinit();
        
        const messages_array = parsed.value.object.get("messages").?.array;
        var messages = try self.allocator.alloc(TopicMessage, messages_array.items.len);
        
        for (messages_array.items, 0..) |msg_obj, i| {
            const msg = msg_obj.object;
            const topic_id = try parseEntityId(msg.get("topic_id").?.string, TopicId);
            const sequence_number = @intCast(u64, msg.get("sequence_number").?.integer);
            
            const consensus_timestamp = msg.get("consensus_timestamp").?.string;
            const timestamp_parts = std.mem.split(u8, consensus_timestamp, ".");
            var iter = timestamp_parts;
            const seconds = std.fmt.parseInt(i64, iter.next().?, 10) catch 0;
            const nanos = std.fmt.parseInt(i32, iter.next() orelse "0", 10) catch 0;
            
            const message_bytes = msg.get("message").?.string;
            const decoded_message = try std.base64.standard.Decoder.decode(self.allocator, message_bytes);
            
            const running_hash = msg.get("running_hash").?.string;
            const decoded_hash = try std.base64.standard.Decoder.decode(self.allocator, running_hash);
            
            const running_hash_version = @intCast(u64, msg.get("running_hash_version").?.integer);
            
            messages[i] = TopicMessage{
                .topic_id = topic_id,
                .sequence_number = sequence_number,
                .consensus_timestamp = Timestamp.init(seconds, nanos),
                .message = decoded_message,
                .running_hash = decoded_hash,
                .running_hash_version = running_hash_version,
                .allocator = self.allocator,
            };
        }
        
        return messages;
    }
    
    fn parseContractInfo(self: *MirrorNodeRestClient, json_data: []const u8) !ContractInfo {
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, json_data, .{});
        defer parsed.deinit();
        
        const root = parsed.value.object;
        
        const contract_id = try parseEntityId(root.get("contract_id").?.string, ContractId);
        const account_id = try parseEntityId(root.get("contract_id").?.string, AccountId);
        
        const created = root.get("created_timestamp").?.string;
        const created_parts = std.mem.split(u8, created, ".");
        var iter = created_parts;
        const created_seconds = std.fmt.parseInt(i64, iter.next().?, 10) catch 0;
        const created_nanos = std.fmt.parseInt(i32, iter.next() orelse "0", 10) catch 0;
        
        const expiry = root.get("expiration_timestamp").?.string;
        const expiry_seconds = std.fmt.parseInt(i64, expiry[0..10], 10) catch 0;
        
        const auto_renew_period = Duration.fromSeconds(
            std.json.parseInt(i64, root.get("auto_renew_period").?.string, 10) catch 7776000
        );
        
        const storage = @intCast(u64, std.json.parseInt(u64, root.get("storage").?.string, 10) catch 0);
        const memo = try self.allocator.dupe(u8, root.get("memo").?.string);
        const balance = Hbar.fromTinybars(std.json.parseInt(i64, root.get("balance").?.object.get("balance").?.string, 10) catch 0);
        const deleted = root.get("deleted").?.bool;
        
        const max_automatic_token_associations = if (root.get("max_automatic_token_associations")) |max|
            @intCast(u32, max.integer)
        else
            0;
        
        const file_id = if (root.get("file_id")) |fid|
            try parseEntityId(fid.string, FileId)
        else
            null;
        
        return ContractInfo{
            .contract_id = contract_id,
            .account_id = account_id,
            .contract_account_id = try self.allocator.dupe(u8, root.get("evm_address").?.string),
            .admin_key = null,
            .expiration_time = Timestamp.fromUnixSeconds(expiry_seconds),
            .auto_renew_period = auto_renew_period,
            .auto_renew_account_id = null,
            .storage = storage,
            .contract_memo = memo,
            .balance = balance,
            .deleted = deleted,
            .token_relationships = std.AutoHashMap(TokenId, u64).init(self.allocator),
            .ledger_id = try self.allocator.dupe(u8, ""),
            .max_automatic_token_associations = max_automatic_token_associations,
            .staking_info = null,
            .created_timestamp = Timestamp.init(created_seconds, created_nanos),
            .bytecode_file_id = file_id,
            .allocator = self.allocator,
        };
    }
    
    fn parseContractResults(self: *MirrorNodeRestClient, json_data: []const u8) ![]ContractResult {
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, json_data, .{});
        defer parsed.deinit();
        
        const results_array = parsed.value.object.get("results").?.array;
        var results = try self.allocator.alloc(ContractResult, results_array.items.len);
        
        for (results_array.items, 0..) |result_obj, i| {
            const res = result_obj.object;
            
            const contract_id = try parseEntityId(res.get("contract_id").?.string, ContractId);
            
            const consensus = res.get("consensus_timestamp").?.string;
            const consensus_parts = std.mem.split(u8, consensus, ".");
            var iter = consensus_parts;
            const consensus_seconds = std.fmt.parseInt(i64, iter.next().?, 10) catch 0;
            const consensus_nanos = std.fmt.parseInt(i32, iter.next() orelse "0", 10) catch 0;
            
            const error_message = if (res.get("error_message")) |err|
                try self.allocator.dupe(u8, err.string)
            else
                try self.allocator.dupe(u8, "");
            
            const bloom = res.get("bloom").?.string;
            const bloom_bytes = try std.fmt.hexToBytes(self.allocator, bloom[2..]);
            
            const gas_limit = @intCast(u64, res.get("gas_limit").?.integer);
            const gas_used = @intCast(u64, res.get("gas_used").?.integer);
            
            const call_result = res.get("call_result").?.string;
            const call_result_bytes = try std.fmt.hexToBytes(self.allocator, call_result[2..]);
            
            const from_addr = res.get("from").?.string;
            const from_bytes = try std.fmt.hexToBytes(self.allocator, from_addr[2..]);
            
            const to_addr = if (res.get("to")) |to|
                try std.fmt.hexToBytes(self.allocator, to.string[2..])
            else
                try self.allocator.alloc(u8, 0);
            
            const created_ids = std.ArrayList(ContractId).init(self.allocator);
            
            results[i] = ContractResult{
                .contract_id = contract_id,
                .consensus_timestamp = Timestamp.init(consensus_seconds, consensus_nanos),
                .error_message = error_message,
                .bloom = bloom_bytes,
                .gas_limit = gas_limit,
                .gas_used = gas_used,
                .call_result = call_result_bytes,
                .from = from_bytes,
                .to = to_bytes,
                .created_contract_ids = created_ids,
                .allocator = self.allocator,
            };
        }
        
        return results;
    }
};

// Data structures for mirror node responses
pub const AccountInfo = struct {
    account_id: AccountId,
    balance: Hbar,
    auto_renew_period: i64,
    deleted: bool,
    memo: []const u8,
    
    allocator: std.mem.Allocator,
    
    pub fn deinit(self: *AccountInfo) void {
        if (self.memo.len > 0) {
            self.allocator.free(self.memo);
        }
    }
};

pub const AccountBalance = struct {
    account_id: AccountId,
    balance: Hbar,
};

pub const TransactionRecord = @import("../query/transaction_record_query.zig").TransactionRecord;

pub const TokenInfo = struct {
    token_id: TokenId,
    name: []const u8,
    symbol: []const u8,
    decimals: u32,
    total_supply: u64,
    treasury_account_id: AccountId,
    
    allocator: std.mem.Allocator,
    
    pub fn deinit(self: *TokenInfo) void {
        if (self.name.len > 0) {
            self.allocator.free(self.name);
        }
        if (self.symbol.len > 0) {
            self.allocator.free(self.symbol);
        }
    }
};

pub const TopicMessage = struct {
    topic_id: TopicId,
    sequence_number: u64,
    message: []const u8,
    consensus_timestamp: Timestamp,
    running_hash: []const u8,
    
    allocator: std.mem.Allocator,
    
    pub fn deinit(self: *TopicMessage) void {
        if (self.message.len > 0) {
            self.allocator.free(self.message);
        }
        if (self.running_hash.len > 0) {
            self.allocator.free(self.running_hash);
        }
    }
};

pub const ContractInfo = struct {
    contract_id: ContractId,
    evm_address: []const u8,
    admin_key: ?[]const u8,
    memo: []const u8,
    auto_renew_period: i64,
    
    allocator: std.mem.Allocator,
    
    pub fn deinit(self: *ContractInfo) void {
        if (self.evm_address.len > 0) {
            self.allocator.free(self.evm_address);
        }
        if (self.admin_key) |key| {
            self.allocator.free(key);
        }
        if (self.memo.len > 0) {
            self.allocator.free(self.memo);
        }
    }
};

pub const ContractResult = struct {
    contract_id: ContractId,
    transaction_id: TransactionId,
    function_result: []const u8,
    gas_used: u64,
    
    allocator: std.mem.Allocator,
    
    pub fn deinit(self: *ContractResult) void {
        self.transaction_id.deinit();
        if (self.function_result.len > 0) {
            self.allocator.free(self.function_result);
        }
    }
};