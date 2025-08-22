const std = @import("std");

// Hbar unit constants - Zig's compile-time constants for optimal performance
pub const TINYBAR_PER_HBAR: i64 = 100_000_000;
pub const TINYBAR_PER_MICROBAR: i64 = 100;
pub const MICROBAR_PER_HBAR: i64 = 1_000_000;
pub const MILLIBAR_PER_HBAR: i64 = 1_000;
pub const KILOBAR_PER_HBAR: i64 = 1_000;

// Maximum and minimum Hbar values
pub const MAX_HBAR: i64 = 50_000_000_000; // 50 billion hbar
pub const MIN_HBAR: i64 = -50_000_000_000;
pub const MAX_TINYBAR: i64 = MAX_HBAR * TINYBAR_PER_HBAR;
pub const MIN_TINYBAR: i64 = MIN_HBAR * TINYBAR_PER_HBAR;

// HbarUnit enumeration
pub const HbarUnit = enum {
    Tinybar,
    Microbar,
    Millibar,
    Hbar,
    Kilobar,
    Megabar,
    Gigabar,
    
    pub fn symbol(self: HbarUnit) []const u8 {
        return switch (self) {
            .Tinybar => "tℏ",
            .Microbar => "μℏ",
            .Millibar => "mℏ",
            .Hbar => "ℏ",
            .Kilobar => "kℏ",
            .Megabar => "Mℏ",
            .Gigabar => "Gℏ",
        };
    }
    
    // Zig's switch expressions are compile-time optimized vs Go's interface{} runtime dispatch
    pub fn toTinybars(self: HbarUnit, amount: f64) i64 {
        return switch (self) {
            .Tinybar => @intFromFloat(amount),
            .Microbar => @intFromFloat(amount * @as(f64, @floatFromInt(TINYBAR_PER_MICROBAR))),
            .Millibar => @intFromFloat(amount * @as(f64, @floatFromInt(TINYBAR_PER_HBAR / MILLIBAR_PER_HBAR))),
            .Hbar => @intFromFloat(amount * @as(f64, @floatFromInt(TINYBAR_PER_HBAR))),
            .Kilobar => @intFromFloat(amount * @as(f64, @floatFromInt(TINYBAR_PER_HBAR * KILOBAR_PER_HBAR))),
            .Megabar => @intFromFloat(amount * @as(f64, @floatFromInt(TINYBAR_PER_HBAR * 1_000_000))),
            .Gigabar => @intFromFloat(amount * @as(f64, @floatFromInt(TINYBAR_PER_HBAR * 1_000_000_000))),
        };
    }
    
    pub fn fromTinybars(self: HbarUnit, tinybars: i64) f64 {
        const tb_float = @as(f64, @floatFromInt(tinybars));
        return switch (self) {
            .Tinybar => tb_float,
            .Microbar => tb_float / @as(f64, @floatFromInt(TINYBAR_PER_MICROBAR)),
            .Millibar => tb_float / @as(f64, @floatFromInt(TINYBAR_PER_HBAR / MILLIBAR_PER_HBAR)),
            .Hbar => tb_float / @as(f64, @floatFromInt(TINYBAR_PER_HBAR)),
            .Kilobar => tb_float / @as(f64, @floatFromInt(TINYBAR_PER_HBAR * KILOBAR_PER_HBAR)),
            .Megabar => tb_float / @as(f64, @floatFromInt(TINYBAR_PER_HBAR * 1_000_000)),
            .Gigabar => tb_float / @as(f64, @floatFromInt(TINYBAR_PER_HBAR * 1_000_000_000)),
        };
    }
};

// Hbar represents an amount of Hedera cryptocurrency
pub const Hbar = struct {
    tinybars: i64,
    
    // Constructors for different units
    pub fn fromTinybars(amount: i64) !Hbar {
        if (amount > MAX_TINYBAR or amount < MIN_TINYBAR) {
            return error.InvalidParameter;
        }
        return Hbar{ .tinybars = amount };
    }
    
    pub fn from(amount: i64) !Hbar {
        return fromTinybars(amount * TINYBAR_PER_HBAR);
    }
    
    pub fn fromFloat(amount: f64) !Hbar {
        const tinybars = @as(i64, @intFromFloat(amount * @as(f64, @floatFromInt(TINYBAR_PER_HBAR))));
        return fromTinybars(tinybars);
    }
    
    pub fn fromString(str: []const u8) !Hbar {
        // Try to parse as a decimal number
        const trimmed = std.mem.trim(u8, str, " ");
        
        // Check for unit suffix
        var value_str = trimmed;
        var unit = HbarUnit.Hbar;
        
        if (std.mem.endsWith(u8, trimmed, "tℏ") or std.mem.endsWith(u8, trimmed, "t")) {
            unit = HbarUnit.Tinybar;
            value_str = trimmed[0 .. trimmed.len - @min(2, trimmed.len)];
        } else if (std.mem.endsWith(u8, trimmed, "μℏ") or std.mem.endsWith(u8, trimmed, "u")) {
            unit = HbarUnit.Microbar;
            value_str = trimmed[0 .. trimmed.len - @min(2, trimmed.len)];
        } else if (std.mem.endsWith(u8, trimmed, "mℏ") or std.mem.endsWith(u8, trimmed, "m")) {
            unit = HbarUnit.Millibar;
            value_str = trimmed[0 .. trimmed.len - @min(2, trimmed.len)];
        } else if (std.mem.endsWith(u8, trimmed, "ℏ") or std.mem.endsWith(u8, trimmed, "h")) {
            unit = HbarUnit.Hbar;
            value_str = trimmed[0 .. trimmed.len - @min(1, trimmed.len)];
        } else if (std.mem.endsWith(u8, trimmed, "kℏ") or std.mem.endsWith(u8, trimmed, "k")) {
            unit = HbarUnit.Kilobar;
            value_str = trimmed[0 .. trimmed.len - @min(2, trimmed.len)];
        }
        
        // Parse the numeric value
        const value = std.fmt.parseFloat(f64, std.mem.trim(u8, value_str, " ")) catch {
            // Try parsing as integer
            const int_value = std.fmt.parseInt(i64, std.mem.trim(u8, value_str, " "), 10) catch {
                return error.InvalidParameter;
            };
            return fromTinybars(unit.toTinybars(@floatFromInt(int_value)));
        };
        
        return fromTinybars(unit.toTinybars(value));
    }
    
    // Zero value
    pub fn zero() Hbar {
        return Hbar{ .tinybars = 0 };
    }
    
    // Maximum value
    pub fn max() Hbar {
        return Hbar{ .tinybars = MAX_TINYBAR };
    }
    
    // Minimum value
    pub fn min() Hbar {
        return Hbar{ .tinybars = MIN_TINYBAR };
    }
    
    // Get value in different units
    pub fn toTinybars(self: Hbar) i64 {
        return self.tinybars;
    }
    
    pub fn to(self: Hbar, unit: HbarUnit) f64 {
        return unit.fromTinybars(self.tinybars);
    }
    
    pub fn toBigNumber(self: Hbar) i64 {
        return self.tinybars;
    }
    
    pub fn toFloat(self: Hbar) f64 {
        return @as(f64, @floatFromInt(self.tinybars)) / @as(f64, @floatFromInt(TINYBAR_PER_HBAR));
    }
    
    pub fn toHbar(self: Hbar) f64 {
        return self.toFloat();
    }
    
    // String representation
    pub fn toString(self: Hbar, allocator: std.mem.Allocator) ![]u8 {
        return self.toStringWithUnit(allocator, HbarUnit.Hbar);
    }
    
    pub fn toStringWithUnit(self: Hbar, allocator: std.mem.Allocator, unit: HbarUnit) ![]u8 {
        const value = self.to(unit);
        
        // Format with appropriate decimal places
        if (@floor(value) == value) {
            // Integer value
            return std.fmt.allocPrint(allocator, "{d} {s}", .{ @as(i64, @intFromFloat(value)), unit.symbol() });
        } else {
            // Decimal value
            return std.fmt.allocPrint(allocator, "{d:.8} {s}", .{ value, unit.symbol() });
        }
    }
    
    // Arithmetic operations
    pub fn negated(self: Hbar) Hbar {
        // Handle overflow case by clamping to maximum value instead of error
        if (self.tinybars == MIN_TINYBAR) {
            return Hbar{ .tinybars = MAX_TINYBAR };
        }
        return Hbar{ .tinybars = -self.tinybars };
    }
    
    pub fn add(self: Hbar, other: Hbar) !Hbar {
        const result = @addWithOverflow(self.tinybars, other.tinybars);
        if (result[1] != 0) return error.InvalidParameter;
        
        if (result[0] > MAX_TINYBAR or result[0] < MIN_TINYBAR) {
            return error.InvalidParameter;
        }
        
        return Hbar{ .tinybars = result[0] };
    }
    
    pub fn subtract(self: Hbar, other: Hbar) !Hbar {
        const result = @subWithOverflow(self.tinybars, other.tinybars);
        if (result[1] != 0) return error.InvalidParameter;
        
        if (result[0] > MAX_TINYBAR or result[0] < MIN_TINYBAR) {
            return error.InvalidParameter;
        }
        
        return Hbar{ .tinybars = result[0] };
    }
    
    pub fn multiply(self: Hbar, multiplier: i64) !Hbar {
        const result = @mulWithOverflow(self.tinybars, multiplier);
        if (result[1] != 0) return error.InvalidParameter;
        
        if (result[0] > MAX_TINYBAR or result[0] < MIN_TINYBAR) {
            return error.InvalidParameter;
        }
        
        return Hbar{ .tinybars = result[0] };
    }
    
    pub fn divide(self: Hbar, divisor: i64) !Hbar {
        if (divisor == 0) return error.InvalidParameter;
        
        const result = @divTrunc(self.tinybars, divisor);
        return Hbar{ .tinybars = result };
    }
    
    // Comparison operations
    pub fn equals(self: Hbar, other: Hbar) bool {
        return self.tinybars == other.tinybars;
    }
    
    pub fn compare(self: Hbar, other: Hbar) std.math.Order {
        if (self.tinybars < other.tinybars) return .lt;
        if (self.tinybars > other.tinybars) return .gt;
        return .eq;
    }
    
    pub fn isPositive(self: Hbar) bool {
        return self.tinybars > 0;
    }
    
    pub fn isNegative(self: Hbar) bool {
        return self.tinybars < 0;
    }
    
    pub fn isZero(self: Hbar) bool {
        return self.tinybars == 0;
    }
};