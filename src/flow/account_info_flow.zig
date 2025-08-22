const std = @import("std");
const Client = @import("../network/client.zig").Client;
const AccountId = @import("../core/id.zig").AccountId;
const AccountInfoQuery = @import("../account/account_info_query.zig").AccountInfoQuery;
const AccountBalanceQuery = @import("../account/account_balance_query.zig").AccountBalanceQuery;
const AccountRecordsQuery = @import("../account/account_records_query.zig").AccountRecordsQuery;
const AccountInfo = @import("../account/account_info_query.zig").AccountInfo;
const AccountBalance = @import("../account/account_balance_query.zig").AccountBalance;
const TransactionRecord = @import("../query/transaction_record_query.zig").TransactionRecord;
const MirrorNodeClient = @import("../mirror/mirror_node_client.zig").MirrorNodeClient;

// AccountInfoFlow provides a comprehensive view of account information
// combining data from both consensus nodes and mirror nodes
pub const AccountInfoFlow = struct {
    allocator: std.mem.Allocator,
    account_id: AccountId,
    include_balance: bool = true,
    include_records: bool = false,
    include_mirror_data: bool = true,
    records_limit: u32 = 10,
    
    pub fn init(allocator: std.mem.Allocator, account_id: AccountId) AccountInfoFlow {
        return AccountInfoFlow{
            .allocator = allocator,
            .account_id = account_id,
        };
    }
    
    pub fn deinit(self: *AccountInfoFlow) void {
        _ = self;
        // No cleanup needed for basic fields
    }
    
    // Include account balance in the flow
    pub fn withBalance(self: *AccountInfoFlow, include: bool) *AccountInfoFlow {
        self.include_balance = include;
        return self;
    }
    
    // Include recent transaction records in the flow
    pub fn withRecords(self: *AccountInfoFlow, include: bool, limit: u32) *AccountInfoFlow {
        self.include_records = include;
        self.records_limit = limit;
        return self;
    }
    
    // Include mirror node data in the flow
    pub fn withMirrorData(self: *AccountInfoFlow, include: bool) *AccountInfoFlow {
        self.include_mirror_data = include;
        return self;
    }
    
    // Execute the comprehensive account information flow
    pub fn execute(self: *AccountInfoFlow, client: *Client, mirror_client: ?*MirrorNodeClient) !CompleteAccountInfo {
        var complete_info = CompleteAccountInfo{
            .account_id = self.account_id,
            .info = null,
            .balance = null,
            .records = null,
            .mirror_info = null,
            .mirror_balance = null,
            .mirror_transactions = null,
        };
        
        // Get account info from consensus node
        var info_query = AccountInfoQuery.init(self.allocator);
        defer info_query.deinit();
        _ = info_query.setAccountId(self.account_id);
        
        complete_info.info = info_query.execute(client) catch |err| {
            if (err == error.AccountNotFound) {
                return error.AccountNotFound;
            }
            return err;
        };
        
        // Get account balance if requested
        if (self.include_balance) {
            var balance_query = AccountBalanceQuery.init(self.allocator);
            defer balance_query.deinit();
            _ = balance_query.setAccountId(self.account_id);
            
            complete_info.balance = balance_query.execute(client) catch |err| {
                // Continue even if balance query fails
                std.log.warn("Failed to get account balance: {}", .{err});
                null;
            };
        }
        
        // Get recent transaction records if requested
        if (self.include_records) {
            var records_query = AccountRecordsQuery.init(self.allocator);
            defer records_query.deinit();
            _ = records_query.setAccountId(self.account_id);
            _ = records_query.setMaxRecords(self.records_limit);
            
            complete_info.records = records_query.execute(client) catch |err| {
                // Continue even if records query fails
                std.log.warn("Failed to get account records: {}", .{err});
                null;
            };
        }
        
        // Get mirror node data if requested and mirror client is available
        if (self.include_mirror_data and mirror_client != null) {
            const mirror = mirror_client.?;
            
            // Get mirror node account info
            complete_info.mirror_info = mirror.getAccountInfo(self.account_id) catch |err| {
                std.log.warn("Failed to get mirror account info: {}", .{err});
                null;
            };
            
            // Get mirror node balance
            complete_info.mirror_balance = mirror.getAccountBalance(self.account_id) catch |err| {
                std.log.warn("Failed to get mirror account balance: {}", .{err});
                null;
            };
            
            // Get recent transactions from mirror node
            complete_info.mirror_transactions = mirror.getAccountTransactions(self.account_id, self.records_limit) catch |err| {
                std.log.warn("Failed to get mirror transactions: {}", .{err});
                null;
            };
        }
        
        return complete_info;
    }
    
    // Execute with automatic retry logic
    pub fn executeWithRetry(
        self: *AccountInfoFlow,
        client: *Client,
        mirror_client: ?*MirrorNodeClient,
        max_retries: u32,
        base_delay_ms: u64,
    ) !CompleteAccountInfo {
        var retries: u32 = 0;
        var delay_ms = base_delay_ms;
        
        while (retries <= max_retries) {
            const result = self.execute(client, mirror_client);
            
            if (result) |info| {
                return info;
            } else |err| {
                switch (err) {
                    error.AccountNotFound => return err, // Don't retry for permanent errors
                    error.NetworkError, error.Timeout, error.TemporaryFailure => {
                        if (retries < max_retries) {
                            std.log.info("Account info flow failed, retrying in {} ms (attempt {}/{})", .{ delay_ms, retries + 1, max_retries + 1 });
                            std.time.sleep(delay_ms * std.time.ns_per_ms);
                            retries += 1;
                            delay_ms *= 2; // Exponential backoff
                            continue;
                        }
                    },
                    else => return err,
                }
                return err;
            }
        }
        
        return error.MaxRetriesExceeded;
    }
    
    // Validate account exists and is accessible
    pub fn validateAccount(self: *AccountInfoFlow, client: *Client) !bool {
        var info_query = AccountInfoQuery.init(self.allocator);
        defer info_query.deinit();
        _ = info_query.setAccountId(self.account_id);
        
        _ = info_query.execute(client) catch |err| {
            switch (err) {
                error.AccountNotFound => return false,
                else => return err,
            }
        };
        
        return true;
    }
    
    // Get a summary of account information suitable for display
    pub fn getSummary(self: *AccountInfoFlow, client: *Client, mirror_client: ?*MirrorNodeClient) !AccountSummary {
        const complete_info = try self.execute(client, mirror_client);
        
        var summary = AccountSummary{
            .account_id = self.account_id,
            .exists = complete_info.info != null,
            .balance_hbars = 0,
            .auto_renew_period = null,
            .expiry_time = null,
            .is_deleted = false,
            .key_type = .unknown,
            .memo = "",
            .token_count = 0,
            .recent_transaction_count = 0,
        };
        
        // Extract summary from consensus info
        if (complete_info.info) |info| {
            summary.auto_renew_period = info.auto_renew_period;
            summary.expiry_time = info.expiry_time;
            summary.is_deleted = info.deleted;
            summary.memo = info.memo;
            
            // Determine key type
            if (info.key) |key| {
                summary.key_type = switch (key) {
                    .ed25519 => .ed25519,
                    .ecdsa_secp256k1 => .ecdsa_secp256k1,
                    .key_list => .key_list,
                    .threshold_key => .threshold_key,
                    .contract_id => .contract_id,
                    .delegatable_contract_id => .delegatable_contract_id,
                };
            }
        }
        
        // Extract balance information
        if (complete_info.balance) |balance| {
            summary.balance_hbars = @divTrunc(balance.hbars, 100_000_000); // Convert tinybars to hbars
            summary.token_count = @intCast(balance.tokens.len);
        } else if (complete_info.mirror_balance) |mirror_balance| {
            summary.balance_hbars = @divTrunc(mirror_balance.balance, 100_000_000);
            summary.token_count = @intCast(mirror_balance.tokens.len);
        }
        
        // Count recent transactions
        if (complete_info.records) |records| {
            summary.recent_transaction_count = @intCast(records.len);
        } else if (complete_info.mirror_transactions) |transactions| {
            summary.recent_transaction_count = @intCast(transactions.len);
        }
        
        return summary;
    }
};

// Complete account information from both consensus and mirror nodes
pub const CompleteAccountInfo = struct {
    account_id: AccountId,
    info: ?AccountInfo,
    balance: ?AccountBalance,
    records: ?[]TransactionRecord,
    mirror_info: ?MirrorNodeClient.AccountInfo,
    mirror_balance: ?MirrorNodeClient.AccountBalance,
    mirror_transactions: ?[]MirrorNodeClient.Transaction,
    
    pub fn deinit(self: *CompleteAccountInfo, allocator: std.mem.Allocator) void {
        if (self.info) |*info| info.deinit(allocator);
        if (self.balance) |*balance| balance.deinit(allocator);
        if (self.records) |records| {
            for (records) |*record| record.deinit(allocator);
            allocator.free(records);
        }
        if (self.mirror_balance) |*balance| {
            allocator.free(balance.tokens);
        }
        if (self.mirror_transactions) |transactions| {
            for (transactions) |*tx| {
                allocator.free(tx.bytes);
                allocator.free(tx.memo);
                allocator.free(tx.name);
                allocator.free(tx.result);
                allocator.free(tx.transaction_hash);
                allocator.free(tx.nft_transfers);
                allocator.free(tx.token_transfers);
                allocator.free(tx.transfers);
                allocator.free(tx.staking_reward_transfers);
            }
            allocator.free(transactions);
        }
    }
};

// Account summary for display purposes
pub const AccountSummary = struct {
    account_id: AccountId,
    exists: bool,
    balance_hbars: i64,
    auto_renew_period: ?i64,
    expiry_time: ?@import("../core/timestamp.zig").Timestamp,
    is_deleted: bool,
    key_type: KeyType,
    memo: []const u8,
    token_count: u32,
    recent_transaction_count: u32,
    
    pub const KeyType = enum {
        unknown,
        ed25519,
        ecdsa_secp256k1,
        key_list,
        threshold_key,
        contract_id,
        delegatable_contract_id,
    };
    
    // Convert summary to human-readable string
    pub fn toString(self: AccountSummary, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(
            allocator,
            "Account: {d}.{d}.{d}\n" ++
            "Exists: {}\n" ++
            "Balance: {} ℏ\n" ++
            "Tokens: {}\n" ++
            "Key Type: {}\n" ++
            "Memo: {s}\n" ++
            "Deleted: {}\n" ++
            "Recent Transactions: {}",
            .{
                self.account_id.entity.shard,
                self.account_id.entity.realm,
                self.account_id.entity.num,
                self.exists,
                self.balance_hbars,
                self.token_count,
                self.key_type,
                self.memo,
                self.is_deleted,
                self.recent_transaction_count,
            }
        );
    }
};