const std = @import("std");
const AccountId = @import("../core/id.zig").AccountId;
const ContractId = @import("../core/id.zig").ContractId;
const TokenId = @import("../core/id.zig").TokenId;
const Hbar = @import("../core/hbar.zig").Hbar;
const Duration = @import("../core/duration.zig").Duration;
const Query = @import("../query/query.zig").Query;
const QueryResponse = @import("../query/query.zig").QueryResponse;
const Client = @import("../network/client.zig").Client;
const ProtoWriter = @import("../protobuf/encoding.zig").ProtoWriter;
const ProtoReader = @import("../protobuf/encoding.zig").ProtoReader;

// Token balance information
pub const TokenBalance = struct {
    token_id: TokenId,
    balance: u64,
    decimals: u32,
    
    pub fn encode(self: TokenBalance, writer: *ProtoWriter) !void {
        // tokenId = 1
        var token_writer = ProtoWriter.init(writer.buffer.allocator);
        defer token_writer.deinit();
        try token_writer.writeInt64(1, @intCast(self.token_id.shard));
        try token_writer.writeInt64(2, @intCast(self.token_id.realm));
        try token_writer.writeInt64(3, @intCast(self.token_id.num));
        const token_bytes = try token_writer.toOwnedSlice();
        defer writer.buffer.allocator.free(token_bytes);
        try writer.writeMessage(1, token_bytes);
        
        // balance = 2
        try writer.writeUint64(2, self.balance);
        
        // decimals = 3
        try writer.writeUint32(3, self.decimals);
    }
    
    pub fn decode(reader: *ProtoReader, allocator: std.mem.Allocator) !TokenBalance {
        var token_id: ?TokenId = null;
        var balance: u64 = 0;
        var decimals: u32 = 0;
        
        while (reader.hasMore()) {
            const tag = try reader.readTag();
            
            switch (tag.field_number) {
                1 => {
                    const token_bytes = try reader.readMessage();
                    var token_reader = ProtoReader.init(token_bytes);
                    
                    var shard: i64 = 0;
                    var realm: i64 = 0;
                    var num: i64 = 0;
                    
                    while (token_reader.hasMore()) {
                        const token_tag = try token_reader.readTag();
                        switch (token_tag.field_number) {
                            1 => shard = try token_reader.readInt64(),
                            2 => realm = try token_reader.readInt64(),
                            3 => num = try token_reader.readInt64(),
                            else => try token_reader.skipField(token_tag.wire_type),
                        }
                    }
                    
                    token_id = TokenId.init(
                        @intCast(shard),
                        @intCast(realm),
                        @intCast(num),
                    );
                },
                2 => balance = try reader.readUint64(),
                3 => decimals = try reader.readUint32(),
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        _ = allocator;
        
        return TokenBalance{
            .token_id = token_id orelse TokenId.init(0, 0, 0),
            .balance = balance,
            .decimals = decimals,
        };
    }
};

// Account balance information
pub const AccountBalance = struct {
    hbars: Hbar,
    tokens: std.AutoHashMap(TokenId, u64),
    token_decimals: std.AutoHashMap(TokenId, u32),
    
    pub fn init(allocator: std.mem.Allocator) AccountBalance {
        return AccountBalance{
            .hbars = Hbar.zero(),
            .tokens = std.AutoHashMap(TokenId, u64).init(allocator),
            .token_decimals = std.AutoHashMap(TokenId, u32).init(allocator),
        };
    }
    
    pub fn deinit(self: *AccountBalance) void {
        self.tokens.deinit();
        self.token_decimals.deinit();
    }
    
    pub fn getTokenBalance(self: AccountBalance, token_id: TokenId) u64 {
        return self.tokens.get(token_id) orelse 0;
    }
    
    pub fn getTokenDecimals(self: AccountBalance, token_id: TokenId) u32 {
        return self.token_decimals.get(token_id) orelse 0;
    }
};

// AccountBalanceQuery retrieves the balance of an account
pub const AccountBalanceQuery = struct {
    base: Query,
    account_id: ?AccountId,
    contract_id: ?ContractId,
    request_timeout: Duration,
    max_backoff: Duration,
    min_backoff: Duration,
    
    pub fn init(allocator: std.mem.Allocator) AccountBalanceQuery {
        return AccountBalanceQuery{
            .base = Query.init(allocator),
            .account_id = null,
            .contract_id = null,
            .request_timeout = Duration.fromSeconds(30),
            .max_backoff = Duration.fromSeconds(8),
            .min_backoff = Duration.fromMilliseconds(250),
        };
    }
    
    pub fn deinit(self: *AccountBalanceQuery) void {
        self.base.deinit();
    }
    
    // Set the account ID to query
    pub fn setAccountId(self: *AccountBalanceQuery, account_id: AccountId) *AccountBalanceQuery {
        self.contract_id = null; // Clear contract ID when setting account ID
        self.account_id = account_id;
        self.base.is_payment_required = false; // Balance queries are free
        return self;
    }
    
    // Set max retry attempts (Go SDK compatibility)
    pub fn setMaxRetry(self: *AccountBalanceQuery, retry_count: u32) *AccountBalanceQuery {
        self.base.max_attempts = retry_count;
        return self;
    }
    
    // Get max retry attempts (Go SDK compatibility)
    pub fn max_retry(self: AccountBalanceQuery) u32 {
        return self.base.max_attempts;
    }
    
    // Set the contract ID to query
    pub fn setContractId(self: *AccountBalanceQuery, contract_id: ContractId) *AccountBalanceQuery {
        self.account_id = null; // Clear account ID when setting contract ID
        self.contract_id = contract_id;
        self.base.is_payment_required = false; // Balance queries are free
        return self;
    }
    
    // Set query payment
    pub fn setQueryPayment(self: *AccountBalanceQuery, amount: Hbar) *AccountBalanceQuery {
        _ = self.base.setQueryPayment(amount);
        return self;
    }
    
    // Get query payment (Go SDK compatibility)
    pub fn payment(self: AccountBalanceQuery) ?Hbar {
        return self.base.payment_amount;
    }
    
    // Set request timeout
    pub fn setRequestTimeout(self: *AccountBalanceQuery, timeout: Duration) *AccountBalanceQuery {
        self.request_timeout = timeout;
        _ = self.base.setRequestTimeout(timeout.toMilliseconds());
        return self;
    }
    
    // Set max backoff
    pub fn setMaxBackoff(self: *AccountBalanceQuery, backoff: Duration) *AccountBalanceQuery {
        self.max_backoff = backoff;
        return self;
    }
    
    // Set min backoff
    pub fn setMinBackoff(self: *AccountBalanceQuery, backoff: Duration) *AccountBalanceQuery {
        self.min_backoff = backoff;
        return self;
    }
    
    // Execute the query
    pub fn execute(self: *AccountBalanceQuery, client: *Client) !AccountBalance {
        if (self.account_id == null and self.contract_id == null) {
            return error.AccountOrContractIdRequired;
        }
        
        const response = try self.base.execute(client);
        return try self.parseResponse(response);
    }
    
    // Get cost of the query (always free for balance queries)
    pub fn getCost(self: *AccountBalanceQuery, client: *Client) !Hbar {
        _ = self;
        _ = client;
        return Hbar.zero();
    }
    
    // Build the query
    pub fn buildQuery(self: *AccountBalanceQuery) ![]u8 {
        var writer = ProtoWriter.init(self.base.allocator);
        defer writer.deinit();
        
        // Query message structure
        // header = 1
        var header_writer = ProtoWriter.init(self.base.allocator);
        defer header_writer.deinit();
        
        // payment = 1 (optional for free queries)
        // responseType = 2
        try header_writer.writeInt32(2, @intFromEnum(self.base.response_type));
        
        const header_bytes = try header_writer.toOwnedSlice();
        defer self.base.allocator.free(header_bytes);
        try writer.writeMessage(1, header_bytes);
        
        // cryptogetAccountBalance = 2 (oneof query)
        var balance_query_writer = ProtoWriter.init(self.base.allocator);
        defer balance_query_writer.deinit();
        
        if (self.account_id) |account| {
            // accountID = 1
            var account_writer = ProtoWriter.init(self.base.allocator);
            defer account_writer.deinit();
            try account_writer.writeInt64(1, @intCast(account.shard));
            try account_writer.writeInt64(2, @intCast(account.realm));
            try account_writer.writeInt64(3, @intCast(account.account));
            
            if (account.alias_key) |alias| {
                try account_writer.writeString(4, alias);
            } else if (account.evm_address) |evm| {
                try account_writer.writeString(4, evm);
            }
            
            const account_bytes = try account_writer.toOwnedSlice();
            defer self.base.allocator.free(account_bytes);
            try balance_query_writer.writeMessage(1, account_bytes);
        } else if (self.contract_id) |contract| {
            // contractID = 2
            var contract_writer = ProtoWriter.init(self.base.allocator);
            defer contract_writer.deinit();
            try contract_writer.writeInt64(1, @intCast(contract.shard));
            try contract_writer.writeInt64(2, @intCast(contract.realm));
            try contract_writer.writeInt64(3, @intCast(contract.num));
            
            if (contract.evm_address) |evm| {
                try contract_writer.writeString(4, evm);
            }
            
            const contract_bytes = try contract_writer.toOwnedSlice();
            defer self.base.allocator.free(contract_bytes);
            try balance_query_writer.writeMessage(2, contract_bytes);
        }
        
        const balance_query_bytes = try balance_query_writer.toOwnedSlice();
        defer self.base.allocator.free(balance_query_bytes);
        try writer.writeMessage(2, balance_query_bytes);
        
        return writer.toOwnedSlice();
    }
    
    // Parse the response
    fn parseResponse(self: *AccountBalanceQuery, response: QueryResponse) !AccountBalance {
        try response.validateStatus();
        
        var reader = ProtoReader.init(response.response_bytes);
        var balance = AccountBalance.init(self.base.allocator);
        
        // Parse CryptoGetAccountBalanceResponse
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
                    // balance (in tinybars)
                    const tinybars = try reader.readUint64();
                    balance.hbars = try Hbar.fromTinybars(@intCast(tinybars));
                },
                4 => {
                    // tokenBalances (repeated)
                    const token_balance_bytes = try reader.readMessage();
                    var token_reader = ProtoReader.init(token_balance_bytes);
                    const token_balance = try TokenBalance.decode(&token_reader, self.base.allocator);
                    
                    try balance.tokens.put(token_balance.token_id, token_balance.balance);
                    try balance.token_decimals.put(token_balance.token_id, token_balance.decimals);
                },
                else => try reader.skipField(tag.wire_type),
            }
        }
        
        return balance;
    }
};