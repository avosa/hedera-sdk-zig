const std = @import("std");
const AccountId = @import("../core/id.zig").AccountId;
const TransactionRecord = @import("../query/transaction_record_query.zig").TransactionRecord;
const Query = @import("../query/query.zig").Query;
const QueryResponse = @import("../query/query.zig").QueryResponse;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;
const Hbar = @import("../core/hbar.zig").Hbar;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;

// AccountRecordsQuery retrieves all transaction records for an account
pub const AccountRecordsQuery = struct {
    base: Query,
    account_id: ?AccountId,
    
    pub fn init(allocator: std.mem.Allocator) AccountRecordsQuery {
        return AccountRecordsQuery{
            .base = Query.init(allocator),
            .account_id = null,
        };
    }
    
    pub fn deinit(self: *AccountRecordsQuery) void {
        self.base.deinit();
    }
    
    // Set the account ID to query records for
    pub fn setAccountId(self: *AccountRecordsQuery, account_id: AccountId) !*AccountRecordsQuery {
        self.account_id = account_id;
        return self;
    }
    
    // Set the query payment amount
    pub fn setQueryPayment(self: *AccountRecordsQuery, payment: Hbar) !*AccountRecordsQuery {
        self.base.payment_amount = payment;
        return self;
    }
    
    // Execute the query
    pub fn execute(self: *AccountRecordsQuery, client: *Client) ![]TransactionRecord {
        if (self.account_id == null) {
            return error.AccountIdRequired;
        }
        
        const response = try self.base.execute(client);
        return try self.parseResponse(response);
    }
    
    // Get cost of the query
    pub fn getCost(self: *AccountRecordsQuery, client: *Client) !Hbar {
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
    pub fn buildQuery(self: *AccountRecordsQuery) ![]u8 {
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
        
        // cryptoGetAccountRecords = 5 (oneof query)
        var records_query_writer = ProtoWriter.init(self.base.allocator);
        defer records_query_writer.deinit();
        
        // accountID = 1
        if (self.account_id) |account| {
            var account_writer = ProtoWriter.init(self.base.allocator);
            defer account_writer.deinit();
            try account_writer.writeInt64(1, @intCast(account.shard));
            try account_writer.writeInt64(2, @intCast(account.realm));
            try account_writer.writeInt64(3, @intCast(account.account));
            const account_bytes = try account_writer.toOwnedSlice();
            defer self.base.allocator.free(account_bytes);
            try records_query_writer.writeMessage(1, account_bytes);
        }
        
        const records_query_bytes = try records_query_writer.toOwnedSlice();
        defer self.base.allocator.free(records_query_bytes);
        try writer.writeMessage(5, records_query_bytes);
        
        return writer.toOwnedSlice();
    }
    
    // Parse the response
    fn parseResponse(self: *AccountRecordsQuery, response: QueryResponse) ![]TransactionRecord {
        try response.validateStatus();
        
        var reader = ProtoReader.init(response.response_bytes);
        var records = std.ArrayList(TransactionRecord).init(self.base.allocator);
        
        // Parse CryptoGetAccountRecordsResponse
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => {
                    // header
                    _ = try reader.readMessage();
                },
                2 => {
                    // accountID
                    _ = try reader.readMessage();
                },
                3 => {
                    // records (repeated)
                    const record_bytes = try reader.readMessage();
                    var record_reader = ProtoReader.init(record_bytes);
                    
                    var record = TransactionRecord{
                        .transaction_id = TransactionId.init(AccountId.init(0, 0, 0)),
                        .consensus_timestamp = undefined,
                        .transaction_hash = "",
                        .memo = "",
                        .transaction_fee = try Hbar.fromTinybars(0),
                        .transfers = std.ArrayList(@import("../transfer/transfer_transaction.zig").Transfer).init(self.base.allocator),
                        .token_transfers = std.ArrayList(@import("../transfer/transfer_transaction.zig").TokenTransfer).init(self.base.allocator),
                        .nft_transfers = std.ArrayList(@import("../transfer/transfer_transaction.zig").NftTransfer).init(self.base.allocator),
                        .receipt = undefined,
                        .allocator = self.base.allocator,
                    };
                    
                    // Parse the transaction record fields
                    while (record_reader.hasMore()) {
                        const r_tag = try record_reader.readTag();
                        
                        switch (r_tag.field_number) {
                            2 => {
                                // transactionID
                                const tx_id_bytes = try record_reader.readMessage();
                                record.transaction_id = try TransactionId.fromProtobuf(tx_id_bytes, self.base.allocator);
                            },
                            3 => {
                                // memo
                                record.memo = try self.base.allocator.dupe(u8, try record_reader.readString());
                            },
                            4 => {
                                // transactionFee
                                const fee = try record_reader.readUint64();
                                record.transaction_fee = try Hbar.fromTinybars(@intCast(fee));
                            },
                            5 => {
                                // consensusTimestamp
                                const timestamp_bytes = try record_reader.readMessage();
                                var timestamp_reader = ProtoReader.init(timestamp_bytes);
                                
                                while (timestamp_reader.hasMore()) {
                                    const t = try timestamp_reader.readTag();
                                    switch (t.field_number) {
                                        1 => record.consensus_timestamp.seconds = try timestamp_reader.readInt64(),
                                        2 => record.consensus_timestamp.nanos = try timestamp_reader.readInt32(),
                                        else => try timestamp_reader.skipField(t.wire_type),
                                    }
                                }
                            },
                            6 => {
                                // transactionHash
                                const hash_bytes = try record_reader.readBytes();
                                record.transaction_hash = try self.base.allocator.dupe(u8, hash_bytes);
                            },
                            10 => {
                                // transferList
                                const transfer_bytes = try record_reader.readMessage();
                                try @import("../transfer/transfer_transaction.zig").parseTransferList(transfer_bytes, &record.transfers, self.base.allocator);
                            },
                            11 => {
                                // tokenTransferLists (repeated)
                                const token_transfer_bytes = try record_reader.readMessage();
                                try @import("../transfer/transfer_transaction.zig").parseTokenTransferList(token_transfer_bytes, &record.token_transfers, &record.nft_transfers, self.base.allocator);
                            },
                            12 => {
                                // receipt
                                const receipt_bytes = try record_reader.readMessage();
                                record.receipt = try @import("../query/receipt_query.zig").TransactionReceipt.fromProtobuf(receipt_bytes, self.base.allocator);
                            },
                            else => try record_reader.skipField(r_tag.wire_type),
                        }
                    }
                    
                    try records.append(record);
                },
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return records.toOwnedSlice();
    }
};


