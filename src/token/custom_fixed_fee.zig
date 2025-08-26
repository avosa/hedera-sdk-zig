const std = @import("std");
const AccountId = @import("../core/id.zig").AccountId;
const TokenId = @import("../core/id.zig").TokenId;
const Hbar = @import("../core/hbar.zig").Hbar;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;

// Fixed fee that charges a set amount of HBAR or token units
pub const CustomFixedFee = struct {
    amount: u64,
    denomination_token_id: ?TokenId,
    fee_collector_account_id: ?AccountId,
    all_collectors_are_exempt: bool,

    pub fn init() CustomFixedFee {
        return CustomFixedFee{
            .amount = 0,
            .denomination_token_id = null,
            .fee_collector_account_id = null,
            .all_collectors_are_exempt = false,
        };
    }

    pub fn setAmount(self: *CustomFixedFee, amount: u64) !*CustomFixedFee {
        self.amount = amount;
        return self;
    }

    pub fn setHbarAmount(self: *CustomFixedFee, hbar: Hbar) !*CustomFixedFee {
        self.amount = hbar.toTinybars();
        self.denomination_token_id = null;
        return self;
    }

    pub fn setDenominationTokenId(self: *CustomFixedFee, token_id: TokenId) !*CustomFixedFee {
        self.denomination_token_id = token_id;
        return self;
    }

    pub fn setFeeCollectorAccountId(self: *CustomFixedFee, account_id: AccountId) !*CustomFixedFee {
        self.fee_collector_account_id = account_id;
        return self;
    }

    pub fn setAllCollectorsAreExempt(self: *CustomFixedFee, exempt: bool) !*CustomFixedFee {
        self.all_collectors_are_exempt = exempt;
        return self;
    }

    pub fn getAmount(self: *const CustomFixedFee) u64 {
        return self.amount;
    }

    pub fn getDenominationTokenId(self: *const CustomFixedFee) ?TokenId {
        return self.denomination_token_id;
    }

    pub fn getFeeCollectorAccountId(self: *const CustomFixedFee) ?AccountId {
        return self.fee_collector_account_id;
    }

    pub fn getAllCollectorsAreExempt(self: *const CustomFixedFee) bool {
        return self.all_collectors_are_exempt;
    }

    pub fn isHbarFee(self: *const CustomFixedFee) bool {
        return self.denomination_token_id == null;
    }

    pub fn isTokenFee(self: *const CustomFixedFee) bool {
        return self.denomination_token_id != null;
    }

    pub fn getHbarAmount(self: *const CustomFixedFee) !Hbar {
        if (!self.isHbarFee()) {
            return error.NotHbarFee;
        }
        return Hbar.fromTinybars(@intCast(self.amount));
    }

    pub fn calculateFee(self: *const CustomFixedFee, transfer_amount: u64) u64 {
        _ = transfer_amount;
        return self.amount;
    }

    pub fn toProtobuf(self: *const CustomFixedFee, allocator: std.mem.Allocator) ![]u8 {
        var writer = ProtoWriter.init(allocator);
        defer writer.deinit();

        try writer.writeUInt64(1, self.amount);

        if (self.denomination_token_id) |token_id| {
            var token_writer = ProtoWriter.init(allocator);
            defer token_writer.deinit();
            
            try token_writer.writeInt64(1, @intCast(token_id.shard));
            try token_writer.writeInt64(2, @intCast(token_id.realm));
            try token_writer.writeInt64(3, @intCast(token_id.num));
            
            const token_bytes = try token_writer.toOwnedSlice();
            defer allocator.free(token_bytes);
            try writer.writeMessage(2, token_bytes);
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

    pub fn fromProtobuf(data: []const u8, allocator: std.mem.Allocator) !CustomFixedFee {
        _ = allocator;
        var reader = ProtoReader.init(data);
        var fee = CustomFixedFee.init();

        while (reader.hasMore()) {
            const tag = try reader.readTag();
            switch (tag.field_number) {
                1 => fee.amount = try reader.readUint64(),
                2 => {
                    const token_data = try reader.readBytes();
                    var token_reader = ProtoReader.init(token_data);
                    var shard: i64 = 0;
                    var realm: i64 = 0;
                    var num: i64 = 0;

                    while (token_reader.hasMore()) {
                        const token_tag = try token_reader.readTag();
                        switch (token_tag.field_number) {
                            1 => shard = try token_reader.readInt64(),
                            2 => realm = try token_reader.readInt64(),
                            3 => num = try token_reader.readInt64(),
                            else => try token_reader.skipField(token_tag.wire_type),
                        }
                    }

                    fee.denomination_token_id = TokenId{
                        .entity = .{
                            .shard = @intCast(shard),
                            .realm = @intCast(realm),
                            .num = @intCast(num),
                        },
                    };
                },
                3 => {
                    const collector_data = try reader.readBytes();
                    var collector_reader = ProtoReader.init(collector_data);
                    var shard: i64 = 0;
                    var realm: i64 = 0;
                    var num: i64 = 0;

                    while (collector_reader.hasMore()) {
                        const collector_tag = try collector_reader.readTag();
                        switch (collector_tag.field_number) {
                            1 => shard = try collector_reader.readInt64(),
                            2 => realm = try collector_reader.readInt64(),
                            3 => num = try collector_reader.readInt64(),
                            else => try collector_reader.skipField(collector_tag.wire_type),
                        }
                    }

                    fee.fee_collector_account_id = AccountId{
                        .shard = @intCast(shard),
                        .realm = @intCast(realm),
                        .account = @intCast(num),
                        .alias_key = null,
                        .alias_evm_address = null,
                        .checksum = null,
                    };
                },
                4 => fee.all_collectors_are_exempt = try reader.readBool(),
                else => try reader.skipField(tag.wire_type),
            }
        }

        return fee;
    }

    pub fn validate(self: *const CustomFixedFee) !void {
        if (self.amount == 0) {
            return error.ZeroAmount;
        }

        if (self.fee_collector_account_id == null) {
            return error.MissingFeeCollector;
        }
    }

    pub fn clone(self: *const CustomFixedFee) CustomFixedFee {
        return CustomFixedFee{
            .amount = self.amount,
            .denomination_token_id = self.denomination_token_id,
            .fee_collector_account_id = self.fee_collector_account_id,
            .all_collectors_are_exempt = self.all_collectors_are_exempt,
        };
    }

    pub fn equals(self: *const CustomFixedFee, other: *const CustomFixedFee) bool {
        if (self.amount != other.amount) return false;
        if (self.all_collectors_are_exempt != other.all_collectors_are_exempt) return false;

        if (self.denomination_token_id == null and other.denomination_token_id != null) return false;
        if (self.denomination_token_id != null and other.denomination_token_id == null) return false;
        if (self.denomination_token_id != null and other.denomination_token_id != null) {
            const self_token = self.denomination_token_id.?;
            const other_token = other.denomination_token_id.?;
            if (self_token.shard != other_token.shard or
                self_token.realm != other_token.realm or
                self_token.num != other_token.num) {
                return false;
            }
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

    pub fn toString(self: *const CustomFixedFee, allocator: std.mem.Allocator) ![]u8 {
        if (self.isHbarFee()) {
            const hbar_amount = try self.getHbarAmount();
            return std.fmt.allocPrint(allocator, "FixedFee{{amount={}, collector={?}}}", .{
                hbar_amount.toString(),
                self.fee_collector_account_id,
            });
        } else {
            return std.fmt.allocPrint(allocator, "FixedFee{{amount={d}, token={?}, collector={?}}}", .{
                self.amount,
                self.denomination_token_id,
                self.fee_collector_account_id,
            });
        }
    }
};
