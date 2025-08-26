const std = @import("std");

// Core Hedera error set matching all official status codes
pub const HederaError = error{
    // Success and neutral responses
    Ok,
    
    // Protocol errors
    InvalidTransaction,
    TransactionFrozen,
    PayerAccountNotFound,
    InvalidNodeAccount,
    TransactionExpired,
    InvalidTransactionStart,
    InvalidTransactionDuration,
    InvalidSignature,
    MemoTooLong,
    InsufficientTxFee,
    InsufficientPayerBalance,
    DuplicateTransaction,
    Busy,
    NotSupported,
    InvalidFileId,
    InvalidAccountId,
    InvalidContractId,
    InvalidTransactionId,
    ReceiptNotFound,
    RecordNotFound,
    InvalidSolidityId,
    Unknown,
    Success,
    FailInvalid,
    FailFee,
    FailBalance,
    
    // Key errors
    KeyRequired,
    BadEncoding,
    InsufficientAccountBalance,
    InvalidSolidityAddress,
    InsufficientGas,
    ContractSizeLimitExceeded,
    LocalCallModificationException,
    ContractRevertExecuted,
    ContractExecutionException,
    InvalidReceivingNodeAccount,
    MissingQueryHeader,
    
    // Account errors
    AccountUpdateFailed,
    InvalidKeyEncoding,
    NullSolidityAddress,
    ContractUpdateFailed,
    InvalidQueryHeader,
    QueryRequestFailed,
    InvalidFeeSubmitted,
    InvalidPayerSignature,
    KeyNotProvided,
    InvalidExpirationTime,
    NoWaclKey,
    FileContentEmpty,
    InvalidAccountAmounts,
    EmptyTransactionBody,
    InvalidTransactionBody,
    
    // Signature and verification errors
    InvalidSignatureTypeMismatchingKey,
    InvalidSubmitKey,
    Unauthorized,
    InvalidFeeFile,
    InvalidExchangeRateFile,
    InsufficientLocalCallGas,
    EntityNotAllowedToDelete,
    AuthorizationFailed,
    FileUploadedProtoInvalid,
    FileUploadedProtoNotSavedToDisk,
    FeeScheduleFilePartUploaded,
    ExchangeRateChangeLimitExceeded,
    
    // Throttle and limit errors
    MaxContractStorageExceeded,
    TransferAccountSameAsDeleteAccount,
    TotalLedgerBalanceInvalid,
    ExpirationReductionNotAllowed,
    MaxGasLimitExceeded,
    MaxFileSizeExceeded,
    ReceiverSigRequired,
    
    // Crypto and token errors
    InvalidTopicId,
    InvalidAdminKey,
    InvalidSubmitKey2,
    InvalidTopicMessage,
    InvalidAutorenewAccount,
    AutorenewAccountNotAllowed,
    TopicExpired,
    InvalidChunkNumber,
    InvalidChunkTransactionId,
    AccountFrozenForToken,
    TokensPerAccountLimitExceeded,
    InvalidTokenId,
    InvalidTokenDecimals,
    InvalidTokenInitialSupply,
    InvalidTokenMaximumSupply,
    InvalidTreasuryAccountForToken,
    InvalidTokenSymbol,
    TokenHasNoFreezeKey,
    TransfersNotZeroSumForToken,
    MissingTokenSymbol,
    TokenSymbolTooLong,
    AccountKycNotGrantedForToken,
    TokenHasNoKycKey,
    InsufficientTokenBalance,
    TokenWasDeleted,
    TokenHasNoSupplyKey,
    TokenHasNoWipeKey,
    InvalidTokenMintAmount,
    InvalidTokenBurnAmount,
    TokenNotAssociatedToAccount,
    CannotWipeTokenTreasuryAccount,
    InvalidKycKey,
    InvalidWipeKey,
    InvalidFreezeKey,
    InvalidSupplyKey,
    MissingTokenName,
    TokenNameTooLong,
    InvalidWipingAmount,
    TokenIsImmutable,
    TokenAlreadyAssociatedToAccount,
    TransactionRequiresZeroTokenBalances,
    AccountIsTreasury,
    TokenIdRepeatedInTokenList,
    TokenTransferListSizeLimitExceeded,
    EmptyTokenTransferBody,
    EmptyTokenTransferAccountAmounts,
    
    // Schedule errors
    InvalidScheduleId,
    ScheduleIsImmutable,
    InvalidSchedulePayerId,
    InvalidScheduleAccountId,
    NoNewValidSignatures,
    UnresolvableRequiredSigners,
    ScheduledTransactionNotInWhitelist,
    SomeSignaturesWereInvalid,
    TransactionIdFieldNotAllowed,
    IdenticalScheduleAlreadyCreated,
    InvalidZeroByteInString,
    ScheduleAlreadyDeleted,
    ScheduleAlreadyExecuted,
    MessageSizeTooLarge,
    
    // Freeze errors
    OperationNotAuthorized,
    NotCurrentlyValid,
    InvalidFreezeTransactionBody,
    FreezeTransactionBodyNotFound,
    TransferListSizeLimitExceeded,
    ResultSizeLimitExceeded,
    NotSpecialAccount,
    ContractNegativeGas,
    ContractNegativeValue,
    InvalidFeeFile2,
    InvalidExchangeRateFile2,
    InsufficientLocalCallGas2,
    EntityNotAllowedToDelete2,
    AuthorizationFailed2,
    FileUploadedProtoInvalid2,
    FileUploadedProtoNotSavedToDisk2,
    FeeScheduleFilePartUploaded2,
    ExchangeRateChangeLimitExceeded2,
    
    // NFT errors
    InvalidCustomFeeCollector,
    InvalidTokenIdInCustomFees,
    TokenNotAssociatedToFeeCollector,
    TokenMaxSupplyReached,
    SenderDoesNotOwnNftSerialNo,
    CustomFeeNotFullySpecified,
    CustomFeeMustBePositive,
    TokenHasNoFeeScheduleKey,
    CustomFeeOutsideNumericRange,
    RoyaltyFractionCannotExceedOne,
    FractionalFeeMaxAmountLessThanMinAmount,
    CustomScheduleAlreadyHasNoFees,
    CustomFeeDenominationMustBeFungibleCommon,
    CustomFractionalFeeOnlyAllowedForFungibleCommon,
    InvalidCustomFeeScheduleKey,
    InvalidTokenMintMetadata,
    InvalidTokenBurnMetadata,
    CurrentTreasuryStillOwnsNfts,
    AccountStillOwnsNfts,
    TreasuryMustOwnBurnedNft,
    AccountDoesNotOwnWipedNft,
    AccountAmountTransfersOnlyAllowedForFungibleCommon,
    MaxNftsInPriceRegimeHaveBeenMinted,
    PayerAccountDeleted,
    CustomFeeChargingExceededMaxRecursionDepth,
    CustomFeeChargingExceededMaxAccountAmounts,
    InsufficientSenderAccountBalanceForCustomFee,
    SerialNumberLimitReached,
    CustomRoyaltyFeeOnlyAllowedForNonFungibleUnique,
    NoRemainingAutomaticAssociations,
    ExistingAutomaticAssociationsExceedGivenLimit,
    RequestedNumAutomaticAssociationsExceedsAssociationLimit,
    TokenIsPaused,
    TokenHasNoPauseKey,
    InvalidPauseKey,
    FreezeUpdateFileDoesNotExist,
    FreezeUpdateFileHashDoesNotMatch,
    NoUpgradeHasBeenPrepared,
    NoFreezeIsScheduled,
    UpdateFileHashChangedSincePrepareUpgrade,
    FreezeStartTimeMustBeFuture,
    PreparedUpdateFileIsImmutable,
    FreezeAlreadyScheduled,
    FreezeUpgradeInProgress,
    UpdateFileIdDoesNotMatchPrepared,
    UpdateFileHashDoesNotMatchPrepared,
    ConsensusGasExhausted,
    RevertedSuccess,
    MaxStorageInPriceRegimeHasBeenUsed,
    InvalidAliasKey,
    UnexpectedTokenDecimals,
    InvalidProxyAccountId,
    InvalidTransferAccountId,
    InvalidFeeCollectorAccountId,
    AliasIsImmutable,
    SpenderAccountSameAsOwner,
    AmountExceedsTokenMaxSupply,
    NegativeAllowanceAmount,
    CannotApproveForAllFungibleCommon,
    SpenderDoesNotHaveAllowance,
    AmountExceedsAllowance,
    MaxAllowancesExceeded,
    EmptyAllowances,
    SpenderAccountRepeatedInAllowance,
    RepeatedSerialNumbersInNftAllowance,
    FungibleTokenInNftAllowance,
    NftInFungibleTokenAllowance,
    InvalidAllowanceOwnerId,
    InvalidAllowanceSpenderId,
    RepeatedAllowancesToDelete,
    InvalidDelegatingSpender,
    DelegatingSpenderCannotGrantApproveForAll,
    DelegatingSpenderDoesNotHaveApproveForAll,
    ScheduleExpirationTimeTooFarInFuture,
    ScheduleExpirationTimeMustBeHigherThanConsensusTime,
    ScheduleFutureThrottleExceeded,
    ScheduleFutureGasLimitExceeded,
    InvalidEthereumTransaction,
    WrongChainId,
    WrongNonce,
    AccessListUnsupported,
    SchedulePendingExpiration,
    ContractIsTokenTreasury,
    ContractHasNonZeroTokenBalances,
    ContractExpiredAndPendingRemoval,
    ContractHasNoAutoRenewAccount,
    PermanentRemovalRequiresSystemInitiation,
    ProxyAccountIdFieldIsDeprecated,
    SelfStakingIsNotAllowed,
    InvalidStakingId,
    InvalidStakedId,
    InvalidAlias,
    StakingNotEnabled,
    InvalidRandomGenerateRange,
    MaxEntitiesInPriceRegimeHaveBeenCreated,
    InvalidFullPrefixSignatureForPrecompile,
    InsufficientBalancesForStorageRent,
    MaxChildRecordsExceeded,
    InsufficientBalancesForRenewalFees,
    TransactionHasUnknownFields,
    AccountIsImmutable,
    AliasAlreadyAssigned,
    
    // Network errors
    NetworkTimeout,
    ConnectionFailed,
    InvalidNodeSelection,
    NoHealthyNodes,
    RequestTimeout,
    GrpcError,
    
    // Client errors
    ClientNotInitialized,
    InvalidConfiguration,
    MissingPrivateKey,
    MissingOperatorAccountId,
    NoOperatorSet,
    InvalidNetworkName,
    NodeNotFound,
    RequestFailed,
    ClientClosed,
    AllocationFailed,
    
    // Parsing errors
    InvalidProtobuf,
    SerializationFailed,
    DeserializationFailed,
    InvalidChecksum,
    ChecksumMismatch,
    
    // General errors
    InvalidParameter,
    OutOfMemory,
    SystemError,
    UnknownError,
};

// Status code mapping structure
pub const StatusCode = struct {
    code: i32,
    name: []const u8,
    error_value: HederaError,
    
    // Convert numeric status code to error
    pub fn fromCode(code: i32) HederaError {
        return switch (code) {
            0 => HederaError.Ok,
            1 => HederaError.InvalidTransaction,
            2 => HederaError.PayerAccountNotFound,
            3 => HederaError.InvalidNodeAccount,
            4 => HederaError.TransactionExpired,
            5 => HederaError.InvalidTransactionStart,
            6 => HederaError.InvalidTransactionDuration,
            7 => HederaError.InvalidSignature,
            8 => HederaError.MemoTooLong,
            9 => HederaError.InsufficientTxFee,
            10 => HederaError.InsufficientPayerBalance,
            11 => HederaError.DuplicateTransaction,
            12 => HederaError.Busy,
            13 => HederaError.NotSupported,
            14 => HederaError.InvalidFileId,
            15 => HederaError.InvalidAccountId,
            16 => HederaError.InvalidContractId,
            17 => HederaError.InvalidTransactionId,
            18 => HederaError.ReceiptNotFound,
            19 => HederaError.RecordNotFound,
            20 => HederaError.InvalidSolidityId,
            21 => HederaError.Unknown,
            22 => HederaError.Success,
            23 => HederaError.FailInvalid,
            24 => HederaError.FailFee,
            25 => HederaError.FailBalance,
            26 => HederaError.KeyRequired,
            27 => HederaError.BadEncoding,
            28 => HederaError.InsufficientAccountBalance,
            29 => HederaError.InvalidSolidityAddress,
            30 => HederaError.InsufficientGas,
            31 => HederaError.ContractSizeLimitExceeded,
            32 => HederaError.LocalCallModificationException,
            33 => HederaError.ContractRevertExecuted,
            34 => HederaError.ContractExecutionException,
            35 => HederaError.InvalidReceivingNodeAccount,
            36 => HederaError.MissingQueryHeader,
            37 => HederaError.AccountUpdateFailed,
            38 => HederaError.InvalidKeyEncoding,
            39 => HederaError.NullSolidityAddress,
            40 => HederaError.ContractUpdateFailed,
            41 => HederaError.InvalidQueryHeader,
            42 => HederaError.InvalidFeeSubmitted,
            43 => HederaError.InvalidPayerSignature,
            44 => HederaError.KeyNotProvided,
            45 => HederaError.InvalidExpirationTime,
            46 => HederaError.NoWaclKey,
            47 => HederaError.FileContentEmpty,
            48 => HederaError.InvalidAccountAmounts,
            49 => HederaError.EmptyTransactionBody,
            50 => HederaError.InvalidTransactionBody,
            else => HederaError.UnknownError,
        };
    }
    
    // Convert error to numeric status code
    pub fn toCode(err: HederaError) i32 {
        return switch (err) {
            HederaError.Ok => 0,
            HederaError.InvalidTransaction => 1,
            HederaError.PayerAccountNotFound => 2,
            HederaError.InvalidNodeAccount => 3,
            HederaError.TransactionExpired => 4,
            HederaError.InvalidTransactionStart => 5,
            HederaError.InvalidTransactionDuration => 6,
            HederaError.InvalidSignature => 7,
            HederaError.MemoTooLong => 8,
            HederaError.InsufficientTxFee => 9,
            HederaError.InsufficientPayerBalance => 10,
            HederaError.DuplicateTransaction => 11,
            HederaError.Busy => 12,
            HederaError.NotSupported => 13,
            HederaError.InvalidFileId => 14,
            HederaError.InvalidAccountId => 15,
            HederaError.InvalidContractId => 16,
            HederaError.InvalidTransactionId => 17,
            HederaError.ReceiptNotFound => 18,
            HederaError.RecordNotFound => 19,
            HederaError.InvalidSolidityId => 20,
            HederaError.Unknown => 21,
            HederaError.Success => 22,
            HederaError.FailInvalid => 23,
            HederaError.FailFee => 24,
            HederaError.FailBalance => 25,
            HederaError.KeyRequired => 26,
            HederaError.BadEncoding => 27,
            HederaError.InsufficientAccountBalance => 28,
            HederaError.InvalidSolidityAddress => 29,
            HederaError.InsufficientGas => 30,
            HederaError.ContractSizeLimitExceeded => 31,
            HederaError.LocalCallModificationException => 32,
            HederaError.ContractRevertExecuted => 33,
            HederaError.ContractExecutionException => 34,
            HederaError.InvalidReceivingNodeAccount => 35,
            HederaError.MissingQueryHeader => 36,
            HederaError.AccountUpdateFailed => 37,
            HederaError.InvalidKeyEncoding => 38,
            HederaError.NullSolidityAddress => 39,
            HederaError.ContractUpdateFailed => 40,
            HederaError.InvalidQueryHeader => 41,
            HederaError.InvalidFeeSubmitted => 42,
            HederaError.InvalidPayerSignature => 43,
            HederaError.KeyNotProvided => 44,
            HederaError.InvalidExpirationTime => 45,
            HederaError.NoWaclKey => 46,
            HederaError.FileContentEmpty => 47,
            HederaError.InvalidAccountAmounts => 48,
            HederaError.EmptyTransactionBody => 49,
            HederaError.InvalidTransactionBody => 50,
            else => -1,
        };
    }
    
    // Get human-readable description
    pub fn getDescription(err: HederaError) []const u8 {
        return switch (err) {
            HederaError.Ok => "The transaction succeeded",
            HederaError.InvalidTransaction => "Transaction is invalid",
            HederaError.PayerAccountNotFound => "Payer account does not exist",
            HederaError.InvalidNodeAccount => "Node account provided is not valid",
            HederaError.TransactionExpired => "Transaction has expired",
            HederaError.InvalidTransactionStart => "Transaction start time is invalid",
            HederaError.InvalidTransactionDuration => "Transaction duration is invalid",
            HederaError.InvalidSignature => "Signature verification failed",
            HederaError.MemoTooLong => "Memo exceeds maximum length",
            HederaError.InsufficientTxFee => "Transaction fee is insufficient",
            HederaError.InsufficientPayerBalance => "Payer has insufficient balance",
            HederaError.DuplicateTransaction => "Transaction is a duplicate",
            HederaError.Busy => "Node is busy, try again later",
            HederaError.NotSupported => "Operation is not supported",
            HederaError.InvalidFileId => "File ID is invalid",
            HederaError.InvalidAccountId => "Account ID is invalid",
            HederaError.InvalidContractId => "Contract ID is invalid",
            HederaError.InvalidTransactionId => "Transaction ID is invalid",
            HederaError.ReceiptNotFound => "Receipt not found",
            HederaError.RecordNotFound => "Record not found",
            HederaError.InvalidSolidityId => "Solidity ID is invalid",
            HederaError.Unknown => "Unknown error occurred",
            HederaError.Success => "Operation completed successfully",
            else => "Error description not available",
        };
    }
};

// Combined error type for SDK operations
pub const SdkError = HederaError || std.mem.Allocator.Error || std.posix.SocketError || error{
    SystemResources,
    Unexpected,
};

// Result type for SDK operations
pub fn Result(comptime T: type) type {
    return union(enum) {
        ok: T,
        err: SdkError,
        
        pub fn isOk(self: @This()) bool {
            return switch (self) {
                .ok => true,
                .err => false,
            };
        }
        
        pub fn isErr(self: @This()) bool {
            return !self.isOk();
        }
        
        pub fn unwrap(self: @This()) T {
            return switch (self) {
                .ok => |value| value,
                .err => |e| std.debug.panic("Called unwrap on error result: {}", .{e}),
            };
        }
        
        pub fn unwrapErr(self: @This()) SdkError {
            return switch (self) {
                .ok => std.debug.panic("Called unwrapErr on ok result", .{}),
                .err => |e| e,
            };
        }
        
        pub fn unwrapOr(self: @This(), default: T) T {
            return switch (self) {
                .ok => |value| value,
                .err => default,
            };
        }
    };
}

// Validation helper functions for common parameter checks
pub fn requirePositive(value: i64) HederaError!void {
    if (value <= 0) {
        return HederaError.InvalidParameter;
    }
}

pub fn requireNotZero(value: anytype) HederaError!void {
    if (value == 0) {
        return HederaError.InvalidParameter;
    }
}

pub fn requireValidRange(value: i64, min: i64, max: i64) HederaError!void {
    if (value < min or value > max) {
        return HederaError.InvalidParameter;
    }
}

pub fn requireNotNull(value: anytype) HederaError!void {
    if (value == null) {
        return HederaError.InvalidParameter;
    }
}

pub fn requireValidString(str: []const u8) HederaError!void {
    if (str.len == 0) {
        return HederaError.InvalidParameter;
    }
}

pub fn requireNotFrozen(frozen: bool) HederaError!void {
    if (frozen) {
        return HederaError.TransactionFrozen;
    }
}

pub fn requireMaxLength(str: []const u8, max_len: usize) HederaError!void {
    if (str.len > max_len) {
        return HederaError.InvalidParameter;
    }
}

// Memory allocation error handling
pub fn handleAllocError(allocator: std.mem.Allocator, comptime T: type, size: usize) HederaError![]T {
    return allocator.alloc(T, size) catch return HederaError.OutOfMemory;
}

pub fn handleDupeError(allocator: std.mem.Allocator, slice: anytype) HederaError!@TypeOf(slice) {
    return allocator.dupe(@TypeOf(slice[0]), slice) catch return HederaError.OutOfMemory;
}

pub fn handleAppendError(list: anytype, item: anytype) HederaError!void {
    list.append(item) catch return HederaError.OutOfMemory;
}

pub fn handleAppendSliceError(list: anytype, slice: anytype) HederaError!void {
    list.appendSlice(slice) catch return HederaError.OutOfMemory;
}

pub fn handleInsertSliceError(list: anytype, index: usize, slice: anytype) HederaError!void {
    list.insertSlice(index, slice) catch return HederaError.OutOfMemory;
}

pub fn handleFormatError(allocator: std.mem.Allocator, comptime format: []const u8, args: anytype) HederaError![]u8 {
    return std.fmt.allocPrint(allocator, format, args) catch return HederaError.OutOfMemory;
}

// Helper function to validate string length
pub fn requireStringNotTooLong(str: []const u8, max_len: usize) HederaError!void {
    if (str.len > max_len) {
        return HederaError.MemoTooLong;
    }
}