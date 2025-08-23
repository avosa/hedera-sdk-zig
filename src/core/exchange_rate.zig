const std = @import("std");
const Hbar = @import("hbar.zig").Hbar;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;
const Timestamp = @import("timestamp.zig").Timestamp;

// Exchange rate between HBAR and USD cents
pub const ExchangeRate = struct {
    hbar_equivalent: i32,
    cent_equivalent: i32,
    expiration_time: ?Timestamp,

    pub fn init(hbar_equivalent: i32, cent_equivalent: i32) ExchangeRate {
        return ExchangeRate{
            .hbar_equivalent = hbar_equivalent,
            .cent_equivalent = cent_equivalent,
            .expiration_time = null,
        };
    }

    pub fn initWithExpiration(hbar_equivalent: i32, cent_equivalent: i32, expiration: Timestamp) ExchangeRate {
        return ExchangeRate{
            .hbar_equivalent = hbar_equivalent,
            .cent_equivalent = cent_equivalent,
            .expiration_time = expiration,
        };
    }

    pub fn setHbarEquivalent(self: *ExchangeRate, hbar_equivalent: i32) *ExchangeRate {
        self.hbar_equivalent = hbar_equivalent;
        return self;
    }

    pub fn setCentEquivalent(self: *ExchangeRate, cent_equivalent: i32) *ExchangeRate {
        self.cent_equivalent = cent_equivalent;
        return self;
    }

    pub fn setExpirationTime(self: *ExchangeRate, expiration: Timestamp) *ExchangeRate {
        self.expiration_time = expiration;
        return self;
    }

    pub fn getHbarEquivalent(self: *const ExchangeRate) i32 {
        return self.hbar_equivalent;
    }

    pub fn getCentEquivalent(self: *const ExchangeRate) i32 {
        return self.cent_equivalent;
    }

    pub fn getExpirationTime(self: *const ExchangeRate) ?Timestamp {
        return self.expiration_time;
    }

    // Convert HBAR to USD cents using this exchange rate
    pub fn hbarToCents(self: *const ExchangeRate, hbar_amount: Hbar) i64 {
        if (self.hbar_equivalent == 0) return 0;
        
        const tinybars = hbar_amount.toTinybars();
        const hbar_whole = @as(f64, @floatFromInt(tinybars)) / 100000000.0;
        const rate = @as(f64, @floatFromInt(self.cent_equivalent)) / @as(f64, @floatFromInt(self.hbar_equivalent));
        
        return @intFromFloat(hbar_whole * rate);
    }

    // Convert USD cents to HBAR using this exchange rate
    pub fn centsToHbar(self: *const ExchangeRate, cent_amount: i64) Hbar {
        if (self.cent_equivalent == 0) return Hbar.ZERO;
        
        const rate = @as(f64, @floatFromInt(self.hbar_equivalent)) / @as(f64, @floatFromInt(self.cent_equivalent));
        const hbar_whole = @as(f64, @floatFromInt(cent_amount)) * rate;
        const tinybars = @as(i64, @intFromFloat(hbar_whole * 100000000.0));
        
        return Hbar.fromTinybars(tinybars);
    }

    // Get the exchange rate as USD per HBAR
    pub fn getUsdPerHbar(self: *const ExchangeRate) f64 {
        if (self.hbar_equivalent == 0) return 0.0;
        return @as(f64, @floatFromInt(self.cent_equivalent)) / (@as(f64, @floatFromInt(self.hbar_equivalent)) * 100.0);
    }

    // Get the exchange rate as HBAR per USD
    pub fn getHbarPerUsd(self: *const ExchangeRate) f64 {
        if (self.cent_equivalent == 0) return 0.0;
        return (@as(f64, @floatFromInt(self.hbar_equivalent)) * 100.0) / @as(f64, @floatFromInt(self.cent_equivalent));
    }

    // Check if the exchange rate is expired
    pub fn isExpired(self: *const ExchangeRate, current_time: Timestamp) bool {
        if (self.expiration_time) |expiration| {
            return current_time.seconds > expiration.seconds or 
                   (current_time.seconds == expiration.seconds and current_time.nanos > expiration.nanos);
        }
        return false;
    }

    // Check if the exchange rate is valid (non-zero denominators)
    pub fn isValid(self: *const ExchangeRate) bool {
        return self.hbar_equivalent > 0 and self.cent_equivalent > 0;
    }

    // Calculate percentage change from another exchange rate
    pub fn getPercentageChange(self: *const ExchangeRate, other: *const ExchangeRate) f64 {
        if (!self.isValid() or !other.isValid()) return 0.0;
        
        const self_rate = self.getUsdPerHbar();
        const other_rate = other.getUsdPerHbar();
        
        if (other_rate == 0.0) return 0.0;
        
        return ((self_rate - other_rate) / other_rate) * 100.0;
    }

    pub fn toProtobuf(self: *const ExchangeRate, allocator: std.mem.Allocator) ![]u8 {
        var writer = ProtoWriter.init(allocator);
        defer writer.deinit();

        // hbar_equivalent = 1
        try writer.writeInt32(1, self.hbar_equivalent);

        // cent_equivalent = 2
        try writer.writeInt32(2, self.cent_equivalent);

        // expiration_time = 3 (optional)
        if (self.expiration_time) |expiration| {
            var time_writer = ProtoWriter.init(allocator);
            defer time_writer.deinit();
            try time_writer.writeInt64(1, expiration.seconds);
            try time_writer.writeInt32(2, expiration.nanos);
            const time_bytes = try time_writer.toOwnedSlice();
            defer allocator.free(time_bytes);
            try writer.writeMessage(3, time_bytes);
        }

        return writer.toOwnedSlice();
    }

    pub fn fromProtobuf(data: []const u8, allocator: std.mem.Allocator) !ExchangeRate {
        _ = allocator;
        var reader = ProtoReader.init(data);
        var rate = ExchangeRate.init(0, 0);

        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => rate.hbar_equivalent = try reader.readInt32(),
                2 => rate.cent_equivalent = try reader.readInt32(),
                3 => {
                    const time_data = try reader.readMessage();
                    var time_reader = ProtoReader.init(time_data);
                    var seconds: i64 = 0;
                    var nanos: i32 = 0;

                    while (time_reader.hasMore()) {
                        const time_tag = try time_reader.readTag();
                        switch (time_tag.field_number) {
                            1 => seconds = try time_reader.readInt64(),
                            2 => nanos = try time_reader.readInt32(),
                            else => try time_reader.skipField(time_tag.wire_type),
                        }
                    }

                    rate.expiration_time = Timestamp{
                        .seconds = seconds,
                        .nanos = nanos,
                    };
                },
                else => try reader.skipField(tag.wire_type),
            }
        }

        return rate;
    }
    
    pub fn fromProtobufBytes(allocator: std.mem.Allocator, data: []const u8) !ExchangeRate {
        return try fromProtobuf(data, allocator);
    }

    pub fn clone(self: *const ExchangeRate) ExchangeRate {
        return ExchangeRate{
            .hbar_equivalent = self.hbar_equivalent,
            .cent_equivalent = self.cent_equivalent,
            .expiration_time = self.expiration_time,
        };
    }

    pub fn equals(self: *const ExchangeRate, other: *const ExchangeRate) bool {
        if (self.hbar_equivalent != other.hbar_equivalent) return false;
        if (self.cent_equivalent != other.cent_equivalent) return false;

        if (self.expiration_time == null and other.expiration_time != null) return false;
        if (self.expiration_time != null and other.expiration_time == null) return false;
        
        if (self.expiration_time != null and other.expiration_time != null) {
            const self_exp = self.expiration_time.?;
            const other_exp = other.expiration_time.?;
            if (self_exp.seconds != other_exp.seconds or self_exp.nanos != other_exp.nanos) {
                return false;
            }
        }

        return true;
    }

    pub fn toString(self: *const ExchangeRate, allocator: std.mem.Allocator) ![]u8 {
        const usd_per_hbar = self.getUsdPerHbar();
        if (self.expiration_time) |expiration| {
            return std.fmt.allocPrint(allocator, "ExchangeRate{{${d:.6}/HBAR, expires={d}.{d:0>9}s}}", .{
                usd_per_hbar,
                expiration.seconds,
                expiration.nanos,
            });
        } else {
            return std.fmt.allocPrint(allocator, "ExchangeRate{{${d:.6}/HBAR}}", .{usd_per_hbar});
        }
    }

    // Create exchange rate from USD per HBAR price
    pub fn fromUsdPerHbar(usd_per_hbar: f64) ExchangeRate {
        const cents_per_hbar = usd_per_hbar * 100.0;
        
        var scale_factor: i32 = 1;
        var scaled_cents = cents_per_hbar;
        
        while (scaled_cents < 1.0 and scale_factor < 1000000) {
            scaled_cents *= 10.0;
            scale_factor *= 10;
        }

        return ExchangeRate.init(scale_factor, @intFromFloat(scaled_cents));
    }

    // Create exchange rate from HBAR per USD price
    pub fn fromHbarPerUsd(hbar_per_usd: f64) ExchangeRate {
        if (hbar_per_usd == 0.0) return ExchangeRate.init(1, 1);
        return ExchangeRate.fromUsdPerHbar(1.0 / hbar_per_usd);
    }

    // Standard mainnet rate (example: 1 HBAR = $0.05)
    pub fn mainnetDefault() ExchangeRate {
        return ExchangeRate.init(1, 5);
    }

    // Standard testnet rate (example: 1 HBAR = $0.01)
    pub fn testnetDefault() ExchangeRate {
        return ExchangeRate.init(1, 1);
    }
};

// Exchange rates set containing current and next rates
pub const ExchangeRates = struct {
    current_rate: ExchangeRate,
    next_rate: ExchangeRate,

    pub fn init(current_rate: ExchangeRate, next_rate: ExchangeRate) ExchangeRates {
        return ExchangeRates{
            .current_rate = current_rate,
            .next_rate = next_rate,
        };
    }

    pub fn getCurrentRate(self: *const ExchangeRates) ExchangeRate {
        return self.current_rate;
    }

    pub fn getNextRate(self: *const ExchangeRates) ExchangeRate {
        return self.next_rate;
    }

    pub fn setCurrentRate(self: *ExchangeRates, rate: ExchangeRate) *ExchangeRates {
        self.current_rate = rate;
        return self;
    }

    pub fn setNextRate(self: *ExchangeRates, rate: ExchangeRate) *ExchangeRates {
        self.next_rate = rate;
        return self;
    }

    // Get the effective rate at a given time
    pub fn getEffectiveRate(self: *const ExchangeRates, timestamp: Timestamp) ExchangeRate {
        if (self.current_rate.isExpired(timestamp) and self.next_rate.isValid()) {
            return self.next_rate;
        }
        return self.current_rate;
    }

    // Check if rates are transitioning (current rate is expired but next rate exists)
    pub fn isTransitioning(self: *const ExchangeRates, timestamp: Timestamp) bool {
        return self.current_rate.isExpired(timestamp) and self.next_rate.isValid();
    }

    pub fn toProtobuf(self: *const ExchangeRates, allocator: std.mem.Allocator) ![]u8 {
        var writer = ProtoWriter.init(allocator);
        defer writer.deinit();

        // current_rate = 1
        const current_bytes = try self.current_rate.toProtobuf(allocator);
        defer allocator.free(current_bytes);
        try writer.writeMessage(1, current_bytes);

        // next_rate = 2
        const next_bytes = try self.next_rate.toProtobuf(allocator);
        defer allocator.free(next_bytes);
        try writer.writeMessage(2, next_bytes);

        return writer.toOwnedSlice();
    }

    pub fn fromProtobuf(data: []const u8, allocator: std.mem.Allocator) !ExchangeRates {
        var reader = ProtoReader.init(data);
        var current_rate = ExchangeRate.init(1, 1);
        var next_rate = ExchangeRate.init(1, 1);

        while (reader.hasMore()) {
            const tag = try reader.readTag();
            switch (tag.field_number) {
                1 => {
                    const rate_data = try reader.readMessage();
                    current_rate = try ExchangeRate.fromProtobuf(rate_data, allocator);
                },
                2 => {
                    const rate_data = try reader.readMessage();
                    next_rate = try ExchangeRate.fromProtobuf(rate_data, allocator);
                },
                else => try reader.skipField(tag.wire_type),
            }
        }

        return ExchangeRates.init(current_rate, next_rate);
    }

    pub fn clone(self: *const ExchangeRates) ExchangeRates {
        return ExchangeRates{
            .current_rate = self.current_rate.clone(),
            .next_rate = self.next_rate.clone(),
        };
    }

    pub fn equals(self: *const ExchangeRates, other: *const ExchangeRates) bool {
        return self.current_rate.equals(&other.current_rate) and 
               self.next_rate.equals(&other.next_rate);
    }
};