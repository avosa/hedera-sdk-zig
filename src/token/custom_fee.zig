const std = @import("std");
const AccountId = @import("../core/id.zig").AccountId;
const TokenId = @import("../core/id.zig").TokenId;
const Hbar = @import("../core/hbar.zig").Hbar;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;
const CustomFixedFee = @import("custom_fixed_fee.zig").CustomFixedFee;
const CustomFractionalFee = @import("custom_fractional_fee.zig").CustomFractionalFee;
const CustomRoyaltyFee = @import("custom_royalty_fee.zig").CustomRoyaltyFee;

// Union type for all custom fee types
pub const CustomFee = union(enum) {
    fixed: CustomFixedFee,
    fractional: CustomFractionalFee,
    royalty: CustomRoyaltyFee,

    pub fn initFixed() CustomFee {
        return CustomFee{ .fixed = CustomFixedFee.init() };
    }

    pub fn initFractional() CustomFee {
        return CustomFee{ .fractional = CustomFractionalFee.init() };
    }

    pub fn initRoyalty() CustomFee {
        return CustomFee{ .royalty = CustomRoyaltyFee.init() };
    }

    pub fn getFeeCollectorAccountId(self: *const CustomFee) ?AccountId {
        return switch (self.*) {
            .fixed => |fee| fee.getFeeCollectorAccountId(),
            .fractional => |fee| fee.getFeeCollectorAccountId(),
            .royalty => |fee| fee.getFeeCollectorAccountId(),
        };
    }

    pub fn getAllCollectorsAreExempt(self: *const CustomFee) bool {
        return switch (self.*) {
            .fixed => |fee| fee.getAllCollectorsAreExempt(),
            .fractional => |fee| fee.getAllCollectorsAreExempt(),
            .royalty => |fee| fee.getAllCollectorsAreExempt(),
        };
    }

    pub fn setFeeCollectorAccountId(self: *CustomFee, account_id: AccountId) void {
        switch (self.*) {
            .fixed => |*fee| _ = fee.setFeeCollectorAccountId(account_id),
            .fractional => |*fee| _ = fee.setFeeCollectorAccountId(account_id),
            .royalty => |*fee| _ = fee.setFeeCollectorAccountId(account_id),
        }
    }

    pub fn setAllCollectorsAreExempt(self: *CustomFee, exempt: bool) void {
        switch (self.*) {
            .fixed => |*fee| _ = fee.setAllCollectorsAreExempt(exempt),
            .fractional => |*fee| _ = fee.setAllCollectorsAreExempt(exempt),
            .royalty => |*fee| _ = fee.setAllCollectorsAreExempt(exempt),
        }
    }

    pub fn calculateFee(self: *const CustomFee, transfer_amount: u64, sale_price: ?u64) u64 {
        return switch (self.*) {
            .fixed => |fee| fee.calculateFee(transfer_amount),
            .fractional => |fee| fee.calculateFee(transfer_amount),
            .royalty => |fee| fee.calculateFee(sale_price),
        };
    }

    pub fn validate(self: *const CustomFee) !void {
        return switch (self.*) {
            .fixed => |fee| fee.validate(),
            .fractional => |fee| fee.validate(),
            .royalty => |fee| fee.validate(),
        };
    }

    pub fn clone(self: *const CustomFee) CustomFee {
        return switch (self.*) {
            .fixed => |fee| CustomFee{ .fixed = fee.clone() },
            .fractional => |fee| CustomFee{ .fractional = fee.clone() },
            .royalty => |fee| CustomFee{ .royalty = fee.clone() },
        };
    }

    pub fn equals(self: *const CustomFee, other: *const CustomFee) bool {
        if (std.meta.activeTag(self.*) != std.meta.activeTag(other.*)) {
            return false;
        }

        return switch (self.*) {
            .fixed => |fee| fee.equals(&other.fixed),
            .fractional => |fee| fee.equals(&other.fractional),
            .royalty => |fee| fee.equals(&other.royalty),
        };
    }

    pub fn toString(self: *const CustomFee, allocator: std.mem.Allocator) ![]u8 {
        return switch (self.*) {
            .fixed => |fee| fee.toString(allocator),
            .fractional => |fee| fee.toString(allocator),
            .royalty => |fee| fee.toString(allocator),
        };
    }

    pub fn toProtobuf(self: *const CustomFee, allocator: std.mem.Allocator) ![]u8 {
        var writer = ProtoWriter.init(allocator);
        defer writer.deinit();

        switch (self.*) {
            .fixed => |fee| {
                const fee_bytes = try fee.toProtobuf(allocator);
                defer allocator.free(fee_bytes);
                try writer.writeMessage(1, fee_bytes);
            },
            .fractional => |fee| {
                const fee_bytes = try fee.toProtobuf(allocator);
                defer allocator.free(fee_bytes);
                try writer.writeMessage(2, fee_bytes);
            },
            .royalty => |fee| {
                const fee_bytes = try fee.toProtobuf(allocator);
                defer allocator.free(fee_bytes);
                try writer.writeMessage(3, fee_bytes);
            },
        }

        return writer.toOwnedSlice();
    }

    pub fn fromProtobuf(data: []const u8, allocator: std.mem.Allocator) !CustomFee {
        var reader = ProtoReader.init(data);

        while (try reader.next()) |field| {
            switch (field.number) {
                1 => {
                    const fixed_fee = try CustomFixedFee.fromProtobuf(field.data, allocator);
                    return CustomFee{ .fixed = fixed_fee };
                },
                2 => {
                    const fractional_fee = try CustomFractionalFee.fromProtobuf(field.data, allocator);
                    return CustomFee{ .fractional = fractional_fee };
                },
                3 => {
                    const royalty_fee = try CustomRoyaltyFee.fromProtobuf(field.data, allocator);
                    return CustomFee{ .royalty = royalty_fee };
                },
                else => {},
            }
        }

        return error.InvalidCustomFee;
    }

    pub fn getType(self: *const CustomFee) CustomFeeType {
        return switch (self.*) {
            .fixed => .Fixed,
            .fractional => .Fractional,
            .royalty => .Royalty,
        };
    }

    pub fn isFixed(self: *const CustomFee) bool {
        return switch (self.*) {
            .fixed => true,
            else => false,
        };
    }

    pub fn isFractional(self: *const CustomFee) bool {
        return switch (self.*) {
            .fractional => true,
            else => false,
        };
    }

    pub fn isRoyalty(self: *const CustomFee) bool {
        return switch (self.*) {
            .royalty => true,
            else => false,
        };
    }

    pub fn asFixed(self: *const CustomFee) ?*const CustomFixedFee {
        return switch (self.*) {
            .fixed => |*fee| fee,
            else => null,
        };
    }

    pub fn asFractional(self: *const CustomFee) ?*const CustomFractionalFee {
        return switch (self.*) {
            .fractional => |*fee| fee,
            else => null,
        };
    }

    pub fn asRoyalty(self: *const CustomFee) ?*const CustomRoyaltyFee {
        return switch (self.*) {
            .royalty => |*fee| fee,
            else => null,
        };
    }
};

pub const CustomFeeType = enum {
    Fixed,
    Fractional,
    Royalty,

    pub fn toString(self: CustomFeeType) []const u8 {
        return switch (self) {
            .Fixed => "Fixed",
            .Fractional => "Fractional",
            .Royalty => "Royalty",
        };
    }
};

// Collection of custom fees for a token
pub const CustomFeeList = struct {
    fees: std.ArrayList(CustomFee),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CustomFeeList {
        return CustomFeeList{
            .fees = std.ArrayList(CustomFee).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CustomFeeList) void {
        self.fees.deinit();
    }

    pub fn add(self: *CustomFeeList, fee: CustomFee) !void {
        try self.fees.append(fee);
    }

    pub fn addFixed(self: *CustomFeeList, fee: CustomFixedFee) !void {
        try self.add(CustomFee{ .fixed = fee });
    }

    pub fn addFractional(self: *CustomFeeList, fee: CustomFractionalFee) !void {
        try self.add(CustomFee{ .fractional = fee });
    }

    pub fn addRoyalty(self: *CustomFeeList, fee: CustomRoyaltyFee) !void {
        try self.add(CustomFee{ .royalty = fee });
    }

    pub fn get(self: *const CustomFeeList, index: usize) ?*const CustomFee {
        if (index >= self.fees.items.len) return null;
        return &self.fees.items[index];
    }

    pub fn size(self: *const CustomFeeList) usize {
        return self.fees.items.len;
    }

    pub fn isEmpty(self: *const CustomFeeList) bool {
        return self.fees.items.len == 0;
    }

    pub fn clear(self: *CustomFeeList) void {
        self.fees.clearRetainingCapacity();
    }

    pub fn remove(self: *CustomFeeList, index: usize) bool {
        if (index >= self.fees.items.len) return false;
        _ = self.fees.orderedRemove(index);
        return true;
    }

    pub fn calculateTotalFees(self: *const CustomFeeList, transfer_amount: u64, sale_price: ?u64) u64 {
        var total: u64 = 0;
        for (self.fees.items) |fee| {
            total += fee.calculateFee(transfer_amount, sale_price);
        }
        return total;
    }

    pub fn validateAll(self: *const CustomFeeList) !void {
        for (self.fees.items) |fee| {
            try fee.validate();
        }
    }

    pub fn getFixedFees(self: *const CustomFeeList, allocator: std.mem.Allocator) ![]CustomFixedFee {
        var result = std.ArrayList(CustomFixedFee).init(allocator);
        defer result.deinit();

        for (self.fees.items) |fee| {
            if (fee.isFixed()) {
                try result.append(fee.fixed);
            }
        }

        return result.toOwnedSlice();
    }

    pub fn getFractionalFees(self: *const CustomFeeList, allocator: std.mem.Allocator) ![]CustomFractionalFee {
        var result = std.ArrayList(CustomFractionalFee).init(allocator);
        defer result.deinit();

        for (self.fees.items) |fee| {
            if (fee.isFractional()) {
                try result.append(fee.fractional);
            }
        }

        return result.toOwnedSlice();
    }

    pub fn getRoyaltyFees(self: *const CustomFeeList, allocator: std.mem.Allocator) ![]CustomRoyaltyFee {
        var result = std.ArrayList(CustomRoyaltyFee).init(allocator);
        defer result.deinit();

        for (self.fees.items) |fee| {
            if (fee.isRoyalty()) {
                try result.append(fee.royalty);
            }
        }

        return result.toOwnedSlice();
    }

    pub fn clone(self: *const CustomFeeList, allocator: std.mem.Allocator) !CustomFeeList {
        var result = CustomFeeList.init(allocator);
        for (self.fees.items) |fee| {
            try result.add(fee.clone());
        }
        return result;
    }

    pub fn toProtobuf(self: *const CustomFeeList, allocator: std.mem.Allocator) ![]u8 {
        var writer = ProtoWriter.init(allocator);
        defer writer.deinit();

        for (self.fees.items) |fee| {
            const fee_bytes = try fee.toProtobuf(allocator);
            defer allocator.free(fee_bytes);
            try writer.writeMessage(1, fee_bytes);
        }

        return writer.toOwnedSlice();
    }

    pub fn fromProtobuf(data: []const u8, allocator: std.mem.Allocator) !CustomFeeList {
        var reader = ProtoReader.init(data);
        var list = CustomFeeList.init(allocator);
        errdefer list.deinit();

        while (try reader.next()) |field| {
            if (field.number == 1) {
                const fee = try CustomFee.fromProtobuf(field.data, allocator);
                try list.add(fee);
            }
        }

        return list;
    }
};