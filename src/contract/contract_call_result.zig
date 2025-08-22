const std = @import("std");
const ContractId = @import("../core/id.zig").ContractId;

// ContractCallResult contains the result of a contract function call
pub const ContractCallResult = struct {
    contract_id: ?ContractId = null,
    result: ?[]u8 = null,
    error_message: ?[]const u8 = null,
    bloom: ?[]u8 = null,
    gas_used: u64 = 0,
    gas_limit: u64 = 0,
    logs: std.ArrayList(ContractLogInfo),
    created_contract_ids: std.ArrayList(ContractId),
    state_changes: std.ArrayList(StateChange),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) ContractCallResult {
        return ContractCallResult{
            .logs = std.ArrayList(ContractLogInfo).init(allocator),
            .created_contract_ids = std.ArrayList(ContractId).init(allocator),
            .state_changes = std.ArrayList(StateChange).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *ContractCallResult) void {
        if (self.result) |r| {
            self.allocator.free(r);
        }
        if (self.error_message) |e| {
            self.allocator.free(e);
        }
        if (self.bloom) |b| {
            self.allocator.free(b);
        }
        
        for (self.logs.items) |*log| {
            log.deinit();
        }
        self.logs.deinit();
        
        self.created_contract_ids.deinit();
        
        for (self.state_changes.items) |*change| {
            change.deinit();
        }
        self.state_changes.deinit();
    }
    
    pub const StateChange = struct {
        contract_id: ContractId,
        storage_changes: []StorageChange,
        allocator: std.mem.Allocator,
        
        pub fn deinit(self: *StateChange) void {
            self.allocator.free(self.storage_changes);
        }
    };
    
    pub const StorageChange = struct {
        key: [32]u8,
        old_value: [32]u8,
        new_value: [32]u8,
    };
};

// ContractLogInfo contains log information from a smart contract
pub const ContractLogInfo = struct {
    contract_id: ?ContractId = null,
    bloom: ?[]u8 = null,
    topics: std.ArrayList([]u8),
    data: ?[]u8 = null,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) ContractLogInfo {
        return ContractLogInfo{
            .topics = std.ArrayList([]u8).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *ContractLogInfo) void {
        if (self.bloom) |b| {
            self.allocator.free(b);
        }
        
        for (self.topics.items) |topic| {
            self.allocator.free(topic);
        }
        self.topics.deinit();
        
        if (self.data) |d| {
            self.allocator.free(d);
        }
    }
};