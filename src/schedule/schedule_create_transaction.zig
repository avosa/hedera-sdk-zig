const std = @import("std");
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const AccountId = @import("../core/id.zig").AccountId;
const ScheduleId = @import("../core/id.zig").ScheduleId;
const Key = @import("../crypto/key.zig").Key;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const Timestamp = @import("../core/timestamp.zig").Timestamp;

// ScheduleCreateTransaction creates a new schedule entity in the network's action queue
pub const ScheduleCreateTransaction = struct {
    base: Transaction,
    payer_account_id: ?AccountId = null,
    admin_key: ?Key = null,
    schedulable_transaction: ?*Transaction = null,
    scheduled_transaction: ?*Transaction = null,  // Alias for compatibility
    memo: ?[]const u8 = null,
    expiration_time: ?Timestamp = null,
    wait_for_expiry: bool = false,
    
    pub fn init(allocator: std.mem.Allocator) ScheduleCreateTransaction {
        return ScheduleCreateTransaction{
            .base = Transaction.init(allocator),
        };
    }
    
    pub fn deinit(self: *ScheduleCreateTransaction) void {
        self.base.deinit();
        if (self.memo) |memo| {
            self.base.allocator.free(memo);
        }
        if (self.schedulable_transaction) |tx| {
            tx.deinit();
            self.base.allocator.destroy(tx);
        }
    }
    
    // Set the payer account ID for the scheduled transaction
    pub fn setPayerAccountId(self: *ScheduleCreateTransaction, payer_account_id: AccountId) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.payer_account_id = payer_account_id;
    }
    
    // Set the admin key that can delete the schedule
    pub fn setAdminKey(self: *ScheduleCreateTransaction, key: Key) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.admin_key = key;
    }
    
    // Set the transaction to be scheduled
    pub fn setScheduledTransaction(self: *ScheduleCreateTransaction, transaction: *Transaction) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        
        if (self.schedulable_transaction) |old_tx| {
            old_tx.deinit();
            self.base.allocator.destroy(old_tx);
        }
        
        self.schedulable_transaction = transaction;
        self.scheduled_transaction = transaction;  // Update alias
    }
    
    // Set the memo for the schedule
    pub fn setMemo(self: *ScheduleCreateTransaction, memo: []const u8) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        if (memo.len > 100) return error.MemoTooLong;
        
        if (self.memo) |old_memo| {
            self.base.allocator.free(old_memo);
        }
        
        self.memo = try self.base.allocator.dupe(u8, memo);
    }
    
    // Set the schedule memo (alias for setMemo)
    pub fn setScheduleMemo(self: *ScheduleCreateTransaction, memo: []const u8) !void {
        return self.setMemo(memo);
    }
    
    // Set the expiration time for the schedule
    pub fn setExpirationTime(self: *ScheduleCreateTransaction, expiration_time: Timestamp) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.expiration_time = expiration_time;
    }
    
    // Set whether to wait for expiry before execution
    pub fn setWaitForExpiry(self: *ScheduleCreateTransaction, wait: bool) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.wait_for_expiry = wait;
    }
    
    // Execute the transaction
    pub fn execute(self: *ScheduleCreateTransaction, client: *Client) !TransactionResponse {
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *ScheduleCreateTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Write common transaction fields
        try self.base.writeCommonFields(&writer);
        
        // scheduleCreate = 42 (oneof data)
        var schedule_writer = ProtoWriter.init(self.base.allocator);
        defer schedule_writer.deinit();
        
        // scheduledTransactionBody = 1
        if (self.schedulable_transaction) |tx| {
            const tx_body = try tx.buildSchedulableBody();
            defer self.base.allocator.free(tx_body);
            try schedule_writer.writeMessage(1, tx_body);
        }
        
        // memo = 2
        if (self.memo) |memo| {
            try schedule_writer.writeString(2, memo);
        }
        
        // adminKey = 3
        if (self.admin_key) |key| {
            const key_bytes = try key.toProtobuf(self.base.allocator);
            defer self.base.allocator.free(key_bytes);
            try schedule_writer.writeMessage(3, key_bytes);
        }
        
        // payerAccountID = 4
        if (self.payer_account_id) |payer| {
            var payer_writer = ProtoWriter.init(self.base.allocator);
            defer payer_writer.deinit();
            try payer_writer.writeInt64(1, @intCast(payer.entity.shard));
            try payer_writer.writeInt64(2, @intCast(payer.entity.realm));
            try payer_writer.writeInt64(3, @intCast(payer.entity.num));
            const payer_bytes = try payer_writer.toOwnedSlice();
            defer self.base.allocator.free(payer_bytes);
            try schedule_writer.writeMessage(4, payer_bytes);
        }
        
        // expirationTime = 5
        if (self.expiration_time) |expiration| {
            var timestamp_writer = ProtoWriter.init(self.base.allocator);
            defer timestamp_writer.deinit();
            try timestamp_writer.writeInt64(1, expiration.seconds);
            try timestamp_writer.writeInt32(2, expiration.nanos);
            const timestamp_bytes = try timestamp_writer.toOwnedSlice();
            defer self.base.allocator.free(timestamp_bytes);
            try schedule_writer.writeMessage(5, timestamp_bytes);
        }
        
        // waitForExpiry = 13
        if (self.wait_for_expiry) {
            try schedule_writer.writeBool(13, self.wait_for_expiry);
        }
        
        const schedule_bytes = try schedule_writer.toOwnedSlice();
        defer self.base.allocator.free(schedule_bytes);
        try writer.writeMessage(42, schedule_bytes);
        
        return writer.toOwnedSlice();
    }
};