const std = @import("std");

// Hedera network request types for fee calculation
pub const RequestType = enum(u32) {
    NONE = 0,
    
    // Crypto operations
    CryptoTransfer = 1,
    CryptoCreate = 2,
    CryptoUpdate = 3,
    CryptoDelete = 4,
    CryptoAddLiveHash = 5,
    CryptoDeleteLiveHash = 6,
    CryptoGetAccountBalance = 7,
    CryptoGetAccountRecords = 8,
    CryptoGetInfo = 9,
    CryptoGetLiveHash = 10,
    CryptoGetProxyStakers = 11,
    CryptoGetStakers = 12,
    
    // File operations
    FileCreate = 13,
    FileUpdate = 14,
    FileDelete = 15,
    FileAppend = 16,
    FileGetContents = 17,
    FileGetInfo = 18,
    
    // Contract operations
    ContractCall = 19,
    ContractCreate = 20,
    ContractUpdate = 21,
    ContractDelete = 22,
    ContractGetBytecode = 23,
    ContractGetInfo = 24,
    ContractCallLocal = 25,
    ContractGetRecords = 26,
    
    // System operations
    SystemDelete = 27,
    SystemUndelete = 28,
    Freeze = 29,
    
    // Consensus operations
    ConsensusCreateTopic = 30,
    ConsensusUpdateTopic = 31,
    ConsensusDeleteTopic = 32,
    ConsensusGetTopicInfo = 33,
    ConsensusSubmitMessage = 34,
    
    // Token operations
    TokenCreate = 35,
    TokenUpdate = 36,
    TokenMint = 37,
    TokenBurn = 38,
    TokenDelete = 39,
    TokenWipe = 40,
    TokenFreeze = 41,
    TokenUnfreeze = 42,
    TokenGrantKyc = 43,
    TokenRevokeKyc = 44,
    TokenAssociate = 45,
    TokenDissociate = 46,
    TokenGetInfo = 47,
    TokenGetNftInfo = 48,
    TokenGetNftInfos = 49,
    TokenGetAccountNftInfos = 50,
    TokenFeeScheduleUpdate = 51,
    TokenPause = 52,
    TokenUnpause = 53,
    
    // Schedule operations
    ScheduleCreate = 54,
    ScheduleSign = 55,
    ScheduleDelete = 56,
    ScheduleGetInfo = 57,
    
    // Network operations
    NetworkGetVersionInfo = 58,
    NetworkGetExecutionTime = 59,
    GetByKey = 60,
    GetBySolidityID = 61,
    
    // Account allowance operations
    CryptoApproveAllowance = 62,
    CryptoDeleteAllowance = 63,
    
    // Ethereum transaction
    EthereumTransaction = 64,
    
    // Node stake update
    NodeStakeUpdate = 65,
    
    // Utility prng
    UtilPrng = 66,
    
    const Self = @This();
    
    pub fn toString(self: Self) []const u8 {
        return @tagName(self);
    }
    
    pub fn fromInt(value: u32) !Self {
        return std.meta.intToEnum(Self, value) catch error.InvalidRequestType;
    }
    
    pub fn toInt(self: Self) u32 {
        return @intFromEnum(self);
    }
    
    pub fn getBaseFee(self: Self) u64 {
        // Base fees in tinybars
        return switch (self) {
            .CryptoTransfer => 1000,
            .CryptoCreate => 100000,
            .CryptoUpdate => 10000,
            .CryptoDelete => 10000,
            .TokenCreate => 500000,
            .TokenUpdate => 50000,
            .TokenMint => 50000,
            .TokenBurn => 50000,
            .ContractCreate => 500000,
            .ContractCall => 50000,
            .FileCreate => 50000,
            .FileUpdate => 10000,
            .ConsensusCreateTopic => 100000,
            .ConsensusSubmitMessage => 1000,
            .ScheduleCreate => 10000,
            else => 1000,
        };
    }
    
    pub fn requiresSignature(self: Self) bool {
        return switch (self) {
            .CryptoGetAccountBalance,
            .CryptoGetAccountRecords,
            .CryptoGetInfo,
            .FileGetContents,
            .FileGetInfo,
            .ContractGetBytecode,
            .ContractGetInfo,
            .ContractCallLocal,
            .ConsensusGetTopicInfo,
            .TokenGetInfo,
            .TokenGetNftInfo,
            .TokenGetNftInfos,
            .TokenGetAccountNftInfos,
            .ScheduleGetInfo,
            .NetworkGetVersionInfo,
            .NetworkGetExecutionTime,
            .GetByKey,
            .GetBySolidityID => false,
            else => true,
        };
    }
    
    pub fn isQuery(self: Self) bool {
        return switch (self) {
            .CryptoGetAccountBalance,
            .CryptoGetAccountRecords,
            .CryptoGetInfo,
            .CryptoGetLiveHash,
            .CryptoGetProxyStakers,
            .CryptoGetStakers,
            .FileGetContents,
            .FileGetInfo,
            .ContractGetBytecode,
            .ContractGetInfo,
            .ContractCallLocal,
            .ContractGetRecords,
            .ConsensusGetTopicInfo,
            .TokenGetInfo,
            .TokenGetNftInfo,
            .TokenGetNftInfos,
            .TokenGetAccountNftInfos,
            .ScheduleGetInfo,
            .NetworkGetVersionInfo,
            .NetworkGetExecutionTime,
            .GetByKey,
            .GetBySolidityID => true,
            else => false,
        };
    }
    
    pub fn isTransaction(self: Self) bool {
        return !self.isQuery();
    }
};