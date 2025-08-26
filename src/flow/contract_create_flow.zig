const std = @import("std");
const AccountId = @import("../core/id.zig").AccountId;
const FileId = @import("../core/id.zig").FileId;
const ContractId = @import("../core/id.zig").ContractId;
const Key = @import("../crypto/key.zig").Key;
const Hbar = @import("../core/hbar.zig").Hbar;
const Duration = @import("../core/duration.zig").Duration;
const Client = @import("../network/client.zig").Client;
const TransactionResponse = @import("../transaction/transaction.zig").TransactionResponse;
const FileCreateTransaction = @import("../file/file_create.zig").FileCreateTransaction;
const FileAppendTransaction = @import("../file/file_append.zig").FileAppendTransaction;
const ContractCreateTransaction = @import("../contract/contract_create.zig").ContractCreateTransaction;
const ContractFunctionParameters = @import("../contract/contract_execute.zig").ContractFunctionParameters;

// ContractCreateFlow creates a contract with bytecode that may exceed transaction size limits
pub const ContractCreateFlow = struct {
    bytecode: []const u8,
    proxy_account_id: ?AccountId = null,
    admin_key: ?Key = null,
    gas: i64,
    initial_balance: Hbar,
    auto_renew_period: Duration,
    parameters: []const u8,
    node_account_ids: std.ArrayList(AccountId),
    create_bytecode: []const u8,
    append_bytecode: []const u8,
    auto_renew_account_id: ?AccountId = null,
    max_automatic_token_associations: i32,
    max_chunks: ?u64 = null,
    memo: []const u8,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) ContractCreateFlow {
        return ContractCreateFlow{
            .bytecode = &[_]u8{},
            .gas = 100000,
            .initial_balance = Hbar.init(0),
            .auto_renew_period = Duration.init(131500 * 60), // 131500 minutes default
            .parameters = &[_]u8{},
            .node_account_ids = std.ArrayList(AccountId).init(allocator),
            .create_bytecode = &[_]u8{},
            .append_bytecode = &[_]u8{},
            .max_automatic_token_associations = 0,
            .memo = &[_]u8{},
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *ContractCreateFlow) void {
        if (self.bytecode.len > 0) self.allocator.free(self.bytecode);
        if (self.parameters.len > 0) self.allocator.free(self.parameters);
        self.node_account_ids.deinit();
        if (self.create_bytecode.len > 0) self.allocator.free(self.create_bytecode);
        if (self.append_bytecode.len > 0) self.allocator.free(self.append_bytecode);
        if (self.memo.len > 0) self.allocator.free(self.memo);
    }
    
    // Set the bytecode
    pub fn setBytecode(self: *ContractCreateFlow, bytecode: []const u8) !*ContractCreateFlow {
        if (self.bytecode.len > 0) self.allocator.free(self.bytecode);
        self.bytecode = try self.allocator.dupe(u8, bytecode);
        return self;
    }
    
    // Set bytecode from hex string
    pub fn setBytecodeWithString(self: *ContractCreateFlow, hex_string: []const u8) !*ContractCreateFlow {
        if (self.bytecode.len > 0) self.allocator.free(self.bytecode);
        
        // Allocate for decoded bytes (half the size of hex string)
        const byte_count = hex_string.len / 2;
        var decoded = try self.allocator.alloc(u8, byte_count);
        
        // Decode hex string to bytes
        var i: usize = 0;
        while (i < hex_string.len) : (i += 2) {
            const high = try charToHex(hex_string[i]);
            const low = try charToHex(hex_string[i + 1]);
            decoded[i / 2] = (high << 4) | low;
        }
        
        self.bytecode = decoded;
        return self;
    }
    
    fn charToHex(c: u8) !u8 {
        return switch (c) {
            '0'...'9' => c - '0',
            'a'...'f' => c - 'a' + 10,
            'A'...'F' => c - 'A' + 10,
            else => error.InvalidHexCharacter,
        };
    }
    
    // Set admin key
    pub fn setAdminKey(self: *ContractCreateFlow, admin_key: Key) !*ContractCreateFlow {
        self.admin_key = admin_key;
        return self;
    }
    
    // Set gas
    pub fn setGas(self: *ContractCreateFlow, gas: i64) !*ContractCreateFlow {
        self.gas = gas;
        return self;
    }
    
    // Set initial balance
    pub fn setInitialBalance(self: *ContractCreateFlow, initial_balance: Hbar) !*ContractCreateFlow {
        self.initial_balance = initial_balance;
        return self;
    }
    
    // Set auto renew period
    pub fn setAutoRenewPeriod(self: *ContractCreateFlow, period: Duration) !*ContractCreateFlow {
        self.auto_renew_period = period;
        return self;
    }
    
    // Set proxy account ID (deprecated)
    pub fn setProxyAccountId(self: *ContractCreateFlow, proxy_account_id: AccountId) !*ContractCreateFlow {
        self.proxy_account_id = proxy_account_id;
        return self;
    }
    
    // Set constructor parameters
    pub fn setConstructorParameters(self: *ContractCreateFlow, params: *ContractFunctionParameters) !*ContractCreateFlow {
        if (self.parameters.len > 0) self.allocator.free(self.parameters);
        self.parameters = try params.build(self.allocator);
        return self;
    }
    
    // Set raw constructor parameters
    pub fn setConstructorParametersRaw(self: *ContractCreateFlow, params: []const u8) !*ContractCreateFlow {
        if (self.parameters.len > 0) self.allocator.free(self.parameters);
        self.parameters = try self.allocator.dupe(u8, params);
        return self;
    }
    
    // Set contract memo
    pub fn setContractMemo(self: *ContractCreateFlow, memo: []const u8) !*ContractCreateFlow {
        if (self.memo.len > 0) self.allocator.free(self.memo);
        self.memo = try self.allocator.dupe(u8, memo);
        return self;
    }
    
    // Set max chunks
    pub fn setMaxChunks(self: *ContractCreateFlow, max: u64) !*ContractCreateFlow {
        self.max_chunks = max;
        return self;
    }
    
    // Set auto renew account ID
    pub fn setAutoRenewAccountId(self: *ContractCreateFlow, id: AccountId) !*ContractCreateFlow {
        self.auto_renew_account_id = id;
        return self;
    }
    
    // Set max automatic token associations
    pub fn setMaxAutomaticTokenAssociations(self: *ContractCreateFlow, max: i32) !*ContractCreateFlow {
        self.max_automatic_token_associations = max;
        return self;
    }
    
    // Set node account IDs
    pub fn setNodeAccountIds(self: *ContractCreateFlow, node_ids: []const AccountId) !*ContractCreateFlow {
        self.node_account_ids.clearRetainingCapacity();
        self.node_account_ids.appendSlice(node_ids);
        return self;
    }
    
    // Split bytecode into chunks
    fn splitBytecode(self: *ContractCreateFlow) !void {
        if (self.create_bytecode.len > 0) self.allocator.free(self.create_bytecode);
        if (self.append_bytecode.len > 0) self.allocator.free(self.append_bytecode);
        
        if (self.bytecode.len > 2048) {
            self.create_bytecode = try self.allocator.dupe(u8, self.bytecode[0..2048]);
            self.append_bytecode = try self.allocator.dupe(u8, self.bytecode[2048..]);
        } else {
            self.create_bytecode = try self.allocator.dupe(u8, self.bytecode);
            self.append_bytecode = &[_]u8{};
        }
    }
    
    // Create file create transaction
    fn createFileCreateTransaction(self: *ContractCreateFlow, client: *Client) !FileCreateTransaction {
        var file_create = FileCreateTransaction.init(self.allocator);
        
        // Set operator public key as file key
        if (client.operator_public_key) |key| {
            var keys = std.ArrayList(Key).init(self.allocator);
            try keys.append(key);
            try file_create.setKeys(keys);
        }
        
        try file_create.setContents(self.create_bytecode);
        
        if (self.node_account_ids.items.len > 0) {
            file_create.base.node_account_ids = try self.node_account_ids.clone();
        }
        
        return file_create;
    }
    
    // Create file append transaction
    fn createFileAppendTransaction(self: *ContractCreateFlow, file_id: FileId) !FileAppendTransaction {
        var file_append = FileAppendTransaction.init(self.allocator);
        
        try file_append.setFileId(file_id);
        try file_append.setContents(self.append_bytecode);
        
        if (self.node_account_ids.items.len > 0) {
            file_append.base.node_account_ids = try self.node_account_ids.clone();
        }
        
        if (self.max_chunks) |max| {
            file_append.max_chunks = max;
        }
        
        return file_append;
    }
    
    // Create contract create transaction
    fn createContractCreateTransaction(self: *ContractCreateFlow, file_id: FileId) !ContractCreateTransaction {
        var contract_create = ContractCreateTransaction.init(self.allocator);
        
        try contract_create.setGas(@intCast(self.gas));
        try contract_create.setConstructorParametersRaw(self.parameters);
        try contract_create.setInitialBalance(self.initial_balance);
        try contract_create.setBytecodeFileId(file_id);
        try contract_create.setContractMemo(self.memo);
        
        if (self.node_account_ids.items.len > 0) {
            contract_create.base.node_account_ids = try self.node_account_ids.clone();
        }
        
        if (self.admin_key) |key| {
            try contract_create.setAdminKey(key);
        }
        
        try contract_create.setAutoRenewPeriod(self.auto_renew_period);
        
        if (self.auto_renew_account_id) |account_id| {
            try contract_create.setAutoRenewAccountId(account_id);
        }
        
        if (self.max_automatic_token_associations != 0) {
            try contract_create.setMaxAutomaticTokenAssociations(self.max_automatic_token_associations);
        }
        
        return contract_create;
    }
    
    // Execute the flow
    pub fn execute(self: *ContractCreateFlow, client: *Client) !TransactionResponse {
        // Split bytecode if necessary
        try self.splitBytecode();
        
        // Create file with bytecode
        var file_create = try self.createFileCreateTransaction(client);
        defer file_create.deinit();
        
        const file_create_response = try file_create.execute(client);
        const file_create_receipt = try file_create_response.getReceipt(client);
        
        if (file_create_receipt.file_id == null) {
            return error.FileIdNotReceived;
        }
        
        const file_id = file_create_receipt.file_id.?;
        
        // Append remaining bytecode if necessary
        if (self.append_bytecode.len > 0) {
            var file_append = try self.createFileAppendTransaction(file_id);
            defer file_append.deinit();
            
            const file_append_response = try file_append.execute(client);
            _ = try file_append_response.getReceipt(client);
        }
        
        // Create contract
        var contract_create = try self.createContractCreateTransaction(file_id);
        defer contract_create.deinit();
        
        const contract_create_response = try contract_create.execute(client);
        _ = try contract_create_response.getReceipt(client);
        
        return contract_create_response;
    }
};

// Creates a new contract creation flow
pub fn contractCreateFlow(allocator: std.mem.Allocator) ContractCreateFlow {
    return ContractCreateFlow.init(allocator);
}