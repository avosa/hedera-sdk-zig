const std = @import("std");
const ScheduleId = @import("../core/id.zig").ScheduleId;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;

// ScheduleCreateResponse contains the response from creating a schedule
pub const ScheduleCreateResponse = struct {
    schedule_id: ScheduleId,
    transaction_id: TransactionId,
    scheduled_transaction_id: TransactionId,
    
    pub fn init(schedule_id: ScheduleId, transaction_id: TransactionId, scheduled_transaction_id: TransactionId) ScheduleCreateResponse {
        return ScheduleCreateResponse{
            .schedule_id = schedule_id,
            .transaction_id = transaction_id,
            .scheduled_transaction_id = scheduled_transaction_id,
        };
    }
};