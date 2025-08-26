const std = @import("std");
const ScheduleId = @import("../core/id.zig").ScheduleId;
const AccountId = @import("../core/id.zig").AccountId;
const Key = @import("../crypto/key.zig").Key;
const Timestamp = @import("../core/timestamp.zig").Timestamp;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;
const Query = @import("../query/query.zig").Query;
const QueryResponse = @import("../query/query.zig").QueryResponse;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;
const Hbar = @import("../core/hbar.zig").Hbar;

// ScheduleInfo contains information about a scheduled transaction
pub const ScheduleInfo = struct {
    schedule_id: ScheduleId,
    creator_account_id: AccountId,
    payer_account_id: AccountId,
    scheduled_transaction_body: []const u8,
    scheduled_transaction: ?*@import("../transaction/transaction.zig").Transaction,
    ledger_id: []const u8,
    wait_for_expiry: bool,
    memo: []const u8,
    
    // Track if strings are owned by allocator
    owns_transaction_body: bool,
    owns_ledger_id: bool,
    owns_memo: bool,
    executed_at: ?Timestamp,
    deleted_at: ?Timestamp,
    expiration_time: Timestamp,
    signatories: std.ArrayList(Key),
    admin_key: ?Key,
    
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) ScheduleInfo {
        return ScheduleInfo{
            .schedule_id = ScheduleId.init(0, 0, 0),
            .creator_account_id = AccountId.init(0, 0, 0),
            .payer_account_id = AccountId.init(0, 0, 0),
            .scheduled_transaction_body = "",
            .scheduled_transaction = null,
            .ledger_id = "",
            .wait_for_expiry = false,
            .memo = "",
            .executed_at = null,
            .deleted_at = null,
            .expiration_time = Timestamp{ .seconds = 0, .nanos = 0 },
            .signatories = std.ArrayList(Key).init(allocator),
            .admin_key = null,
            .allocator = allocator,
            .owns_transaction_body = false,
            .owns_ledger_id = false,
            .owns_memo = false,
        };
    }
    
    pub fn deinit(self: *ScheduleInfo) void {
        if (self.owns_transaction_body) {
            self.allocator.free(self.scheduled_transaction_body);
        }
        if (self.owns_ledger_id) {
            self.allocator.free(self.ledger_id);
        }
        if (self.owns_memo) {
            self.allocator.free(self.memo);
        }
        self.signatories.deinit();
    }
};

// ScheduleInfoQuery retrieves information about a scheduled transaction
pub const ScheduleInfoQuery = struct {
    base: Query,
    schedule_id: ?ScheduleId,
    
    pub fn init(allocator: std.mem.Allocator) ScheduleInfoQuery {
        return ScheduleInfoQuery{
            .base = Query.init(allocator),
            .schedule_id = null,
        };
    }
    
    pub fn deinit(self: *ScheduleInfoQuery) void {
        self.base.deinit();
    }
    
    // Set the schedule ID to query
    pub fn setScheduleId(self: *ScheduleInfoQuery, schedule_id: ScheduleId) !*ScheduleInfoQuery {
        self.schedule_id = schedule_id;
        return self;
    }
    
    // Set the query payment amount
    pub fn setQueryPayment(self: *ScheduleInfoQuery, payment: Hbar) !*ScheduleInfoQuery {
        self.base.payment_amount = payment;
        return self;
    }
    
    // Execute the query
    pub fn execute(self: *ScheduleInfoQuery, client: *Client) !ScheduleInfo {
        if (self.schedule_id == null) {
            return error.ScheduleIdRequired;
        }
        
        const response = try self.base.execute(client);
        return try self.parseResponse(response);
    }
    
    // Get cost of the query
    pub fn getCost(self: *ScheduleInfoQuery, client: *Client) !Hbar {
        self.base.response_type = .CostAnswer;
        const response = try self.base.execute(client);
        
        var reader = ProtoReader.init(response.response_bytes);
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                2 => {
                    const cost = try reader.readUint64();
                    return try Hbar.fromTinybars(@intCast(cost));
                },
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return error.CostNotFound;
    }
    
    // Build the query
    pub fn buildQuery(self: *ScheduleInfoQuery) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Query message structure
        // header = 1
        var header_writer = ProtoWriter.init(self.base.allocator);
        defer header_writer.deinit();
        
        // payment = 1
        if (self.base.payment_transaction) |payment| {
            try header_writer.writeMessage(1, payment);
        }
        
        // responseType = 2
        try header_writer.writeInt32(2, @intFromEnum(self.base.response_type));
        
        const header_bytes = try header_writer.toOwnedSlice();
        defer self.base.allocator.free(header_bytes);
        try writer.writeMessage(1, header_bytes);
        
        // scheduleGetInfo = 17 (oneof query)
        var info_query_writer = ProtoWriter.init(self.base.allocator);
        defer info_query_writer.deinit();
        
        // scheduleID = 1
        if (self.schedule_id) |schedule| {
            var schedule_writer = ProtoWriter.init(self.base.allocator);
            defer schedule_writer.deinit();
            try schedule_writer.writeInt64(1, @intCast(schedule.shard));
            try schedule_writer.writeInt64(2, @intCast(schedule.realm));
            try schedule_writer.writeInt64(3, @intCast(schedule.num));
            const schedule_bytes = try schedule_writer.toOwnedSlice();
            defer self.base.allocator.free(schedule_bytes);
            try info_query_writer.writeMessage(1, schedule_bytes);
        }
        
        const info_query_bytes = try info_query_writer.toOwnedSlice();
        defer self.base.allocator.free(info_query_bytes);
        try writer.writeMessage(17, info_query_bytes);
        
        return writer.toOwnedSlice();
    }
    
    // Parse the response
    fn parseResponse(self: *ScheduleInfoQuery, response: QueryResponse) !ScheduleInfo {
        try response.validateStatus();
        
        var reader = ProtoReader.init(response.response_bytes);
        
        var info = ScheduleInfo{
            .schedule_id = ScheduleId.init(0, 0, 0),
            .creator_account_id = AccountId.init(0, 0, 0),
            .payer_account_id = AccountId.init(0, 0, 0),
            .scheduled_transaction_body = "",
            .ledger_id = "",
            .wait_for_expiry = false,
            .memo = "",
            .executed_at = null,
            .deleted_at = null,
            .expiration_time = Timestamp{ .seconds = 0, .nanos = 0 },
            .signatories = std.ArrayList(Key).init(self.base.allocator),
            .admin_key = null,
            .allocator = self.base.allocator,
        };
        
        // Parse ScheduleGetInfoResponse
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => {
                    // header
                    _ = try reader.readMessage();
                },
                2 => {
                    // scheduleInfo
                    const schedule_info_bytes = try reader.readMessage();
                    var schedule_reader = ProtoReader.init(schedule_info_bytes);
                    
                    while (schedule_reader.hasMore()) {
                        const s_tag = try schedule_reader.readTag();
                        
                        switch (s_tag.field_number) {
                            1 => {
                                // scheduleID
                                const schedule_bytes = try schedule_reader.readMessage();
                                var id_reader = ProtoReader.init(schedule_bytes);
                                
                                var shard: i64 = 0;
                                var realm: i64 = 0;
                                var num: i64 = 0;
                                
                                while (id_reader.hasMore()) {
                                    const i = try id_reader.readTag();
                                    switch (i.field_number) {
                                        1 => shard = try id_reader.readInt64(),
                                        2 => realm = try id_reader.readInt64(),
                                        3 => num = try id_reader.readInt64(),
                                        else => try id_reader.skipField(i.wire_type),
                                    }
                                }
                                
                                info.schedule_id = ScheduleId.init(@intCast(shard), @intCast(realm), @intCast(num));
                            },
                            2 => {
                                // creatorAccountID
                                const creator_bytes = try schedule_reader.readMessage();
                                var creator_reader = ProtoReader.init(creator_bytes);
                                
                                var shard: i64 = 0;
                                var realm: i64 = 0;
                                var num: i64 = 0;
                                
                                while (creator_reader.hasMore()) {
                                    const c = try creator_reader.readTag();
                                    switch (c.field_number) {
                                        1 => shard = try creator_reader.readInt64(),
                                        2 => realm = try creator_reader.readInt64(),
                                        3 => num = try creator_reader.readInt64(),
                                        else => try creator_reader.skipField(c.wire_type),
                                    }
                                }
                                
                                info.creator_account_id = AccountId.init(@intCast(shard), @intCast(realm), @intCast(num));
                            },
                            3 => {
                                // payerAccountID
                                const payer_bytes = try schedule_reader.readMessage();
                                var payer_reader = ProtoReader.init(payer_bytes);
                                
                                var shard: i64 = 0;
                                var realm: i64 = 0;
                                var num: i64 = 0;
                                
                                while (payer_reader.hasMore()) {
                                    const p = try payer_reader.readTag();
                                    switch (p.field_number) {
                                        1 => shard = try payer_reader.readInt64(),
                                        2 => realm = try payer_reader.readInt64(),
                                        3 => num = try payer_reader.readInt64(),
                                        else => try payer_reader.skipField(p.wire_type),
                                    }
                                }
                                
                                info.payer_account_id = AccountId.init(@intCast(shard), @intCast(realm), @intCast(num));
                            },
                            4 => {
                                // scheduledTransactionBody
                                const body_bytes = try schedule_reader.readBytes();
                                info.scheduled_transaction_body = try self.base.allocator.dupe(u8, body_bytes);
                            },
                            5 => {
                                // ledgerId
                                const ledger_bytes = try schedule_reader.readBytes();
                                info.ledger_id = try self.base.allocator.dupe(u8, ledger_bytes);
                            },
                            6 => info.wait_for_expiry = try schedule_reader.readBool(),
                            7 => info.memo = try self.base.allocator.dupe(u8, try schedule_reader.readString()),
                            8 => {
                                // executedAt
                                const executed_bytes = try schedule_reader.readMessage();
                                var executed_reader = ProtoReader.init(executed_bytes);
                                
                                var executed_time = Timestamp{ .seconds = 0, .nanos = 0 };
                                while (executed_reader.hasMore()) {
                                    const e = try executed_reader.readTag();
                                    switch (e.field_number) {
                                        1 => executed_time.seconds = try executed_reader.readInt64(),
                                        2 => executed_time.nanos = try executed_reader.readInt32(),
                                        else => try executed_reader.skipField(e.wire_type),
                                    }
                                }
                                info.executed_at = executed_time;
                            },
                            9 => {
                                // deletedAt
                                const deleted_bytes = try schedule_reader.readMessage();
                                var deleted_reader = ProtoReader.init(deleted_bytes);
                                
                                var deleted_time = Timestamp{ .seconds = 0, .nanos = 0 };
                                while (deleted_reader.hasMore()) {
                                    const d = try deleted_reader.readTag();
                                    switch (d.field_number) {
                                        1 => deleted_time.seconds = try deleted_reader.readInt64(),
                                        2 => deleted_time.nanos = try deleted_reader.readInt32(),
                                        else => try deleted_reader.skipField(d.wire_type),
                                    }
                                }
                                info.deleted_at = deleted_time;
                            },
                            10 => {
                                // expirationTime
                                const exp_bytes = try schedule_reader.readMessage();
                                var exp_reader = ProtoReader.init(exp_bytes);
                                
                                while (exp_reader.hasMore()) {
                                    const e = try exp_reader.readTag();
                                    switch (e.field_number) {
                                        1 => info.expiration_time.seconds = try exp_reader.readInt64(),
                                        2 => info.expiration_time.nanos = try exp_reader.readInt32(),
                                        else => try exp_reader.skipField(e.wire_type),
                                    }
                                }
                            },
                            11 => {
                                // signatories (repeated)
                                const sig_bytes = try schedule_reader.readMessage();
                                const signatory = try Key.fromProtobuf(sig_bytes, self.base.allocator);
                                try info.signatories.append(signatory);
                            },
                            12 => {
                                // adminKey
                                const key_bytes = try schedule_reader.readMessage();
                                info.admin_key = try Key.fromProtobuf(key_bytes, self.base.allocator);
                            },
                            else => try schedule_reader.skipField(s_tag.wire_type),
                        }
                    }
                },
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return info;
    }
};

// Factory function for creating a new ScheduleInfoQuery
