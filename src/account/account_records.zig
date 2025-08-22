const std = @import("std");
const AccountId = @import("../core/id.zig").AccountId;
const TransactionRecord = @import("../query/transaction_record_query.zig").TransactionRecord;

// AccountRecords contains transaction records for an account
pub const AccountRecords = struct {
    account_id: AccountId,
    records: std.ArrayList(TransactionRecord),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, account_id: AccountId) AccountRecords {
        return AccountRecords{
            .account_id = account_id,
            .records = std.ArrayList(TransactionRecord).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *AccountRecords) void {
        for (self.records.items) |*record| {
            record.deinit();
        }
        self.records.deinit();
    }
    
    pub fn addRecord(self: *AccountRecords, record: TransactionRecord) !void {
        try self.records.append(record);
    }
};