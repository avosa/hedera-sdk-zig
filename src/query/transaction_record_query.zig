const std = @import("std");
const TransactionId = @import("../core/transaction_id.zig").TransactionId;
const AccountId = @import("../core/id.zig").AccountId;
const Timestamp = @import("../core/timestamp.zig").Timestamp;
const Query = @import("../query/query.zig").Query;
const QueryResponse = @import("../query/query.zig").QueryResponse;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;
const Hbar = @import("../core/hbar.zig").Hbar;
const Transfer = @import("../transfer/transfer_transaction.zig").Transfer;
const NftTransfer = @import("../transfer/transfer_transaction.zig").NftTransfer;
const TokenTransfer = @import("../transaction/transaction_record.zig").TokenTransfer;
const TransactionReceipt = @import("receipt_query.zig").TransactionReceipt;

// Use the consolidated TransactionRecord from transaction module
pub const TransactionRecord = @import("../transaction/transaction_record.zig").TransactionRecord;
pub const ContractFunctionResult = @import("../contract/contract_execute.zig").ContractFunctionResult;

// TransactionRecordQuery retrieves a transaction record
pub const TransactionRecordQuery = struct {
    base: Query,
    transaction_id: ?TransactionId,
    include_children: bool,
    include_duplicates: bool,

    pub fn init(allocator: std.mem.Allocator) TransactionRecordQuery {
        return TransactionRecordQuery{
            .base = Query.init(allocator),
            .transaction_id = null,
            .include_children = false,
            .include_duplicates = false,
        };
    }

    pub fn deinit(self: *TransactionRecordQuery) void {
        self.base.deinit();
    }

    // Set the transaction ID to query
    pub fn setTransactionId(self: *TransactionRecordQuery, id: TransactionId) !*TransactionRecordQuery {
        self.transaction_id = id;
        return self;
    }

    // Include child transaction records
    pub fn setIncludeChildren(self: *TransactionRecordQuery, include: bool) !*TransactionRecordQuery {
        self.include_children = include;
        return self;
    }

    // Alias for setIncludeChildren to match TransactionResponse usage
    pub fn setIncludeChildRecords(self: *TransactionRecordQuery, include: bool) !*TransactionRecordQuery {
        return self.setIncludeChildren(include);
    }

    // Include duplicate transaction records
    pub fn setIncludeDuplicates(self: *TransactionRecordQuery, include: bool) !*TransactionRecordQuery {
        self.include_duplicates = include;
        return self;
    }

    // Execute the query
    pub fn execute(self: *TransactionRecordQuery, client: *Client) !TransactionRecord {
        if (self.transaction_id == null) {
            return error.TransactionIdRequired;
        }

        const response = try self.base.execute(client);
        return try self.parseResponse(response);
    }

    // Get cost of the query
    pub fn getCost(self: *TransactionRecordQuery, client: *Client) !Hbar {
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
    fn buildQuery(self: *TransactionRecordQuery) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();

        // Query header
        var header_writer = ProtoWriter.init(self.base.allocator);
        defer header_writer.deinit();

        if (self.base.payment_transaction) |payment| {
            try header_writer.writeMessage(1, payment);
        }

        try header_writer.writeInt32(2, @intFromEnum(self.base.response_type));

        const header_bytes = try header_writer.toOwnedSlice();
        defer self.base.allocator.free(header_bytes);
        try writer.writeMessage(1, header_bytes);

        // TransactionGetRecord query
        var record_query_writer = ProtoWriter.init(self.base.allocator);
        defer record_query_writer.deinit();

        if (self.transaction_id) |tx_id| {
            var tx_id_writer = ProtoWriter.init(self.base.allocator);
            defer tx_id_writer.deinit();

            // Write account ID
            var account_writer = ProtoWriter.init(self.base.allocator);
            defer account_writer.deinit();
            try account_writer.writeInt64(1, @intCast(tx_id.account_id.shard));
            try account_writer.writeInt64(2, @intCast(tx_id.account_id.realm));
            try account_writer.writeInt64(3, @intCast(tx_id.account_id.account));

            const account_bytes = try account_writer.toOwnedSlice();
            defer self.base.allocator.free(account_bytes);
            try tx_id_writer.writeMessage(1, account_bytes);

            // Write valid start timestamp
            var timestamp_writer = ProtoWriter.init(self.base.allocator);
            defer timestamp_writer.deinit();
            try timestamp_writer.writeInt64(1, tx_id.valid_start.seconds);
            try timestamp_writer.writeInt32(2, tx_id.valid_start.nanos);

            const timestamp_bytes = try timestamp_writer.toOwnedSlice();
            defer self.base.allocator.free(timestamp_bytes);
            try tx_id_writer.writeMessage(2, timestamp_bytes);

            if (tx_id.scheduled) {
                try tx_id_writer.writeBool(3, true);
            }

            if (tx_id.nonce) |nonce| {
                try tx_id_writer.writeInt32(4, @intCast(nonce));
            }

            const tx_id_bytes = try tx_id_writer.toOwnedSlice();
            defer self.base.allocator.free(tx_id_bytes);
            try record_query_writer.writeMessage(1, tx_id_bytes);
        }

        if (self.include_children) {
            try record_query_writer.writeBool(2, true);
        }

        if (self.include_duplicates) {
            try record_query_writer.writeBool(3, true);
        }

        const record_query_bytes = try record_query_writer.toOwnedSlice();
        defer self.base.allocator.free(record_query_bytes);
        try writer.writeMessage(11, record_query_bytes); // transactionGetRecord field

        return writer.toOwnedSlice();
    }

    // Parse the response
    fn parseResponse(self: *TransactionRecordQuery, response: QueryResponse) !TransactionRecord {
        try response.validateStatus();

        var reader = ProtoReader.init(response.response_bytes);
        const receipt = TransactionReceipt.init(self.base.allocator, .OK);
        const tx_id = self.transaction_id orelse TransactionId.generate(AccountId.init(0, 0, 0));
        var record = TransactionRecord.init(self.base.allocator, receipt, tx_id);

        while (reader.hasMore()) {
            const tag = try reader.readTag();

            switch (tag.field_number) {
                1 => {
                    // Transaction receipt
                    const receipt_bytes = try reader.readBytes();
                    record.receipt = try TransactionReceipt.fromProtobuf(self.base.allocator, receipt_bytes);
                },
                2 => {
                    // Transaction hash
                    record.transaction_hash = try reader.readBytes();
                },
                3 => {
                    // Consensus timestamp
                    const timestamp_bytes = try reader.readBytes();
                    var timestamp_reader = ProtoReader.init(timestamp_bytes);
                    while (timestamp_reader.hasMore()) {
                        const ts_tag = try timestamp_reader.readTag();
                        switch (ts_tag.field_number) {
                            1 => record.consensus_timestamp.seconds = try timestamp_reader.readInt64(),
                            2 => record.consensus_timestamp.nanos = try timestamp_reader.readInt32(),
                            else => try timestamp_reader.skipField(ts_tag.wire_type),
                        }
                    }
                },
                4 => {
                    // Transaction ID
                    const tx_id_bytes = try reader.readBytes();
                    record.transaction_id = try TransactionId.fromProtobuf(self.base.allocator, tx_id_bytes);
                },
                5 => {
                    // Memo
                    record.transaction_memo = try reader.readString();
                },
                6 => {
                    // Transaction fee
                    const fee = try reader.readUint64();
                    record.transaction_fee = try Hbar.fromTinybars(@intCast(fee));
                },
                7 => {
                    // Contract function result
                    const result_bytes = try reader.readBytes();
                    record.call_result = try ContractFunctionResult.fromProtobuf(self.base.allocator, result_bytes);
                },
                8 => {
                    // Transfer list
                    const transfer_bytes = try reader.readBytes();
                    var transfer_reader = ProtoReader.init(transfer_bytes);
                    while (transfer_reader.hasMore()) {
                        const transfer_tag = try transfer_reader.readTag();
                        switch (transfer_tag.field_number) {
                            1 => {
                                // Account amounts
                                const account_amount_bytes = try transfer_reader.readBytes();
                                const transfer = try Transfer.fromProtobuf(self.base.allocator, account_amount_bytes);
                                try record.transfers.append(transfer);
                            },
                            else => try transfer_reader.skipField(transfer_tag.wire_type),
                        }
                    }
                },
                9 => {
                    // Token transfer lists
                    const token_list_bytes = try reader.readBytes();
                    var list_reader = ProtoReader.init(token_list_bytes);

                    while (list_reader.hasMore()) {
                        const list_tag = try list_reader.readTag();
                        switch (list_tag.field_number) {
                            1 => {
                                // Token ID
                                _ = try list_reader.readBytes();
                            },
                            2 => {
                                // Transfers
                                const transfer_bytes = try list_reader.readBytes();
                                const token_transfer = try TokenTransfer.fromProtobuf(self.base.allocator, transfer_bytes);
                                try record.token_transfers.append(token_transfer);
                            },
                            else => try list_reader.skipField(list_tag.wire_type),
                        }
                    }
                },
                10 => {
                    // Schedule ref
                    const schedule_bytes = try reader.readBytes();
                    var schedule_reader = ProtoReader.init(schedule_bytes);
                    while (schedule_reader.hasMore()) {
                        const schedule_tag = try schedule_reader.readTag();
                        switch (schedule_tag.field_number) {
                            3 => {
                                // Schedule ID
                                const schedule_id_bytes = try schedule_reader.readBytes();
                                record.schedule_ref = try @import("../core/id.zig").ScheduleId.fromProtobuf(self.base.allocator, schedule_id_bytes);
                            },
                            else => try schedule_reader.skipField(schedule_tag.wire_type),
                        }
                    }
                },
                11 => {
                    const fee_bytes = try reader.readBytes();
                    var fee_list = std.ArrayList(@import("../transaction/transaction_record.zig").AssessedCustomFee).init(self.base.allocator);
                    defer fee_list.deinit();
                    
                    var fee_reader = ProtoReader.init(fee_bytes);
                    var fee = @import("../transaction/transaction_record.zig").AssessedCustomFee{
                        .amount = 0,
                        .token_id = null,
                        .fee_collector_account_id = AccountId.init(0, 0, 0),
                        .payer_account_ids = &[_]AccountId{},
                    };
                    
                    while (fee_reader.hasMore()) {
                        const fee_tag = try fee_reader.readTag();
                        switch (fee_tag.field_number) {
                            1 => fee.amount = try fee_reader.readInt64(),
                            2 => {
                                const token_bytes = try fee_reader.readBytes();
                                fee.token_id = try @import("../core/id.zig").TokenId.fromProtobuf(self.base.allocator, token_bytes);
                            },
                            3 => {
                                const collector_bytes = try fee_reader.readBytes();
                                fee.fee_collector_account_id = try AccountId.fromProtobuf(self.base.allocator, collector_bytes);
                            },
                            4 => {
                                const payer_bytes = try fee_reader.readBytes();
                                var payers = std.ArrayList(AccountId).init(self.base.allocator);
                                const payer = try AccountId.fromProtobuf(self.base.allocator, payer_bytes);
                                try payers.append(payer);
                                fee.payer_account_ids = try payers.toOwnedSlice();
                            },
                            else => try fee_reader.skipField(fee_tag.wire_type),
                        }
                    }
                    
                    try fee_list.append(fee);
                    record.assessed_custom_fees = try fee_list.toOwnedSlice();
                },
                12 => {
                    const nft_transfer_bytes = try reader.readBytes();
                    var nft_list_reader = ProtoReader.init(nft_transfer_bytes);
                    
                    while (nft_list_reader.hasMore()) {
                        const nft_tag = try nft_list_reader.readTag();
                        switch (nft_tag.field_number) {
                            1 => {
                                _ = try nft_list_reader.readBytes();
                            },
                            2 => {
                                const transfer_bytes = try nft_list_reader.readBytes();
                                const nft_transfer = try NftTransfer.fromProtobuf(self.base.allocator, transfer_bytes);
                                const token_nft = @import("../transaction/transaction_record.zig").TokenNftTransfer{
                                    .sender_account_id = nft_transfer.sender_account_id,
                                    .receiver_account_id = nft_transfer.receiver_account_id,
                                    .serial_number = @intCast(nft_transfer.nft_id.serial_number),
                                    .is_approval = nft_transfer.is_approved,
                                };
                                try record.nft_transfers.append(token_nft);
                            },
                            else => try nft_list_reader.skipField(nft_tag.wire_type),
                        }
                    }
                },
                13 => {
                    const assoc_bytes = try reader.readBytes();
                    var assoc_list = std.ArrayList(@import("../transaction/transaction_record.zig").TokenAssociation).init(self.base.allocator);
                    defer assoc_list.deinit();
                    
                    var assoc_reader = ProtoReader.init(assoc_bytes);
                    var assoc = @import("../transaction/transaction_record.zig").TokenAssociation{
                        .token_id = @import("../core/id.zig").TokenId.init(0, 0, 0),
                        .account_id = AccountId.init(0, 0, 0),
                    };
                    
                    while (assoc_reader.hasMore()) {
                        const assoc_tag = try assoc_reader.readTag();
                        switch (assoc_tag.field_number) {
                            1 => {
                                const token_bytes = try assoc_reader.readBytes();
                                assoc.token_id = try @import("../core/id.zig").TokenId.fromProtobuf(self.base.allocator, token_bytes);
                            },
                            2 => {
                                const account_bytes = try assoc_reader.readBytes();
                                assoc.account_id = try AccountId.fromProtobuf(self.base.allocator, account_bytes);
                            },
                            else => try assoc_reader.skipField(assoc_tag.wire_type),
                        }
                    }
                    
                    try assoc_list.append(assoc);
                    record.automatic_token_associations = try assoc_list.toOwnedSlice();
                },
                14 => {
                    // Parent consensus timestamp
                    const parent_timestamp_bytes = try reader.readBytes();
                    var parent_reader = ProtoReader.init(parent_timestamp_bytes);
                    var parent_timestamp = Timestamp{ .seconds = 0, .nanos = 0 };
                    while (parent_reader.hasMore()) {
                        const parent_tag = try parent_reader.readTag();
                        switch (parent_tag.field_number) {
                            1 => parent_timestamp.seconds = try parent_reader.readInt64(),
                            2 => parent_timestamp.nanos = try parent_reader.readInt32(),
                            else => try parent_reader.skipField(parent_tag.wire_type),
                        }
                    }
                    record.parent_consensus_timestamp = parent_timestamp;
                },
                15 => {
                    const alias_bytes = try reader.readBytes();
                    if (alias_bytes.len > 0) {
                        record.alias_key = try @import("../crypto/key.zig").PublicKey.fromProtobuf(self.base.allocator, alias_bytes);
                    }
                },
                16 => {
                    // Ethereum hash
                    record.ethereum_hash = try reader.readBytes();
                },
                17 => {
                    const staking_bytes = try reader.readBytes();
                    var staking_reader = ProtoReader.init(staking_bytes);
                    while (staking_reader.hasMore()) {
                        const staking_tag = try staking_reader.readTag();
                        switch (staking_tag.field_number) {
                            1 => {
                                const account_amount_bytes = try staking_reader.readBytes();
                                const transfer = try Transfer.fromProtobuf(self.base.allocator, account_amount_bytes);
                                try record.paid_staking_rewards.put(transfer.account_id, transfer.amount);
                            },
                            else => try staking_reader.skipField(staking_tag.wire_type),
                        }
                    }
                },
                18 => {
                    // Evm address
                    record.evm_address = try reader.readBytes();
                },
                19 => {
                    _ = try reader.readBytes();
                },
                20 => {
                    const child_bytes = try reader.readBytes();
                    var child_list = std.ArrayList(TransactionRecord).init(self.base.allocator);
                    defer child_list.deinit();
                    const child_record = try parseChildRecord(self.base.allocator, child_bytes);
                    try child_list.append(child_record);
                    record.children = try child_list.toOwnedSlice();
                },
                else => try reader.skipField(tag.wire_type),
            }
        }

        return record;
    }

    fn parseChildRecord(allocator: std.mem.Allocator, bytes: []const u8) !TransactionRecord {
        var reader = ProtoReader.init(bytes);
        const receipt = TransactionReceipt.init(allocator, @import("../core/status.zig").Status.OK);
        const tx_id = TransactionId.generate(AccountId.init(0, 0, 0));
        var record = TransactionRecord.init(allocator, receipt, tx_id);

        while (reader.hasMore()) {
            const tag = try reader.readTag();

            switch (tag.field_number) {
                1 => {
                    const receipt_bytes = try reader.readBytes();
                    record.receipt = try TransactionReceipt.fromProtobuf(allocator, receipt_bytes);
                },
                2 => {
                    record.transaction_hash = try reader.readBytes();
                },
                3 => {
                    const timestamp_bytes = try reader.readBytes();
                    var timestamp_reader = ProtoReader.init(timestamp_bytes);
                    while (timestamp_reader.hasMore()) {
                        const ts_tag = try timestamp_reader.readTag();
                        switch (ts_tag.field_number) {
                            1 => record.consensus_timestamp.seconds = try timestamp_reader.readInt64(),
                            2 => record.consensus_timestamp.nanos = try timestamp_reader.readInt32(),
                            else => try timestamp_reader.skipField(ts_tag.wire_type),
                        }
                    }
                },
                4 => {
                    const tx_id_bytes = try reader.readBytes();
                    record.transaction_id = try TransactionId.fromProtobuf(allocator, tx_id_bytes);
                },
                else => try reader.skipField(tag.wire_type),
            }
        }

        return record;
    }
};
