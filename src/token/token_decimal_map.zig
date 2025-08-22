const std = @import("std");
const TokenId = @import("../core/id.zig").TokenId;

// Token decimal tracking for proper token amount display
pub const TokenDecimalMap = struct {
    decimals: std.HashMap(TokenId, u32, TokenContext, std.hash_map.default_max_load_percentage),
    allocator: std.mem.Allocator,

    const TokenContext = struct {
        pub fn hash(self: @This(), token_id: TokenId) u64 {
            _ = self;
            var hasher = std.hash.Wyhash.init(0);
            hasher.update(std.mem.asBytes(&token_id.shard));
            hasher.update(std.mem.asBytes(&token_id.realm));
            hasher.update(std.mem.asBytes(&token_id.num));
            return hasher.final();
        }

        pub fn eql(self: @This(), a: TokenId, b: TokenId) bool {
            _ = self;
            return a.shard == b.shard and
                   a.realm == b.realm and
                   a.num == b.num;
        }
    };

    pub fn init(allocator: std.mem.Allocator) TokenDecimalMap {
        return TokenDecimalMap{
            .decimals = std.HashMap(TokenId, u32, TokenContext, std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TokenDecimalMap) void {
        self.decimals.deinit();
    }

    pub fn put(self: *TokenDecimalMap, token_id: TokenId, decimal_count: u32) !void {
        try self.decimals.put(token_id, decimal_count);
    }

    pub fn get(self: *const TokenDecimalMap, token_id: TokenId) ?u32 {
        return self.decimals.get(token_id);
    }

    pub fn getOrDefault(self: *const TokenDecimalMap, token_id: TokenId, default: u32) u32 {
        return self.decimals.get(token_id) orelse default;
    }

    pub fn remove(self: *TokenDecimalMap, token_id: TokenId) bool {
        return self.decimals.remove(token_id);
    }

    pub fn contains(self: *const TokenDecimalMap, token_id: TokenId) bool {
        return self.decimals.contains(token_id);
    }

    pub fn isEmpty(self: *const TokenDecimalMap) bool {
        return self.decimals.count() == 0;
    }

    pub fn size(self: *const TokenDecimalMap) u32 {
        return @intCast(self.decimals.count());
    }

    pub fn clear(self: *TokenDecimalMap) void {
        self.decimals.clearRetainingCapacity();
    }

    // Iterator for all token decimals
    pub const Iterator = struct {
        inner: std.HashMap(TokenId, u32, TokenContext, std.hash_map.default_max_load_percentage).Iterator,

        pub fn next(self: *Iterator) ?struct { token_id: TokenId, decimals: u32 } {
            if (self.inner.next()) |entry| {
                return .{ .token_id = entry.key_ptr.*, .decimals = entry.value_ptr.* };
            }
            return null;
        }
    };

    pub fn iterator(self: *const TokenDecimalMap) Iterator {
        return Iterator{ .inner = self.decimals.iterator() };
    }

    // Convert raw token amount to decimal representation
    pub fn toDecimalAmount(self: *const TokenDecimalMap, token_id: TokenId, raw_amount: u64) f64 {
        const decimal_places = self.get(token_id) orelse 0;
        if (decimal_places == 0) return @floatFromInt(raw_amount);
        
        const divisor = std.math.pow(f64, 10.0, @floatFromInt(decimal_places));
        return @as(f64, @floatFromInt(raw_amount)) / divisor;
    }

    // Convert decimal amount to raw token amount
    pub fn fromDecimalAmount(self: *const TokenDecimalMap, token_id: TokenId, decimal_amount: f64) u64 {
        const decimal_places = self.get(token_id) orelse 0;
        if (decimal_places == 0) return @intFromFloat(decimal_amount);
        
        const multiplier = std.math.pow(f64, 10.0, @floatFromInt(decimal_places));
        return @intFromFloat(decimal_amount * multiplier);
    }

    // Format token amount with proper decimal places
    pub fn formatAmount(self: *const TokenDecimalMap, token_id: TokenId, raw_amount: u64, allocator: std.mem.Allocator) ![]u8 {
        const decimal_places = self.get(token_id) orelse 0;
        if (decimal_places == 0) {
            return std.fmt.allocPrint(allocator, "{d}", .{raw_amount});
        }

        const decimal_amount = self.toDecimalAmount(token_id, raw_amount);
        return std.fmt.allocPrint(allocator, "{d:.{}f}", .{ decimal_amount, decimal_places });
    }

    // Parse formatted amount string to raw amount
    pub fn parseAmount(self: *const TokenDecimalMap, token_id: TokenId, amount_str: []const u8) !u64 {
        const decimal_places = self.get(token_id) orelse 0;
        
        if (decimal_places == 0) {
            return std.fmt.parseInt(u64, amount_str, 10);
        }

        const decimal_amount = try std.fmt.parseFloat(f64, amount_str);
        return self.fromDecimalAmount(token_id, decimal_amount);
    }

    // Clone the decimal map
    pub fn clone(self: *const TokenDecimalMap, allocator: std.mem.Allocator) !TokenDecimalMap {
        var result = TokenDecimalMap.init(allocator);
        errdefer result.deinit();

        var iter = self.iterator();
        while (iter.next()) |entry| {
            try result.put(entry.token_id, entry.decimals);
        }

        return result;
    }

    // Merge another decimal map into this one
    pub fn merge(self: *TokenDecimalMap, other: *const TokenDecimalMap) !void {
        var iter = other.iterator();
        while (iter.next()) |entry| {
            try self.put(entry.token_id, entry.decimals);
        }
    }

    // Get all tokens and their decimal places
    pub fn getAllDecimals(self: *const TokenDecimalMap, allocator: std.mem.Allocator) ![]struct { token_id: TokenId, decimals: u32 } {
        var result = std.ArrayList(struct { token_id: TokenId, decimals: u32 }).init(allocator);
        defer result.deinit();

        var iter = self.iterator();
        while (iter.next()) |entry| {
            try result.append(entry);
        }

        return result.toOwnedSlice();
    }

    // Validate decimal places (typically 0-18 for tokens)
    pub fn isValidDecimals(decimals: u32) bool {
        return decimals <= 18;
    }

    // Set decimal places with validation
    pub fn setDecimals(self: *TokenDecimalMap, token_id: TokenId, decimals: u32) *TokenDecimalMap {
        if (!isValidDecimals(decimals)) {
            return error.InvalidDecimals;
        }
        try self.put(token_id, decimals);
        return self;
    }

    // Create from token info list
    pub fn fromTokenInfos(allocator: std.mem.Allocator, token_infos: []const TokenInfo) !TokenDecimalMap {
        var map = TokenDecimalMap.init(allocator);
        errdefer map.deinit();

        for (token_infos) |info| {
            try map.put(info.token_id, info.decimals);
        }

        return map;
    }

    // Get display precision for a token (useful for UI)
    pub fn getDisplayPrecision(self: *const TokenDecimalMap, token_id: TokenId, max_precision: u32) u32 {
        const decimals = self.get(token_id) orelse 0;
        return @min(decimals, max_precision);
    }

    // Calculate minimum transferable unit for a token
    pub fn getMinimumUnit(self: *const TokenDecimalMap, token_id: TokenId) u64 {
        const decimals = self.get(token_id) orelse 0;
        if (decimals == 0) return 1;
        return std.math.pow(u64, 10, decimals);
    }
};

// Token info for building decimal maps
pub const TokenInfo = struct {
    token_id: TokenId,
    decimals: u32,
    name: []const u8,
    symbol: []const u8,
    
    pub fn init(token_id: TokenId, decimals: u32, name: []const u8, symbol: []const u8) TokenInfo {
        return TokenInfo{
            .token_id = token_id,
            .decimals = decimals,
            .name = name,
            .symbol = symbol,
        };
    }
};
