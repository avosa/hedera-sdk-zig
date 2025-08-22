const std = @import("std");
const Allocator = std.mem.Allocator;
const RequestType = @import("../core/request_type.zig").RequestType;
const FeeData = @import("../core/fee_data.zig").FeeData;
const protobuf = @import("../protobuf/protobuf.zig");

pub const TransactionFeeSchedule = struct {
    request_type: RequestType,
    fee_data: ?*FeeData, // Deprecated: use fees
    fees: []const *FeeData,
    allocator: Allocator,
    
    const Self = @This();
    
    pub fn init(allocator: Allocator, request_type: RequestType) Self {
        return Self{
            .request_type = request_type,
            .fee_data = null,
            .fees = &[_]*FeeData{},
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Self) void {
        if (self.fee_data) |fee_data| {
            fee_data.deinit();
            self.allocator.destroy(fee_data);
        }
        
        for (self.fees) |fee| {
            fee.deinit();
            self.allocator.destroy(fee);
        }
        
        if (self.fees.len > 0) {
            self.allocator.free(self.fees);
        }
    }
    
    pub fn setFeeData(self: *Self, fee_data: *FeeData) *Self {
        if (self.fee_data) |old_fee_data| {
            old_fee_data.deinit();
            self.allocator.destroy(old_fee_data);
        }
        self.fee_data = fee_data;
        return self;
    }
    
    pub fn setFees(self: *Self, fees: []const *FeeData) !*Self {
        // Clean up existing fees
        for (self.fees) |fee| {
            fee.deinit();
            self.allocator.destroy(fee);
        }
        if (self.fees.len > 0) {
            self.allocator.free(self.fees);
        }
        
        // Clone and set new fees
        var new_fees = try self.allocator.alloc(*FeeData, fees.len);
        for (fees, 0..) |fee, i| {
            const cloned_fee = try self.allocator.create(FeeData);
            cloned_fee.* = try fee.clone(self.allocator);
            new_fees[i] = cloned_fee;
        }
        
        self.fees = new_fees;
        return self;
    }
    
    pub fn addFee(self: *Self, fee_data: *FeeData) !*Self {
        var new_fees = try self.allocator.alloc(*FeeData, self.fees.len + 1);
        
        // Copy existing fees
        @memcpy(new_fees[0..self.fees.len], self.fees);
        
        // Add new fee
        new_fees[self.fees.len] = fee_data;
        
        // Free old array and update
        if (self.fees.len > 0) {
            self.allocator.free(self.fees);
        }
        self.fees = new_fees;
        
        return self;
    }
    
    pub fn fromProtobufBytes(allocator: Allocator, bytes: []const u8) !Self {
        var reader = protobuf.ProtobufReader.init(allocator, bytes);
        
        var request_type: RequestType = .None;
        var fee_data: ?*FeeData = null;
        var fees = std.ArrayList(*FeeData).init(allocator);
        defer {
            for (fees.items) |fee| {
                fee.deinit();
                allocator.destroy(fee);
            }
            fees.deinit();
        }
        
        while (try reader.nextField()) |field| {
            switch (field.tag) {
                1 => {
                    // hederaFunctionality = 1
                    const functionality = try field.readVarint();
                    request_type = try RequestType.fromInt(@intCast(u32, functionality));
                },
                2 => {
                    // feeData = 2 (deprecated)
                    const fee_bytes = try field.readBytes(allocator);
                    defer allocator.free(fee_bytes);
                    
                    const fee = try allocator.create(FeeData);
                    fee.* = try FeeData.fromProtobufBytes(allocator, fee_bytes);
                    fee_data = fee;
                },
                3 => {
                    // fees = 3 (repeated)
                    const fee_bytes = try field.readBytes(allocator);
                    defer allocator.free(fee_bytes);
                    
                    const fee = try allocator.create(FeeData);
                    fee.* = try FeeData.fromProtobufBytes(allocator, fee_bytes);
                    try fees.append(fee);
                },
                else => try field.skip(),
            }
        }
        
        var result = Self.init(allocator, request_type);
        result.fee_data = fee_data;
        
        if (fees.items.len > 0) {
            result.fees = try allocator.dupe(*FeeData, fees.items);
            // Don't let the defer clean up the fees since we're transferring ownership
            fees.clearRetainingCapacity();
        }
        
        return result;
    }
    
    pub fn toProtobufBytes(self: *const Self, allocator: Allocator) ![]u8 {
        var writer = protobuf.ProtobufWriter.init(allocator);
        defer writer.deinit();
        
        // hederaFunctionality = 1
        try writer.writeEnumField(1, RequestType, self.request_type);
        
        // feeData = 2 (deprecated)
        if (self.fee_data) |fee_data| {
            const fee_bytes = try fee_data.toProtobufBytes(allocator);
            defer allocator.free(fee_bytes);
            try writer.writeMessageField(2, fee_bytes);
        }
        
        // fees = 3 (repeated)
        for (self.fees) |fee| {
            const fee_bytes = try fee.toProtobufBytes(allocator);
            defer allocator.free(fee_bytes);
            try writer.writeMessageField(3, fee_bytes);
        }
        
        return try writer.toOwnedSlice();
    }
    
    pub fn getRequestType(self: *const Self) RequestType {
        return self.request_type;
    }
    
    pub fn getFeeData(self: *const Self) ?*const FeeData {
        return self.fee_data;
    }
    
    pub fn getFees(self: *const Self) []const *FeeData {
        return self.fees;
    }
    
    pub fn getDefaultFee(self: *const Self) ?*const FeeData {
        if (self.fees.len > 0) {
            return self.fees[0];
        }
        return self.fee_data;
    }
    
    pub fn findFeeForSubType(self: *const Self, sub_type: RequestType) ?*const FeeData {
        for (self.fees) |fee| {
            if (fee.getSubType() == sub_type) {
                return fee;
            }
        }
        return null;
    }
    
    pub fn clone(self: *const Self, allocator: Allocator) !Self {
        var cloned = Self.init(allocator, self.request_type);
        
        if (self.fee_data) |fee_data| {
            const cloned_fee_data = try allocator.create(FeeData);
            cloned_fee_data.* = try fee_data.clone(allocator);
            cloned.fee_data = cloned_fee_data;
        }
        
        if (self.fees.len > 0) {
            var cloned_fees = try allocator.alloc(*FeeData, self.fees.len);
            for (self.fees, 0..) |fee, i| {
                const cloned_fee = try allocator.create(FeeData);
                cloned_fee.* = try fee.clone(allocator);
                cloned_fees[i] = cloned_fee;
            }
            cloned.fees = cloned_fees;
        }
        
        return cloned;
    }
    
    pub fn toString(self: *const Self, allocator: Allocator) ![]u8 {
        return try std.fmt.allocPrint(allocator,
            "TransactionFeeSchedule{{request_type={s}, fees_count={d}}}",
            .{ @tagName(self.request_type), self.fees.len }
        );
    }
    
    pub fn toJson(self: *const Self, allocator: Allocator) ![]u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        defer buffer.deinit();
        
        try buffer.appendSlice("{");
        try buffer.writer().print("\"requestType\":\"{s}\",", .{@tagName(self.request_type)});
        
        if (self.fee_data) |fee_data| {
            const fee_json = try fee_data.toJson(allocator);
            defer allocator.free(fee_json);
            try buffer.writer().print("\"feeData\":{s},", .{fee_json});
        }
        
        try buffer.appendSlice("\"fees\":[");
        for (self.fees, 0..) |fee, i| {
            if (i > 0) try buffer.appendSlice(",");
            const fee_json = try fee.toJson(allocator);
            defer allocator.free(fee_json);
            try buffer.appendSlice(fee_json);
        }
        try buffer.appendSlice("]");
        
        try buffer.appendSlice("}");
        
        return try allocator.dupe(u8, buffer.items);
    }
};