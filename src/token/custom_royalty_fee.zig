const std = @import("std");
const AccountId = @import("../core/id.zig").AccountId;
const TokenId = @import("../core/id.zig").TokenId;
const Hbar = @import("../core/hbar.zig").Hbar;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;
const CustomFixedFee = @import("custom_fixed_fee.zig").CustomFixedFee;

// Royalty fee for NFT trades with fallback fixed fee
pub const CustomRoyaltyFee = struct {
    numerator: u64,
    denominator: u64,
    fallback_fee: ?CustomFixedFee,
    fee_collector_account_id: ?AccountId,
    all_collectors_are_exempt: bool,

    pub fn init() CustomRoyaltyFee {
        return CustomRoyaltyFee{
            .numerator = 0,
            .denominator = 1,
            .fallback_fee = null,
            .fee_collector_account_id = null,
            .all_collectors_are_exempt = false,
        };
    }

    pub fn setNumerator(self: *CustomRoyaltyFee, numerator: u64) *CustomRoyaltyFee {
        self.numerator = numerator;
        return self;
    }

    pub fn setDenominator(self: *CustomRoyaltyFee, denominator: u64) *CustomRoyaltyFee {
        if (denominator == 0) {
            self.denominator = 1;
        } else {
            self.denominator = denominator;
            return self;
        }
        return self;
    }

    pub fn setFraction(self: *CustomRoyaltyFee, numerator: u64, denominator: u64) *CustomRoyaltyFee {
        self.numerator = numerator;
        self.denominator = if (denominator == 0) 1 else denominator;
        return self;
    }

    pub fn setFallbackFee(self: *CustomRoyaltyFee, fallback_fee: CustomFixedFee) *CustomRoyaltyFee {
        self.fallback_fee = fallback_fee;
        return self;
    }

    pub fn setFeeCollectorAccountId(self: *CustomRoyaltyFee, account_id: AccountId) *CustomRoyaltyFee {
        self.fee_collector_account_id = account_id;
        return self;
    }

    pub fn setAllCollectorsAreExempt(self: *CustomRoyaltyFee, exempt: bool) *CustomRoyaltyFee {
        self.all_collectors_are_exempt = exempt;
        return self;
    }

    pub fn getNumerator(self: *const CustomRoyaltyFee) u64 {
        return self.numerator;
    }

    pub fn getDenominator(self: *const CustomRoyaltyFee) u64 {
        return self.denominator;
    }

    pub fn getFallbackFee(self: *const CustomRoyaltyFee) ?CustomFixedFee {
        return self.fallback_fee;
    }

    pub fn getFeeCollectorAccountId(self: *const CustomRoyaltyFee) ?AccountId {
        return self.fee_collector_account_id;
    }

    pub fn getAllCollectorsAreExempt(self: *const CustomRoyaltyFee) bool {
        return self.all_collectors_are_exempt;
    }

    pub fn getFraction(self: *const CustomRoyaltyFee) struct { numerator: u64, denominator: u64 } {
        return .{ .numerator = self.numerator, .denominator = self.denominator };
    }

    pub fn getPercentage(self: *const CustomRoyaltyFee) f64 {
        return (@as(f64, @floatFromInt(self.numerator)) / @as(f64, @floatFromInt(self.denominator))) * 100.0;
    }

    pub fn hasFallbackFee(self: *const CustomRoyaltyFee) bool {
        return self.fallback_fee != null;
    }

    pub fn calculateRoyalty(self: *const CustomRoyaltyFee, sale_price: u64) u64 {
        if (self.denominator == 0) return 0;
        return (sale_price * self.numerator) / self.denominator;
    }

    pub fn calculateFee(self: *const CustomRoyaltyFee, sale_price: ?u64) u64 {
        if (sale_price) |price| {
            return self.calculateRoyalty(price);
        } else if (self.fallback_fee) |fallback| {
            return fallback.amount;
        } else {
            return 0;
        }
    }

    pub fn shouldUseFallbackFee(self: *const CustomRoyaltyFee, sale_price: ?u64) bool {
        return sale_price == null and self.fallback_fee != null;
    }

    pub fn toProtobuf(self: *const CustomRoyaltyFee, allocator: std.mem.Allocator) ![]u8 {
        var writer = ProtoWriter.init(allocator);
        defer writer.deinit();

        var exchange_writer = ProtoWriter.init(allocator);
        defer exchange_writer.deinit();
        try exchange_writer.writeUInt64(1, self.numerator);
        try exchange_writer.writeUInt64(2, self.denominator);
        const exchange_bytes = try exchange_writer.toOwnedSlice();
        defer allocator.free(exchange_bytes);
        try writer.writeMessage(1, exchange_bytes);

        if (self.fallback_fee) |fallback| {
            const fallback_bytes = try fallback.toProtobuf(allocator);
            defer allocator.free(fallback_bytes);
            try writer.writeMessage(2, fallback_bytes);
        }

        if (self.fee_collector_account_id) |collector_id| {
            var collector_writer = ProtoWriter.init(allocator);
            defer collector_writer.deinit();
            
            try collector_writer.writeInt64(1, @intCast(collector_id.shard));
            try collector_writer.writeInt64(2, @intCast(collector_id.realm));
            try collector_writer.writeInt64(3, @intCast(collector_id.account));
            
            const collector_bytes = try collector_writer.toOwnedSlice();
            defer allocator.free(collector_bytes);
            try writer.writeMessage(3, collector_bytes);
        }

        try writer.writeBool(4, self.all_collectors_are_exempt);

        return writer.toOwnedSlice();
    }

    pub fn fromProtobuf(data: []const u8, allocator: std.mem.Allocator) !CustomRoyaltyFee {
        var reader = ProtoReader.init(data);
        var fee = CustomRoyaltyFee.init();

        while (try reader.next()) |field| {
            switch (field.number) {
                1 => {
                    var exchange_reader = ProtoReader.init(field.data);
                    while (try exchange_reader.next()) |exchange_field| {
                        switch (exchange_field.number) {
                            1 => fee.numerator = try exchange_reader.readUInt64(exchange_field.data),
                            2 => fee.denominator = try exchange_reader.readUInt64(exchange_field.data),
                            else => {},
                        }
                    }
                },
                2 => {
                    fee.fallback_fee = try CustomFixedFee.fromProtobuf(field.data, allocator);
                },
                3 => {
                    var collector_reader = ProtoReader.init(field.data);
                    var shard: i64 = 0;
                    var realm: i64 = 0;
                    var num: i64 = 0;

                    while (try collector_reader.next()) |collector_field| {
                        switch (collector_field.number) {
                            1 => shard = try collector_reader.readInt64(collector_field.data),
                            2 => realm = try collector_reader.readInt64(collector_field.data),
                            3 => num = try collector_reader.readInt64(collector_field.data),
                            else => {},
                        }
                    }

                    fee.fee_collector_account_id = AccountId.init(@intCast(shard), @intCast(realm), @intCast(num));
                },
                4 => fee.all_collectors_are_exempt = try reader.readBool(field.data),
                else => {},
            }
        }

        return fee;
    }

    pub fn validate(self: *const CustomRoyaltyFee) !void {
        if (self.numerator == 0) {
            return error.ZeroNumerator;
        }

        if (self.denominator == 0) {
            return error.ZeroDenominator;
        }

        if (self.numerator > self.denominator) {
            return error.RoyaltyGreaterThanOne;
        }

        const percentage = self.getPercentage();
        if (percentage > 100.0) {
            return error.RoyaltyExceedsMaximum;
        }

        if (self.fee_collector_account_id == null) {
            return error.MissingFeeCollector;
        }

        if (self.fallback_fee) |fallback| {
            try fallback.validate();
        }
    }

    pub fn simplifyFraction(self: *CustomRoyaltyFee) void {
        const gcd = std.math.gcd(self.numerator, self.denominator);
        if (gcd > 1) {
            self.numerator /= gcd;
            self.denominator /= gcd;
        }
    }

    pub fn clone(self: *const CustomRoyaltyFee) CustomRoyaltyFee {
        return CustomRoyaltyFee{
            .numerator = self.numerator,
            .denominator = self.denominator,
            .fallback_fee = if (self.fallback_fee) |fallback| fallback.clone() else null,
            .fee_collector_account_id = self.fee_collector_account_id,
            .all_collectors_are_exempt = self.all_collectors_are_exempt,
        };
    }

    pub fn equals(self: *const CustomRoyaltyFee, other: *const CustomRoyaltyFee) bool {
        if (self.numerator != other.numerator) return false;
        if (self.denominator != other.denominator) return false;
        if (self.all_collectors_are_exempt != other.all_collectors_are_exempt) return false;

        if (self.fallback_fee == null and other.fallback_fee != null) return false;
        if (self.fallback_fee != null and other.fallback_fee == null) return false;
        if (self.fallback_fee != null and other.fallback_fee != null) {
            if (!self.fallback_fee.?.equals(&other.fallback_fee.?)) return false;
        }

        if (self.fee_collector_account_id == null and other.fee_collector_account_id != null) return false;
        if (self.fee_collector_account_id != null and other.fee_collector_account_id == null) return false;
        if (self.fee_collector_account_id != null and other.fee_collector_account_id != null) {
            const self_collector = self.fee_collector_account_id.?;
            const other_collector = other.fee_collector_account_id.?;
            if (self_collector.shard != other_collector.shard or
                self_collector.realm != other_collector.realm or
                self_collector.account != other_collector.account) {
                return false;
            }
        }

        return true;
    }

    pub fn toString(self: *const CustomRoyaltyFee, allocator: std.mem.Allocator) ![]u8 {
        const fallback_str = if (self.fallback_fee) |fallback| 
            try fallback.toString(allocator)
        else 
            try allocator.dupe(u8, "none");
        defer allocator.free(fallback_str);

        return std.fmt.allocPrint(allocator, "RoyaltyFee{{royalty={d}/{d} ({d:.2}%), fallback={s}, collector={?}}}", .{
            self.numerator,
            self.denominator,
            self.getPercentage(),
            fallback_str,
            self.fee_collector_account_id,
        });
    }

    // Helper methods for common royalty percentages
    pub fn fromPercentage(percentage: f64) CustomRoyaltyFee {
        if (percentage <= 0.0 or percentage > 100.0) {
            return CustomRoyaltyFee.init();
        }

        var fee = CustomRoyaltyFee.init();
        
        if (percentage == @floor(percentage)) {
            fee.numerator = @intFromFloat(percentage);
            fee.denominator = 100;
        } else {
            fee.numerator = @intFromFloat(percentage * 10000.0);
            fee.denominator = 1000000;
        }
        
        fee.simplifyFraction();
        return fee;
    }

    pub fn fromBasisPoints(basis_points: u64) CustomRoyaltyFee {
        if (basis_points > 10000) {
            return CustomRoyaltyFee.init();
        }

        var fee = CustomRoyaltyFee.init();
        fee.numerator = basis_points;
        fee.denominator = 10000;
        fee.simplifyFraction();
        return fee;
    }

    pub fn getBasisPoints(self: *const CustomRoyaltyFee) u64 {
        if (self.denominator == 0) return 0;
        return (self.numerator * 10000) / self.denominator;
    }
};
