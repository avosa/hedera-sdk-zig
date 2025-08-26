const std = @import("std");
const AccountId = @import("../core/id.zig").AccountId;
const TokenId = @import("../core/id.zig").TokenId;
const Hbar = @import("../core/hbar.zig").Hbar;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;

// Fractional fee that charges a percentage of the transfer amount
pub const CustomFractionalFee = struct {
    numerator: u64,
    denominator: u64,
    minimum_amount: u64,
    maximum_amount: u64,
    net_of_transfers: bool,
    fee_collector_account_id: ?AccountId,
    all_collectors_are_exempt: bool,

    pub fn init() CustomFractionalFee {
        return CustomFractionalFee{
            .numerator = 0,
            .denominator = 1,
            .minimum_amount = 0,
            .maximum_amount = 0,
            .net_of_transfers = false,
            .fee_collector_account_id = null,
            .all_collectors_are_exempt = false,
        };
    }

    pub fn setNumerator(self: *CustomFractionalFee, numerator: u64) !*CustomFractionalFee {
        self.numerator = numerator;
        return self;
    }

    pub fn setDenominator(self: *CustomFractionalFee, denominator: u64) !*CustomFractionalFee {
        if (denominator == 0) {
            self.denominator = 1;
        } else {
            self.denominator = denominator;
            return self;
        }
        return self;
    }

    pub fn setFraction(self: *CustomFractionalFee, numerator: u64, denominator: u64) !*CustomFractionalFee {
        self.numerator = numerator;
        self.denominator = if (denominator == 0) 1 else denominator;
        return self;
    }

    pub fn setMinimumAmount(self: *CustomFractionalFee, minimum: u64) !*CustomFractionalFee {
        self.minimum_amount = minimum;
        return self;
    }

    pub fn setMaximumAmount(self: *CustomFractionalFee, maximum: u64) !*CustomFractionalFee {
        self.maximum_amount = maximum;
        return self;
    }

    pub fn setNetOfTransfers(self: *CustomFractionalFee, net_of_transfers: bool) !*CustomFractionalFee {
        self.net_of_transfers = net_of_transfers;
        return self;
    }

    pub fn setFeeCollectorAccountId(self: *CustomFractionalFee, account_id: AccountId) !*CustomFractionalFee {
        self.fee_collector_account_id = account_id;
        return self;
    }

    pub fn setAllCollectorsAreExempt(self: *CustomFractionalFee, exempt: bool) !*CustomFractionalFee {
        self.all_collectors_are_exempt = exempt;
        return self;
    }

    pub fn getNumerator(self: *const CustomFractionalFee) u64 {
        return self.numerator;
    }

    pub fn getDenominator(self: *const CustomFractionalFee) u64 {
        return self.denominator;
    }

    pub fn getMinimumAmount(self: *const CustomFractionalFee) u64 {
        return self.minimum_amount;
    }

    pub fn getMaximumAmount(self: *const CustomFractionalFee) u64 {
        return self.maximum_amount;
    }

    pub fn getNetOfTransfers(self: *const CustomFractionalFee) bool {
        return self.net_of_transfers;
    }

    pub fn getFeeCollectorAccountId(self: *const CustomFractionalFee) ?AccountId {
        return self.fee_collector_account_id;
    }

    pub fn getAllCollectorsAreExempt(self: *const CustomFractionalFee) bool {
        return self.all_collectors_are_exempt;
    }

    pub fn getFraction(self: *const CustomFractionalFee) struct { numerator: u64, denominator: u64 } {
        return .{ .numerator = self.numerator, .denominator = self.denominator };
    }

    pub fn getPercentage(self: *const CustomFractionalFee) f64 {
        return (@as(f64, @floatFromInt(self.numerator)) / @as(f64, @floatFromInt(self.denominator))) * 100.0;
    }

    pub fn calculateFee(self: *const CustomFractionalFee, transfer_amount: u64) u64 {
        if (self.denominator == 0) return 0;

        var fee_amount = (transfer_amount * self.numerator) / self.denominator;

        if (self.minimum_amount > 0 and fee_amount < self.minimum_amount) {
            fee_amount = self.minimum_amount;
            return self;
        }

        if (self.maximum_amount > 0 and fee_amount > self.maximum_amount) {
            fee_amount = self.maximum_amount;
        }

        return fee_amount;
    }

    pub fn calculateEffectiveAmount(self: *const CustomFractionalFee, transfer_amount: u64) struct { net_amount: u64, fee_amount: u64 } {
        const fee_amount = self.calculateFee(transfer_amount);
        
        if (self.net_of_transfers) {
            return .{ .net_amount = transfer_amount, .fee_amount = fee_amount };
        } else {
            return .{ .net_amount = transfer_amount - fee_amount, .fee_amount = fee_amount };
        }
    }

    pub fn toProtobuf(self: *const CustomFractionalFee, allocator: std.mem.Allocator) ![]u8 {
        var writer = ProtoWriter.init(allocator);
        defer writer.deinit();

        var fraction_writer = ProtoWriter.init(allocator);
        defer fraction_writer.deinit();
        try fraction_writer.writeUInt64(1, self.numerator);
        try fraction_writer.writeUInt64(2, self.denominator);
        const fraction_bytes = try fraction_writer.toOwnedSlice();
        defer allocator.free(fraction_bytes);
        try writer.writeMessage(1, fraction_bytes);

        if (self.minimum_amount > 0) {
            try writer.writeUInt64(2, self.minimum_amount);
        }

        if (self.maximum_amount > 0) {
            try writer.writeUInt64(3, self.maximum_amount);
        }

        try writer.writeBool(4, self.net_of_transfers);

        if (self.fee_collector_account_id) |collector_id| {
            var collector_writer = ProtoWriter.init(allocator);
            defer collector_writer.deinit();
            
            try collector_writer.writeInt64(1, @intCast(collector_id.shard));
            try collector_writer.writeInt64(2, @intCast(collector_id.realm));
            try collector_writer.writeInt64(3, @intCast(collector_id.account));
            
            const collector_bytes = try collector_writer.toOwnedSlice();
            defer allocator.free(collector_bytes);
            try writer.writeMessage(5, collector_bytes);
        }

        try writer.writeBool(6, self.all_collectors_are_exempt);

        return writer.toOwnedSlice();
    }

    pub fn fromProtobuf(data: []const u8, allocator: std.mem.Allocator) !CustomFractionalFee {
        _ = allocator;
        var reader = ProtoReader.init(data);
        var fee = CustomFractionalFee.init();

        while (try reader.next()) |field| {
            switch (field.number) {
                1 => {
                    var fraction_reader = ProtoReader.init(field.data);
                    while (try fraction_reader.next()) |fraction_field| {
                        switch (fraction_field.number) {
                            1 => fee.numerator = try fraction_reader.readUInt64(fraction_field.data),
                            2 => fee.denominator = try fraction_reader.readUInt64(fraction_field.data),
                            else => {},
                        }
                    }
                },
                2 => fee.minimum_amount = try reader.readUInt64(field.data),
                3 => fee.maximum_amount = try reader.readUInt64(field.data),
                4 => fee.net_of_transfers = try reader.readBool(field.data),
                5 => {
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

                    fee.fee_collector_account_id = AccountId{
                        .entity = .{
                            .shard = shard,
                            .realm = realm,
                            .num = num,
                        },
                    };
                },
                6 => fee.all_collectors_are_exempt = try reader.readBool(field.data),
                else => {},
            }
        }

        return fee;
    }

    pub fn validate(self: *const CustomFractionalFee) !void {
        if (self.numerator == 0) {
            return error.ZeroNumerator;
        }

        if (self.denominator == 0) {
            return error.ZeroDenominator;
        }

        if (self.numerator > self.denominator) {
            return error.FractionGreaterThanOne;
        }

        if (self.minimum_amount > 0 and self.maximum_amount > 0 and self.minimum_amount > self.maximum_amount) {
            return error.MinimumGreaterThanMaximum;
        }

        if (self.fee_collector_account_id == null) {
            return error.MissingFeeCollector;
        }
    }

    pub fn simplifyFraction(self: *CustomFractionalFee) void {
        const gcd = std.math.gcd(self.numerator, self.denominator);
        if (gcd > 1) {
            self.numerator /= gcd;
            self.denominator /= gcd;
        }
    }

    pub fn clone(self: *const CustomFractionalFee) CustomFractionalFee {
        return CustomFractionalFee{
            .numerator = self.numerator,
            .denominator = self.denominator,
            .minimum_amount = self.minimum_amount,
            .maximum_amount = self.maximum_amount,
            .net_of_transfers = self.net_of_transfers,
            .fee_collector_account_id = self.fee_collector_account_id,
            .all_collectors_are_exempt = self.all_collectors_are_exempt,
        };
    }

    pub fn equals(self: *const CustomFractionalFee, other: *const CustomFractionalFee) bool {
        if (self.numerator != other.numerator) return false;
        if (self.denominator != other.denominator) return false;
        if (self.minimum_amount != other.minimum_amount) return false;
        if (self.maximum_amount != other.maximum_amount) return false;
        if (self.net_of_transfers != other.net_of_transfers) return false;
        if (self.all_collectors_are_exempt != other.all_collectors_are_exempt) return false;

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

    pub fn toString(self: *const CustomFractionalFee, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "FractionalFee{{fraction={d}/{d} ({d:.2}%), min={d}, max={d}, netOfTransfers={}, collector={?}}}", .{
            self.numerator,
            self.denominator,
            self.getPercentage(),
            self.minimum_amount,
            self.maximum_amount,
            self.net_of_transfers,
            self.fee_collector_account_id,
        });
    }
};
