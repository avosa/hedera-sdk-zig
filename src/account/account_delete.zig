const std = @import("std");
const AccountId = @import("../core/id.zig").AccountId;
const Transaction = @import("../transaction/transaction.zig").Transaction;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const TransactionId = @import("../core/transaction_id.zig").TransactionId;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const errors = @import("../core/errors.zig");
const Duration = @import("../core/duration.zig").Duration;
const Hbar = @import("../core/hbar.zig").Hbar;

// AccountDeleteTransaction marks an account as deleted, moving all its current hbars to another account.
// It will remain in the ledger, marked as deleted, until it expires. Transfers into a deleted account fail.
// But a deleted account can still have its expiration extended in the normal way.
pub const AccountDeleteTransaction = struct {
    base: Transaction,
    delete_account_id: ?AccountId,
    transfer_account_id: ?AccountId,

    pub fn init(allocator: std.mem.Allocator) AccountDeleteTransaction {
        var tx = AccountDeleteTransaction{
            .base = Transaction.init(allocator),
            .delete_account_id = null,
            .transfer_account_id = null,
        };
        tx.base.buildTransactionBodyForNode = buildTransactionBodyForNode;
        return tx;
    }

    pub fn deinit(self: *AccountDeleteTransaction) void {
        self.base.deinit();
    }

    // SetAccountID sets the account to delete
    pub fn setAccountId(self: *AccountDeleteTransaction, account_id: AccountId) !*AccountDeleteTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        self.delete_account_id = account_id;
        return self;
    }

    // GetAccountID returns the account ID which will be deleted
    pub fn getAccountId(self: *const AccountDeleteTransaction) AccountId {
        if (self.delete_account_id) |id| {
            return id;
        }
        return AccountId{};
    }

    // SetTransferAccountID sets the account to transfer remaining balance to
    pub fn setTransferAccountId(self: *AccountDeleteTransaction, transfer_id: AccountId) !*AccountDeleteTransaction {
        if (self.base.frozen) return error.TransactionFrozen;
        self.transfer_account_id = transfer_id;
        return self;
    }

    // GetTransferAccountID returns the account ID which will receive all remaining hbars
    pub fn getTransferAccountID(self: *const AccountDeleteTransaction) AccountId {
        if (self.transfer_account_id) |id| {
            return id;
        }
        return AccountId{};
    }

    pub fn setTransactionId(self: *AccountDeleteTransaction, transaction_id: TransactionId) !*AccountDeleteTransaction {
        _ = try self.base.setTransactionId(transaction_id);
        return self;
    }
    
    pub fn setTransactionMemo(self: *AccountDeleteTransaction, memo: []const u8) !*AccountDeleteTransaction {
        _ = try self.base.setTransactionMemo(memo);
        return self;
    }
    
    pub fn setMaxTransactionFee(self: *AccountDeleteTransaction, fee: Hbar) !*AccountDeleteTransaction {
        _ = try self.base.setMaxTransactionFee(fee);
        return self;
    }
    
    pub fn setTransactionValidDuration(self: *AccountDeleteTransaction, duration: Duration) !*AccountDeleteTransaction {
        _ = try self.base.setTransactionValidDuration(duration);
        return self;
    }
    
    pub fn setNodeAccountIds(self: *AccountDeleteTransaction, nodes: []const AccountId) !*AccountDeleteTransaction {
        _ = try self.base.setNodeAccountIds(nodes);
        return self;
    }
    
    pub fn setGrpcDeadline(self: *AccountDeleteTransaction, deadline: Duration) !*AccountDeleteTransaction {
        _ = try self.base.setGrpcDeadline(deadline);
        return self;
    }
    
    pub fn setRegenerateTransactionId(self: *AccountDeleteTransaction, regenerate: bool) !*AccountDeleteTransaction {
        _ = try self.base.setRegenerateTransactionId(regenerate);
        return self;
    }
    
    // Execute the transaction
    pub fn freezeWith(self: *AccountDeleteTransaction, client: ?*Client) !*Transaction {
        return try self.base.freezeWith(client);
    }

    // Sign the transaction with a private key
    pub fn sign(self: *AccountDeleteTransaction, private_key: anytype) !void {
        _ = try self.base.sign(private_key);
    }

    pub fn execute(self: *AccountDeleteTransaction, client: *Client) !TransactionResponse {
        if (self.delete_account_id == null) {
            return error.DeleteAccountIdRequired;
        }

        if (self.transfer_account_id == null) {
            return error.TransferAccountIdRequired;
        }

        return try self.base.execute(client);
    }

    // Build transaction body
    pub fn buildTransactionBody(self: *AccountDeleteTransaction) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();

        // Common transaction fields
        try self.writeCommonFields(&writer);

        // cryptoDelete = 12 (oneof data)
        var delete_writer = ProtoWriter.init(self.base.allocator);
        defer delete_writer.deinit();

        // deleteAccountID = 1
        if (self.delete_account_id) |account| {
            var account_writer = ProtoWriter.init(self.base.allocator);
            defer account_writer.deinit();
            try account_writer.writeInt64(1, @intCast(account.shard));
            try account_writer.writeInt64(2, @intCast(account.realm));
            try account_writer.writeInt64(3, @intCast(account.account));
            const account_bytes = try account_writer.toOwnedSlice();
            defer self.base.allocator.free(account_bytes);
            try delete_writer.writeMessage(1, account_bytes);
        }

        // transferAccountID = 2
        if (self.transfer_account_id) |transfer| {
            var transfer_writer = ProtoWriter.init(self.base.allocator);
            defer transfer_writer.deinit();
            try transfer_writer.writeInt64(1, @intCast(transfer.shard));
            try transfer_writer.writeInt64(2, @intCast(transfer.realm));
            try transfer_writer.writeInt64(3, @intCast(transfer.account));
            const transfer_bytes = try transfer_writer.toOwnedSlice();
            defer self.base.allocator.free(transfer_bytes);
            try delete_writer.writeMessage(2, transfer_bytes);
        }

        const delete_bytes = try delete_writer.toOwnedSlice();
        defer self.base.allocator.free(delete_bytes);
        try writer.writeMessage(12, delete_bytes);

        return writer.toOwnedSlice();
    }

    fn writeCommonFields(self: *AccountDeleteTransaction, writer: *ProtoWriter) !void {
        // transactionID = 1
        if (self.base.transaction_id) |tx_id| {
            var tx_id_writer = ProtoWriter.init(self.base.allocator);
            defer tx_id_writer.deinit();

            var timestamp_writer = ProtoWriter.init(self.base.allocator);
            defer timestamp_writer.deinit();
            try timestamp_writer.writeInt64(1, tx_id.valid_start.seconds);
            try timestamp_writer.writeInt32(2, tx_id.valid_start.nanos);
            const timestamp_bytes = try timestamp_writer.toOwnedSlice();
            defer self.base.allocator.free(timestamp_bytes);
            try tx_id_writer.writeMessage(1, timestamp_bytes);

            var account_writer = ProtoWriter.init(self.base.allocator);
            defer account_writer.deinit();
            try account_writer.writeInt64(1, @intCast(tx_id.account_id.shard));
            try account_writer.writeInt64(2, @intCast(tx_id.account_id.realm));
            try account_writer.writeInt64(3, @intCast(tx_id.account_id.account));
            const account_bytes = try account_writer.toOwnedSlice();
            defer self.base.allocator.free(account_bytes);
            try tx_id_writer.writeMessage(2, account_bytes);

            if (tx_id.nonce) |n| {
                try tx_id_writer.writeInt32(4, @intCast(n));
            }

            const tx_id_bytes = try tx_id_writer.toOwnedSlice();
            defer self.base.allocator.free(tx_id_bytes);
            try writer.writeMessage(1, tx_id_bytes);
        }

        // nodeAccountID = 2
        if (self.base.node_account_ids.items.len > 0) {
            var node_writer = ProtoWriter.init(self.base.allocator);
            defer node_writer.deinit();
            const node = self.base.node_account_ids.items[0];
            try node_writer.writeInt64(1, @intCast(node.shard));
            try node_writer.writeInt64(2, @intCast(node.realm));
            try node_writer.writeInt64(3, @intCast(node.account));
            const node_bytes = try node_writer.toOwnedSlice();
            defer self.base.allocator.free(node_bytes);
            try writer.writeMessage(2, node_bytes);
        }

        // transactionFee = 3
        if (self.base.max_transaction_fee) |fee| {
            try writer.writeUint64(3, @intCast(fee.toTinybars()));
        }

        // transactionValidDuration = 4
        var duration_writer = ProtoWriter.init(self.base.allocator);
        defer duration_writer.deinit();
        try duration_writer.writeInt64(1, self.base.transaction_valid_duration.toSeconds());
        const duration_bytes = try duration_writer.toOwnedSlice();
        defer self.base.allocator.free(duration_bytes);
        try writer.writeMessage(4, duration_bytes);

        // memo = 5
        if (self.base.transaction_memo.len > 0) {
            try writer.writeString(5, self.base.transaction_memo);
        }
    }
    
    // Wrapper function for Transaction base class function pointer
    pub fn buildTransactionBodyForNode(transaction: *Transaction, node: AccountId) anyerror![]u8 {
        const self = @as(*AccountDeleteTransaction, @fieldParentPtr("base", transaction));
        _ = node; // Node parameter not needed for this transaction
        return self.buildTransactionBody();
    }
};


