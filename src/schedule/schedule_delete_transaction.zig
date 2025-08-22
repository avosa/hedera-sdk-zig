const std = @import("std");
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const ScheduleId = @import("../core/id.zig").ScheduleId;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;

// ScheduleDeleteTransaction deletes a schedule from the network's action queue
pub const ScheduleDeleteTransaction = struct {
    base: Transaction,
    schedule_id: ?ScheduleId = null,
    
    pub fn init(allocator: std.mem.Allocator) ScheduleDeleteTransaction {
        return ScheduleDeleteTransaction{
            .base = Transaction.init(allocator),
        };
    }
    
    pub fn deinit(self: *ScheduleDeleteTransaction) void {
        self.base.deinit();
    }
    
    // Set the schedule ID to delete
    pub fn setScheduleId(self: *ScheduleDeleteTransaction, schedule_id: ScheduleId) !void {
        if (self.base.frozen) return error.TransactionIsFrozen;
        self.schedule_id = schedule_id;
    }
    
    // Execute the transaction
    pub fn execute(self: *ScheduleDeleteTransaction, client: *Client) !TransactionResponse {
        return try self.base.execute(client);
    }
    
    // Build transaction body
    pub fn buildTransactionBody(self: *ScheduleDeleteTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Write common transaction fields
        try self.base.writeCommonFields(&writer);
        
        // scheduleDelete = 43 (oneof data)
        var schedule_writer = ProtoWriter.init(self.base.allocator);
        defer schedule_writer.deinit();
        
        // scheduleID = 1
        if (self.schedule_id) |schedule_id| {
            var id_writer = ProtoWriter.init(self.base.allocator);
            defer id_writer.deinit();
            try id_writer.writeInt64(1, @intCast(schedule_id.entity.shard));
            try id_writer.writeInt64(2, @intCast(schedule_id.entity.realm));
            try id_writer.writeInt64(3, @intCast(schedule_id.entity.num));
            const id_bytes = try id_writer.toOwnedSlice();
            defer self.base.allocator.free(id_bytes);
            try schedule_writer.writeMessage(1, id_bytes);
        }
        
        const schedule_bytes = try schedule_writer.toOwnedSlice();
        defer self.base.allocator.free(schedule_bytes);
        try writer.writeMessage(43, schedule_bytes);
        
        return writer.toOwnedSlice();
    }
};