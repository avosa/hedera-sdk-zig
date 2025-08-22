const std = @import("std");
const encoding = @import("encoding.zig");
const ProtoWriter = encoding.ProtoWriter;
const ProtoReader = encoding.ProtoReader;
const AccountId = @import("../core/id.zig").AccountId;
const ContractId = @import("../core/id.zig").ContractId;
const FileId = @import("../core/id.zig").FileId;
const TokenId = @import("../core/id.zig").TokenId;
const TopicId = @import("../core/id.zig").TopicId;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;
const Timestamp = @import("../core/transaction_id.zig").Timestamp;
const Duration = @import("../core/transaction_id.zig").Duration;
const Key = @import("../crypto/key.zig").Key;

// Protobuf message for AccountID
pub const AccountIDProto = struct {
    shard: i64 = 0,
    realm: i64 = 0,
    account: union(enum) {
        account_num: i64,
        alias: []const u8,
    },
    
    pub fn encode(self: AccountIDProto, writer: *ProtoWriter) !void {
        try writer.writeInt64(1, self.shard);
        try writer.writeInt64(2, self.realm);
        
        switch (self.account) {
            .account_num => |num| try writer.writeInt64(3, num),
            .alias => |alias| try writer.writeString(4, alias),
        }
    }
    
    pub fn decode(reader: *ProtoReader) !AccountIDProto {
        var result = AccountIDProto{
            .shard = 0,
            .realm = 0,
            .account = .{ .account_num = 0 },
        };
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => result.shard = try reader.readInt64(),
                2 => result.realm = try reader.readInt64(),
                3 => result.account = .{ .account_num = try reader.readInt64() },
                4 => result.account = .{ .alias = try reader.readString() },
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return result;
    }
    
    pub fn fromAccountId(id: AccountId) AccountIDProto {
        return AccountIDProto{
            .shard = @as(i64, @intCast(id.entity.shard)),
            .realm = @as(i64, @intCast(id.entity.realm)),
            .account = if (id.alias_key) |alias|
                .{ .alias = alias }
            else
                .{ .account_num = @as(i64, @intCast(id.entity.num)) },
        };
    }
    
    pub fn toAccountId(self: AccountIDProto) AccountId {
        return AccountId{
            .entity = .{
                .shard = @as(u64, @intCast(self.shard)),
                .realm = @as(u64, @intCast(self.realm)),
                .num = switch (self.account) {
                    .account_num => |num| @as(u64, @intCast(num)),
                    .alias => 0,
                },
            },
            .alias_key = switch (self.account) {
                .alias => |alias| alias,
                .account_num => null,
            },
        };
    }
};

// Protobuf message for ContractID
pub const ContractIDProto = struct {
    shard: i64 = 0,
    realm: i64 = 0,
    contract: union(enum) {
        contract_num: i64,
        evm_address: []const u8,
    },
    
    pub fn encode(self: ContractIDProto, writer: *ProtoWriter) !void {
        try writer.writeInt64(1, self.shard);
        try writer.writeInt64(2, self.realm);
        
        switch (self.contract) {
            .contract_num => |num| try writer.writeInt64(3, num),
            .evm_address => |addr| try writer.writeString(4, addr),
        }
    }
    
    pub fn decode(reader: *ProtoReader) !ContractIDProto {
        var result = ContractIDProto{
            .shard = 0,
            .realm = 0,
            .contract = .{ .contract_num = 0 },
        };
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => result.shard = try reader.readInt64(),
                2 => result.realm = try reader.readInt64(),
                3 => result.contract = .{ .contract_num = try reader.readInt64() },
                4 => result.contract = .{ .evm_address = try reader.readString() },
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return result;
    }
};

// Protobuf message for FileID
pub const FileIDProto = struct {
    shard: i64 = 0,
    realm: i64 = 0,
    file_num: i64 = 0,
    
    pub fn encode(self: FileIDProto, writer: *ProtoWriter) !void {
        try writer.writeInt64(1, self.shard);
        try writer.writeInt64(2, self.realm);
        try writer.writeInt64(3, self.file_num);
    }
    
    pub fn decode(reader: *ProtoReader) !FileIDProto {
        var result = FileIDProto{};
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => result.shard = try reader.readInt64(),
                2 => result.realm = try reader.readInt64(),
                3 => result.file_num = try reader.readInt64(),
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return result;
    }
};

// Protobuf message for TokenID
pub const TokenIDProto = struct {
    shard: i64 = 0,
    realm: i64 = 0,
    token_num: i64 = 0,
    
    pub fn encode(self: TokenIDProto, writer: *ProtoWriter) !void {
        try writer.writeInt64(1, self.shard);
        try writer.writeInt64(2, self.realm);
        try writer.writeInt64(3, self.token_num);
    }
    
    pub fn decode(reader: *ProtoReader) !TokenIDProto {
        var result = TokenIDProto{};
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => result.shard = try reader.readInt64(),
                2 => result.realm = try reader.readInt64(),
                3 => result.token_num = try reader.readInt64(),
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return result;
    }
};

// Protobuf message for TopicID
pub const TopicIDProto = struct {
    shard: i64 = 0,
    realm: i64 = 0,
    topic_num: i64 = 0,
    
    pub fn encode(self: TopicIDProto, writer: *ProtoWriter) !void {
        try writer.writeInt64(1, self.shard);
        try writer.writeInt64(2, self.realm);
        try writer.writeInt64(3, self.topic_num);
    }
    
    pub fn decode(reader: *ProtoReader) !TopicIDProto {
        var result = TopicIDProto{};
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => result.shard = try reader.readInt64(),
                2 => result.realm = try reader.readInt64(),
                3 => result.topic_num = try reader.readInt64(),
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return result;
    }
};

// Protobuf message for Timestamp
pub const TimestampProto = struct {
    seconds: i64 = 0,
    nanos: i32 = 0,
    
    pub fn encode(self: TimestampProto, writer: *ProtoWriter) !void {
        try writer.writeInt64(1, self.seconds);
        try writer.writeInt32(2, self.nanos);
    }
    
    pub fn decode(reader: *ProtoReader) !TimestampProto {
        var result = TimestampProto{};
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => result.seconds = try reader.readInt64(),
                2 => result.nanos = try reader.readInt32(),
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return result;
    }
    
    pub fn fromTimestamp(ts: Timestamp) TimestampProto {
        return TimestampProto{
            .seconds = ts.seconds,
            .nanos = ts.nanos,
        };
    }
    
    pub fn toTimestamp(self: TimestampProto) Timestamp {
        return Timestamp{
            .seconds = self.seconds,
            .nanos = self.nanos,
        };
    }
};

// Protobuf message for Duration
pub const DurationProto = struct {
    seconds: i64 = 0,
    
    pub fn encode(self: DurationProto, writer: *ProtoWriter) !void {
        try writer.writeInt64(1, self.seconds);
    }
    
    pub fn decode(reader: *ProtoReader) !DurationProto {
        var result = DurationProto{};
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => result.seconds = try reader.readInt64(),
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return result;
    }
    
    pub fn fromDuration(d: Duration) DurationProto {
        return DurationProto{
            .seconds = d.seconds,
        };
    }
    
    pub fn toDuration(self: DurationProto) Duration {
        return Duration{
            .seconds = self.seconds,
        };
    }
};

// Protobuf message for TransactionID
pub const TransactionIDProto = struct {
    transaction_valid_start: ?TimestampProto = null,
    account_id: ?AccountIDProto = null,
    scheduled: bool = false,
    nonce: i32 = 0,
    
    pub fn encode(self: TransactionIDProto, writer: *ProtoWriter) !void {
        if (self.transaction_valid_start) |ts| {
            var ts_writer = ProtoWriter.init(writer.buffer.allocator);
            defer ts_writer.deinit();
            try ts.encode(&ts_writer);
            try writer.writeMessage(1, ts_writer.getWritten());
        }
        
        if (self.account_id) |acc| {
            var acc_writer = ProtoWriter.init(writer.buffer.allocator);
            defer acc_writer.deinit();
            try acc.encode(&acc_writer);
            try writer.writeMessage(2, acc_writer.getWritten());
        }
        
        try writer.writeBool(3, self.scheduled);
        try writer.writeInt32(4, self.nonce);
    }
    
    pub fn decode(reader: *ProtoReader) !TransactionIDProto {
        var result = TransactionIDProto{};
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => {
                    const msg_data = try reader.readMessage();
                    var msg_reader = ProtoReader.init(msg_data);
                    result.transaction_valid_start = try TimestampProto.decode(&msg_reader);
                },
                2 => {
                    const msg_data = try reader.readMessage();
                    var msg_reader = ProtoReader.init(msg_data);
                    result.account_id = try AccountIDProto.decode(&msg_reader);
                },
                3 => result.scheduled = try reader.readBool(),
                4 => result.nonce = try reader.readInt32(),
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return result;
    }
    
    pub fn fromTransactionId(id: TransactionId) TransactionIDProto {
        return TransactionIDProto{
            .transaction_valid_start = TimestampProto.fromTimestamp(id.valid_start),
            .account_id = AccountIDProto.fromAccountId(id.account_id),
            .scheduled = id.scheduled,
            .nonce = if (id.nonce) |n| @as(i32, @intCast(n)) else 0,
        };
    }
    
    pub fn toTransactionId(self: TransactionIDProto) TransactionId {
        return TransactionId{
            .account_id = if (self.account_id) |acc| acc.toAccountId() else AccountId.init(0, 0, 0),
            .valid_start = if (self.transaction_valid_start) |ts| ts.toTimestamp() else Timestamp{ .seconds = 0, .nanos = 0 },
            .scheduled = self.scheduled,
            .nonce = if (self.nonce != 0) @as(u32, @intCast(self.nonce)) else null,
        };
    }
};

// Protobuf message for Key
pub const KeyProto = struct {
    key: union(enum) {
        contract_id: ContractIDProto,
        ed25519: []const u8,
        rsa_3072: []const u8,
        ecdsa_384: []const u8,
        threshold_key: ThresholdKeyProto,
        key_list: KeyListProto,
        ecdsa_secp256k1: []const u8,
        delegatable_contract_id: ContractIDProto,
    },
    
    pub fn encode(self: KeyProto, writer: *ProtoWriter) !void {
        switch (self.key) {
            .contract_id => |cid| {
                var cid_writer = ProtoWriter.init(writer.buffer.allocator);
                defer cid_writer.deinit();
                try cid.encode(&cid_writer);
                try writer.writeMessage(1, cid_writer.getWritten());
            },
            .ed25519 => |key| try writer.writeString(2, key),
            .rsa_3072 => |key| try writer.writeString(3, key),
            .ecdsa_384 => |key| try writer.writeString(4, key),
            .threshold_key => |tk| {
                var tk_writer = ProtoWriter.init(writer.buffer.allocator);
                defer tk_writer.deinit();
                try tk.encode(&tk_writer);
                try writer.writeMessage(5, tk_writer.getWritten());
            },
            .key_list => |kl| {
                var kl_writer = ProtoWriter.init(writer.buffer.allocator);
                defer kl_writer.deinit();
                try kl.encode(&kl_writer);
                try writer.writeMessage(6, kl_writer.getWritten());
            },
            .ecdsa_secp256k1 => |key| try writer.writeString(7, key),
            .delegatable_contract_id => |cid| {
                var cid_writer = ProtoWriter.init(writer.buffer.allocator);
                defer cid_writer.deinit();
                try cid.encode(&cid_writer);
                try writer.writeMessage(8, cid_writer.getWritten());
            },
        }
    }
    
    pub fn decode(reader: *ProtoReader) !KeyProto {
        var result: ?KeyProto = null;
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => {
                    const msg_data = try reader.readMessage();
                    var msg_reader = ProtoReader.init(msg_data);
                    result = KeyProto{ .key = .{ .contract_id = try ContractIDProto.decode(&msg_reader) } };
                },
                2 => result = KeyProto{ .key = .{ .ed25519 = try reader.readString() } },
                3 => result = KeyProto{ .key = .{ .rsa_3072 = try reader.readString() } },
                4 => result = KeyProto{ .key = .{ .ecdsa_384 = try reader.readString() } },
                5 => {
                    const msg_data = try reader.readMessage();
                    var msg_reader = ProtoReader.init(msg_data);
                    result = KeyProto{ .key = .{ .threshold_key = try ThresholdKeyProto.decode(&msg_reader) } };
                },
                6 => {
                    const msg_data = try reader.readMessage();
                    var msg_reader = ProtoReader.init(msg_data);
                    result = KeyProto{ .key = .{ .key_list = try KeyListProto.decode(&msg_reader) } };
                },
                7 => result = KeyProto{ .key = .{ .ecdsa_secp256k1 = try reader.readString() } },
                8 => {
                    const msg_data = try reader.readMessage();
                    var msg_reader = ProtoReader.init(msg_data);
                    result = KeyProto{ .key = .{ .delegatable_contract_id = try ContractIDProto.decode(&msg_reader) } };
                },
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return result orelse return error.MissingRequiredField;
    }
};

// Protobuf message for KeyList
pub const KeyListProto = struct {
    keys: []KeyProto,
    
    pub fn encode(self: KeyListProto, writer: *ProtoWriter) !void {
        for (self.keys) |key| {
            var key_writer = ProtoWriter.init(writer.buffer.allocator);
            defer key_writer.deinit();
            try key.encode(&key_writer);
            try writer.writeMessage(1, key_writer.getWritten());
        }
    }
    
    pub fn decode(reader: *ProtoReader) !KeyListProto {
        var keys = std.ArrayList(KeyProto).init(std.heap.page_allocator);
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => {
                    const msg_data = try reader.readMessage();
                    var msg_reader = ProtoReader.init(msg_data);
                    try keys.append(try KeyProto.decode(&msg_reader));
                },
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return KeyListProto{ .keys = try keys.toOwnedSlice() };
    }
};

// Protobuf message for ThresholdKey
pub const ThresholdKeyProto = struct {
    threshold: u32 = 0,
    keys: ?KeyListProto = null,
    
    pub fn encode(self: ThresholdKeyProto, writer: *ProtoWriter) !void {
        try writer.writeUint32(1, self.threshold);
        
        if (self.keys) |kl| {
            var kl_writer = ProtoWriter.init(writer.buffer.allocator);
            defer kl_writer.deinit();
            try kl.encode(&kl_writer);
            try writer.writeMessage(2, kl_writer.getWritten());
        }
    }
    
    pub fn decode(reader: *ProtoReader) !ThresholdKeyProto {
        var result = ThresholdKeyProto{};
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => result.threshold = try reader.readUint32(),
                2 => {
                    const msg_data = try reader.readMessage();
                    var msg_reader = ProtoReader.init(msg_data);
                    result.keys = try KeyListProto.decode(&msg_reader);
                },
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return result;
    }
};