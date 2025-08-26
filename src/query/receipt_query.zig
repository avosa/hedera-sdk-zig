const std = @import("std");
const Status = @import("../core/status.zig").Status;
pub const TransactionReceipt = @import("../transaction/transaction_receipt.zig").TransactionReceipt;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;
const AccountId = @import("../core/id.zig").AccountId;
const ContractId = @import("../core/id.zig").ContractId;
const FileId = @import("../core/id.zig").FileId;
const TokenId = @import("../core/id.zig").TokenId;
const TopicId = @import("../core/id.zig").TopicId;
const ScheduleId = @import("../core/id.zig").ScheduleId;
const Query = @import("query.zig").Query;
const QueryResponse = @import("query.zig").QueryResponse;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;
const HederaError = @import("../core/errors.zig").HederaError;
const Hbar = @import("../core/hbar.zig").Hbar;

// ExchangeRate represents the exchange rate for HBAR to USD cents
pub const ExchangeRate = struct {
    hbars: i32,
    cents: i32,
    expiration_time: i64,
    
    pub fn decode(reader: *ProtoReader) !ExchangeRate {
        var rate = ExchangeRate{
            .hbars = 0,
            .cents = 0,
            .expiration_time = 0,
        };
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            switch (tag.field_number) {
                1 => rate.hbars = try reader.readInt32(),
                2 => rate.cents = try reader.readInt32(),
                3 => {
                    const timestamp_bytes = try reader.readMessage();
                    var timestamp_reader = ProtoReader.init(timestamp_bytes);
                    while (timestamp_reader.hasMore()) {
                        const t = try timestamp_reader.readTag();
                        switch (t.field_number) {
                            1 => rate.expiration_time = try timestamp_reader.readInt64(),
                            else => try timestamp_reader.skipField(t.wire_type),
                        }
                    }
                },
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return rate;
    }
};

// TransactionReceipt is imported from transaction/transaction_receipt.zig
// No redundant definition here

// TransactionReceiptQuery retrieves the receipt of a transaction
pub const TransactionReceiptQuery = struct {
    base: Query,
    transaction_id: ?TransactionId,
    include_children: bool,
    include_duplicates: bool,
    
    pub fn init(allocator: std.mem.Allocator) TransactionReceiptQuery {
        var query = TransactionReceiptQuery{
            .base = Query.init(allocator),
            .transaction_id = null,
            .include_children = false,
            .include_duplicates = false,
        };
        query.base.grpc_service_name = "proto.CryptoService";
        query.base.grpc_method_name = "getTransactionReceipts";
        query.base.is_payment_required = false;
        return query;
    }
    
    pub fn deinit(self: *TransactionReceiptQuery) void {
        self.base.deinit();
    }
    
    // Set the transaction ID
    pub fn setTransactionId(self: *TransactionReceiptQuery, transaction_id: TransactionId) !*TransactionReceiptQuery {
        self.transaction_id = transaction_id;
        return self;
    }
    
    // Set whether to include child receipts
    pub fn setIncludeChildren(self: *TransactionReceiptQuery, include: bool) !*TransactionReceiptQuery {
        self.include_children = include;
        return self;
    }
    
    // Set whether to include duplicate receipts
    pub fn setIncludeDuplicates(self: *TransactionReceiptQuery, include: bool) !*TransactionReceiptQuery {
        self.include_duplicates = include;
        return self;
    }
    
    // Execute the query
    pub fn execute(self: *TransactionReceiptQuery, client: *Client) !TransactionReceipt {
        if (self.transaction_id == null) {
            return error.TransactionIdRequired;
        }
        
        const response = try self.base.execute(client);
        return try self.parseResponse(response);
    }
    
    // Get cost of the query (always free for receipts)
    pub fn getCost(self: *TransactionReceiptQuery, client: *Client) !Hbar {
        _ = self;
        _ = client;
        return Hbar.zero();
    }
    
    // Build the query
    pub fn buildQuery(self: *TransactionReceiptQuery) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Query message structure
        // transactionGetReceipt = 4 (oneof query)
        var receipt_query_writer = ProtoWriter.init(self.base.allocator);
        defer receipt_query_writer.deinit();
        
        // transactionID = 2
        if (self.transaction_id) |tx_id| {
            var tx_id_writer = ProtoWriter.init(self.base.allocator);
            defer tx_id_writer.deinit();
            
            // transactionValidStart = 1
            var timestamp_writer = ProtoWriter.init(self.base.allocator);
            defer timestamp_writer.deinit();
            try timestamp_writer.writeInt64(1, tx_id.valid_start.seconds);
            try timestamp_writer.writeInt32(2, tx_id.valid_start.nanos);
            const timestamp_bytes = try timestamp_writer.toOwnedSlice();
            defer self.base.allocator.free(timestamp_bytes);
            try tx_id_writer.writeMessage(1, timestamp_bytes);
            
            // accountID = 2
            var account_writer = ProtoWriter.init(self.base.allocator);
            defer account_writer.deinit();
            try account_writer.writeInt64(1, @intCast(tx_id.account_id.shard));
            try account_writer.writeInt64(2, @intCast(tx_id.account_id.realm));
            try account_writer.writeInt64(3, @intCast(tx_id.account_id.account));
            const account_bytes = try account_writer.toOwnedSlice();
            defer self.base.allocator.free(account_bytes);
            try tx_id_writer.writeMessage(2, account_bytes);
            
            // nonce = 4
            if (tx_id.nonce) |n| {
                try tx_id_writer.writeInt32(4, @intCast(n));
            }
            
            const tx_id_bytes = try tx_id_writer.toOwnedSlice();
            defer self.base.allocator.free(tx_id_bytes);
            try receipt_query_writer.writeMessage(2, tx_id_bytes);
        }
        
        // includeDuplicates = 3
        if (self.include_duplicates) {
            try receipt_query_writer.writeBool(3, true);
        }
        
        // includeChildReceipts = 4
        if (self.include_children) {
            try receipt_query_writer.writeBool(4, true);
        }
        
        const receipt_query_bytes = try receipt_query_writer.toOwnedSlice();
        defer self.base.allocator.free(receipt_query_bytes);
        try writer.writeMessage(4, receipt_query_bytes);
        
        return writer.toOwnedSlice();
    }
    
    // Parse the response
    fn parseResponse(self: *TransactionReceiptQuery, response: QueryResponse) !TransactionReceipt {
        var reader = ProtoReader.init(response.response_bytes);
        var receipt = TransactionReceipt.init(self.base.allocator, Status.OK);
        var serial_numbers = std.ArrayList(i64).init(self.base.allocator);
        defer serial_numbers.deinit();
        
        // Parse TransactionGetReceiptResponse
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => {
                    // header (ignored for receipts)
                    _ = try reader.readMessage();
                },
                2 => {
                    // receipt
                    const receipt_bytes = try reader.readMessage();
                    var receipt_reader = ProtoReader.init(receipt_bytes);
                    
                    while (receipt_reader.hasMore()) {
                        const r_tag = try receipt_reader.readTag();
                        
                        switch (r_tag.field_number) {
                            1 => {
                                // status
                                const status_code = try receipt_reader.readInt32();
                                receipt.status = try Status.fromInt(status_code);
                            },
                            2 => {
                                // accountID
                                const account_bytes = try receipt_reader.readMessage();
                                var account_reader = ProtoReader.init(account_bytes);
                                
                                var shard: i64 = 0;
                                var realm: i64 = 0;
                                var num: i64 = 0;
                                
                                while (account_reader.hasMore()) {
                                    const a = try account_reader.readTag();
                                    switch (a.field_number) {
                                        1 => shard = try account_reader.readInt64(),
                                        2 => realm = try account_reader.readInt64(),
                                        3 => num = try account_reader.readInt64(),
                                        else => try account_reader.skipField(a.wire_type),
                                    }
                                }
                                
                                receipt.account_id = AccountId.init(@intCast(shard), @intCast(realm), @intCast(num));
                            },
                            3 => {
                                // fileID
                                const file_bytes = try receipt_reader.readMessage();
                                var file_reader = ProtoReader.init(file_bytes);
                                
                                var shard: i64 = 0;
                                var realm: i64 = 0;
                                var num: i64 = 0;
                                
                                while (file_reader.hasMore()) {
                                    const f = try file_reader.readTag();
                                    switch (f.field_number) {
                                        1 => shard = try file_reader.readInt64(),
                                        2 => realm = try file_reader.readInt64(),
                                        3 => num = try file_reader.readInt64(),
                                        else => try file_reader.skipField(f.wire_type),
                                    }
                                }
                                
                                receipt.file_id = FileId.init(@intCast(shard), @intCast(realm), @intCast(num));
                            },
                            4 => {
                                // contractID
                                const contract_bytes = try receipt_reader.readMessage();
                                var contract_reader = ProtoReader.init(contract_bytes);
                                
                                var shard: i64 = 0;
                                var realm: i64 = 0;
                                var num: i64 = 0;
                                
                                while (contract_reader.hasMore()) {
                                    const c = try contract_reader.readTag();
                                    switch (c.field_number) {
                                        1 => shard = try contract_reader.readInt64(),
                                        2 => realm = try contract_reader.readInt64(),
                                        3 => num = try contract_reader.readInt64(),
                                        else => try contract_reader.skipField(c.wire_type),
                                    }
                                }
                                
                                receipt.contract_id = ContractId.init(@intCast(shard), @intCast(realm), @intCast(num));
                            },
                            5 => {
                                // exchangeRate
                                const rate_bytes = try receipt_reader.readMessage();
                                var rate_reader = ProtoReader.init(rate_bytes);
                                
                                // currentRate = 1
                                while (rate_reader.hasMore()) {
                                    const rate_tag = try rate_reader.readTag();
                                    switch (rate_tag.field_number) {
                                        1 => {
                                            const current_bytes = try rate_reader.readMessage();
                                            var current_reader = ProtoReader.init(current_bytes);
                                            const local_rate = try ExchangeRate.decode(&current_reader);
                                            receipt.exchange_rate = @import("../core/exchange_rate.zig").ExchangeRate{
                                                .cent_equivalent = local_rate.cents,
                                                .hbar_equivalent = local_rate.hbars,
                                                .expiration_time = null,
                                            };
                                        },
                                        else => try rate_reader.skipField(rate_tag.wire_type),
                                    }
                                }
                            },
                            6 => {
                                // topicID
                                const topic_bytes = try receipt_reader.readMessage();
                                var topic_reader = ProtoReader.init(topic_bytes);
                                
                                var shard: i64 = 0;
                                var realm: i64 = 0;
                                var num: i64 = 0;
                                
                                while (topic_reader.hasMore()) {
                                    const t = try topic_reader.readTag();
                                    switch (t.field_number) {
                                        1 => shard = try topic_reader.readInt64(),
                                        2 => realm = try topic_reader.readInt64(),
                                        3 => num = try topic_reader.readInt64(),
                                        else => try topic_reader.skipField(t.wire_type),
                                    }
                                }
                                
                                receipt.topic_id = TopicId.init(@intCast(shard), @intCast(realm), @intCast(num));
                            },
                            7 => receipt.topic_sequence_number = try receipt_reader.readUint64(),
                            8 => receipt.topic_running_hash = try self.base.allocator.dupe(u8, try receipt_reader.readBytes()),
                            9 => receipt.topic_running_hash_version = try receipt_reader.readUint64(),
                            10 => {
                                // tokenID
                                const token_bytes = try receipt_reader.readMessage();
                                var token_reader = ProtoReader.init(token_bytes);
                                
                                var shard: i64 = 0;
                                var realm: i64 = 0;
                                var num: i64 = 0;
                                
                                while (token_reader.hasMore()) {
                                    const t = try token_reader.readTag();
                                    switch (t.field_number) {
                                        1 => shard = try token_reader.readInt64(),
                                        2 => realm = try token_reader.readInt64(),
                                        3 => num = try token_reader.readInt64(),
                                        else => try token_reader.skipField(t.wire_type),
                                    }
                                }
                                
                                receipt.token_id = TokenId.init(@intCast(shard), @intCast(realm), @intCast(num));
                            },
                            11 => receipt.total_supply = try receipt_reader.readUint64(),
                            12 => {
                                // scheduleID
                                const schedule_bytes = try receipt_reader.readMessage();
                                var schedule_reader = ProtoReader.init(schedule_bytes);
                                
                                var shard: i64 = 0;
                                var realm: i64 = 0;
                                var num: i64 = 0;
                                
                                while (schedule_reader.hasMore()) {
                                    const s = try schedule_reader.readTag();
                                    switch (s.field_number) {
                                        1 => shard = try schedule_reader.readInt64(),
                                        2 => realm = try schedule_reader.readInt64(),
                                        3 => num = try schedule_reader.readInt64(),
                                        else => try schedule_reader.skipField(s.wire_type),
                                    }
                                }
                                
                                receipt.schedule_id = ScheduleId.init(@intCast(shard), @intCast(realm), @intCast(num));
                            },
                            14 => try serial_numbers.append(try receipt_reader.readInt64()),
                            15 => receipt.node_id = try receipt_reader.readUint64(),
                            else => try receipt_reader.skipField(r_tag.wire_type),
                        }
                    }
                },
                3 => {
                    // duplicateTransactionReceipts (repeated)
                    _ = try reader.readMessage();
                },
                4 => {
                    // childTransactionReceipts (repeated)
                    _ = try reader.readMessage();
                },
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        // Convert ArrayLists to slices
        if (serial_numbers.items.len > 0) {
            receipt.serial_numbers = try self.base.allocator.dupe(i64, serial_numbers.items);
        }
        
        return receipt;
    }
};