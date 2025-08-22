const std = @import("std");
const TokenId = @import("../core/id.zig").TokenId;
const AccountId = @import("../core/id.zig").AccountId;
const Hbar = @import("../core/hbar.zig").Hbar;

// Token balance tracking for accounts
pub const TokenBalanceMap = struct {
    balances: std.HashMap(TokenId, u64, TokenContext, std.hash_map.default_max_load_percentage),
    allocator: std.mem.Allocator,

    const TokenContext = struct {
        pub fn hash(self: @This(), token_id: TokenId) u64 {
            _ = self;
            var hasher = std.hash.Wyhash.init(0);
            hasher.update(std.mem.asBytes(&token_id.entity.shard));
            hasher.update(std.mem.asBytes(&token_id.entity.realm));
            hasher.update(std.mem.asBytes(&token_id.entity.num));
            return hasher.final();
        }

        pub fn eql(self: @This(), a: TokenId, b: TokenId) bool {
            _ = self;
            return a.entity.shard == b.entity.shard and
                   a.entity.realm == b.entity.realm and
                   a.entity.num == b.entity.num;
        }
    };

    pub fn init(allocator: std.mem.Allocator) TokenBalanceMap {
        return TokenBalanceMap{
            .balances = std.HashMap(TokenId, u64, TokenContext, std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TokenBalanceMap) void {
        self.balances.deinit();
    }

    pub fn put(self: *TokenBalanceMap, token_id: TokenId, balance: u64) !void {
        try self.balances.put(token_id, balance);
    }

    pub fn get(self: *const TokenBalanceMap, token_id: TokenId) ?u64 {
        return self.balances.get(token_id);
    }

    pub fn remove(self: *TokenBalanceMap, token_id: TokenId) bool {
        return self.balances.remove(token_id);
    }

    pub fn contains(self: *const TokenBalanceMap, token_id: TokenId) bool {
        return self.balances.contains(token_id);
    }

    pub fn isEmpty(self: *const TokenBalanceMap) bool {
        return self.balances.count() == 0;
    }

    pub fn size(self: *const TokenBalanceMap) u32 {
        return @intCast(self.balances.count());
    }

    pub fn clear(self: *TokenBalanceMap) void {
        self.balances.clearRetainingCapacity();
    }

    // Iterator for all token balances
    pub const Iterator = struct {
        inner: std.HashMap(TokenId, u64, TokenContext, std.hash_map.default_max_load_percentage).Iterator,

        pub fn next(self: *Iterator) ?struct { token_id: TokenId, balance: u64 } {
            if (self.inner.next()) |entry| {
                return .{ .token_id = entry.key_ptr.*, .balance = entry.value_ptr.* };
            }
            return null;
        }
    };

    pub fn iterator(self: *const TokenBalanceMap) Iterator {
        return Iterator{ .inner = self.balances.iterator() };
    }

    // Get all tokens with non-zero balances
    pub fn getNonZeroBalances(self: *const TokenBalanceMap, allocator: std.mem.Allocator) ![]struct { token_id: TokenId, balance: u64 } {
        var result = std.ArrayList(struct { token_id: TokenId, balance: u64 }).init(allocator);
        defer result.deinit();

        var iter = self.iterator();
        while (iter.next()) |entry| {
            if (entry.balance > 0) {
                try result.append(entry);
            }
        }

        return result.toOwnedSlice();
    }

    // Get total number of different tokens held
    pub fn getTokenCount(self: *const TokenBalanceMap) u32 {
        var count: u32 = 0;
        var iter = self.iterator();
        while (iter.next()) |entry| {
            if (entry.balance > 0) {
                count += 1;
            }
        }
        return count;
    }

    // Update balance by adding/subtracting amount
    pub fn updateBalance(self: *TokenBalanceMap, token_id: TokenId, delta: i64) !void {
        const current_balance = self.get(token_id) orelse 0;
        const new_balance = if (delta < 0) 
            current_balance -| @as(u64, @intCast(-delta))
        else 
            current_balance + @as(u64, @intCast(delta));
        
        try self.put(token_id, new_balance);
    }

    // Create from token transfer list
    pub fn fromTransfers(allocator: std.mem.Allocator, transfers: []const TokenTransfer) !TokenBalanceMap {
        var map = TokenBalanceMap.init(allocator);
        errdefer map.deinit();

        for (transfers) |transfer| {
            const current = map.get(transfer.token_id) orelse 0;
            const new_balance = if (transfer.amount < 0)
                current -| @as(u64, @intCast(-transfer.amount))
            else
                current + @as(u64, @intCast(transfer.amount));
            
            try map.put(transfer.token_id, new_balance);
        }

        return map;
    }

    // Merge another balance map into this one
    pub fn merge(self: *TokenBalanceMap, other: *const TokenBalanceMap) !void {
        var iter = other.iterator();
        while (iter.next()) |entry| {
            const current = self.get(entry.token_id) orelse 0;
            try self.put(entry.token_id, current + entry.balance);
        }
    }

    // Clone the balance map
    pub fn clone(self: *const TokenBalanceMap, allocator: std.mem.Allocator) !TokenBalanceMap {
        var result = TokenBalanceMap.init(allocator);
        errdefer result.deinit();

        var iter = self.iterator();
        while (iter.next()) |entry| {
            try result.put(entry.token_id, entry.balance);
        }

        return result;
    }
};

// Account balance map - tracks multiple accounts' token balances
pub const AccountBalanceMap = struct {
    balances: std.HashMap(AccountId, TokenBalanceMap, AccountContext, std.hash_map.default_max_load_percentage),
    allocator: std.mem.Allocator,

    const AccountContext = struct {
        pub fn hash(self: @This(), account_id: AccountId) u64 {
            _ = self;
            var hasher = std.hash.Wyhash.init(0);
            hasher.update(std.mem.asBytes(&account_id.entity.shard));
            hasher.update(std.mem.asBytes(&account_id.entity.realm));
            hasher.update(std.mem.asBytes(&account_id.entity.num));
            return hasher.final();
        }

        pub fn eql(self: @This(), a: AccountId, b: AccountId) bool {
            _ = self;
            return a.entity.shard == b.entity.shard and
                   a.entity.realm == b.entity.realm and
                   a.entity.num == b.entity.num;
        }
    };

    pub fn init(allocator: std.mem.Allocator) AccountBalanceMap {
        return AccountBalanceMap{
            .balances = std.HashMap(AccountId, TokenBalanceMap, AccountContext, std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *AccountBalanceMap) void {
        var iter = self.balances.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.balances.deinit();
    }

    pub fn getOrCreate(self: *AccountBalanceMap, account_id: AccountId) !*TokenBalanceMap {
        const result = try self.balances.getOrPut(account_id);
        if (!result.found_existing) {
            result.value_ptr.* = TokenBalanceMap.init(self.allocator);
        }
        return result.value_ptr;
    }

    pub fn get(self: *const AccountBalanceMap, account_id: AccountId) ?*const TokenBalanceMap {
        return self.balances.getPtr(account_id);
    }

    pub fn updateBalance(self: *AccountBalanceMap, account_id: AccountId, token_id: TokenId, delta: i64) !void {
        const balance_map = try self.getOrCreate(account_id);
        try balance_map.updateBalance(token_id, delta);
    }

    pub fn getTokenBalance(self: *const AccountBalanceMap, account_id: AccountId, token_id: TokenId) u64 {
        if (self.get(account_id)) |balance_map| {
            return balance_map.get(token_id) orelse 0;
        }
        return 0;
    }
};

// Token transfer for building balance maps
pub const TokenTransfer = struct {
    account_id: AccountId,
    token_id: TokenId,
    amount: i64,
    
    pub fn init(account_id: AccountId, token_id: TokenId, amount: i64) TokenTransfer {
        return TokenTransfer{
            .account_id = account_id,
            .token_id = token_id,
            .amount = amount,
        };
    }
};