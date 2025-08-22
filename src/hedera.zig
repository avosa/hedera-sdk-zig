// Hedera SDK for Zig - Main entry point
// Complete implementation matching Hedera Go SDK functionality

const std = @import("std");

// Core types
pub const errors = @import("core/errors.zig");
pub const HederaError = errors.HederaError;
pub const Status = @import("core/status.zig").Status;
pub const StatusCode = errors.StatusCode;
pub const SdkError = errors.SdkError;
pub const Result = errors.Result;

pub const Hbar = @import("core/hbar.zig").Hbar;
pub const HbarUnit = @import("core/hbar.zig").HbarUnit;
pub const Timestamp = @import("core/timestamp.zig").Timestamp;
pub const Duration = @import("core/duration.zig").Duration;
pub const TransactionId = @import("core/transaction_id.zig").TransactionId;

// ID types
pub const AccountId = @import("core/id.zig").AccountId;
pub const ContractId = @import("core/id.zig").ContractId;
pub const FileId = @import("core/id.zig").FileId;
pub const TokenId = @import("core/id.zig").TokenId;
pub const TopicId = @import("core/id.zig").TopicId;
pub const ScheduleId = @import("core/id.zig").ScheduleId;
pub const NftId = @import("core/id.zig").NftId;

// Cryptography
pub const PrivateKey = @import("crypto/private_key.zig").PrivateKey;
pub const PublicKey = @import("crypto/key.zig").PublicKey;
pub const Key = @import("crypto/key.zig").Key;
pub const KeyList = @import("crypto/key.zig").KeyList;
pub const ThresholdKey = @import("crypto/key.zig").ThresholdKey;
pub const Ed25519PrivateKey = @import("crypto/key.zig").Ed25519PrivateKey;
pub const Ed25519PublicKey = @import("crypto/key.zig").Ed25519PublicKey;
pub const EcdsaSecp256k1PrivateKey = @import("crypto/key.zig").EcdsaSecp256k1PrivateKey;
pub const EcdsaSecp256k1PublicKey = @import("crypto/key.zig").EcdsaSecp256k1PublicKey;
pub const Mnemonic = @import("crypto/mnemonic.zig").Mnemonic;

// Network
pub const Client = @import("network/client.zig").Client;
pub const Node = @import("network/node.zig").Node;
pub const Network = @import("network/network.zig").Network;
// These will be replaced by the more complete versions below

// Factory functions matching Hedera SDK patterns
pub const clientForName = @import("network/client.zig").Client.clientForName;
pub const accountIdFromString = @import("core/id.zig").AccountId.accountIdFromString;
pub const privateKeyFromString = @import("crypto/private_key.zig").PrivateKey.privateKeyFromString;
pub const generatePrivateKey = @import("crypto/private_key.zig").PrivateKey.generatePrivateKey;

// Transaction factory functions - matching Hedera SDK naming patterns
pub const newAccountCreateTransaction = @import("account/account_create.zig").newAccountCreateTransaction;
pub const newAccountDeleteTransaction = @import("account/account_delete.zig").newAccountDeleteTransaction;
pub const newTokenCreateTransaction = @import("token/token_create.zig").newTokenCreateTransaction;
pub const newTokenUpdateTransaction = @import("token/token_update.zig").newTokenUpdateTransaction;
pub const newTokenDeleteTransaction = @import("token/token_delete.zig").newTokenDeleteTransaction;
pub const newTopicCreateTransaction = @import("topic/topic_create.zig").newTopicCreateTransaction;
pub const newTopicUpdateTransaction = @import("topic/topic_update.zig").newTopicUpdateTransaction;
pub const newTopicDeleteTransaction = @import("topic/topic_delete.zig").newTopicDeleteTransaction;
pub const newContractCreateTransaction = @import("contract/contract_create.zig").newContractCreateTransaction;
pub const newContractUpdateTransaction = @import("contract/contract_update_transaction.zig").newContractUpdateTransaction;
pub const newContractDeleteTransaction = @import("contract/contract_delete.zig").newContractDeleteTransaction;
pub const newFileCreateTransaction = @import("file/file_create.zig").newFileCreateTransaction;
pub const newFileUpdateTransaction = @import("file/file_update_transaction.zig").newFileUpdateTransaction;
pub const newFileDeleteTransaction = @import("file/file_delete.zig").newFileDeleteTransaction;
pub const newTransferTransaction = @import("transfer/transfer_transaction.zig").newTransferTransaction;

// Transaction base
pub const Transaction = @import("transaction/transaction.zig").Transaction;
pub const TransactionResponse = @import("transaction/transaction_response.zig").TransactionResponse;
pub const SignatureMap = @import("transaction/transaction.zig").SignatureMap;

// NEW Batch Transaction - PERFORMANCE CRITICAL
pub const BatchTransaction = @import("transaction/batch_transaction.zig").BatchTransaction;

// NEW Node Management - NETWORK ADMIN
pub const NodeCreateTransaction = @import("node/node_create_transaction.zig").NodeCreateTransaction;
// ServiceEndpoint is defined below in managed_node.zig

// NEW LiveHash operations - CRYPTOGRAPHIC PROOF
pub const LiveHashAddTransaction = @import("crypto/live_hash.zig").LiveHashAddTransaction;
pub const LiveHashDeleteTransaction = @import("crypto/live_hash.zig").LiveHashDeleteTransaction;
pub const LiveHash = @import("crypto/live_hash.zig").LiveHash;

// Query base
pub const Query = @import("query/query.zig").Query;
pub const QueryResponse = @import("query/query.zig").QueryResponse;

// Account operations
pub const AccountCreateTransaction = @import("account/account_create.zig").AccountCreateTransaction;
pub const AccountUpdateTransaction = @import("account/account_update.zig").AccountUpdateTransaction;
pub const AccountDeleteTransaction = @import("account/account_delete.zig").AccountDeleteTransaction;
pub const AccountBalanceQuery = @import("account/account_balance_query.zig").AccountBalanceQuery;
pub const AccountInfoQuery = @import("account/account_info_query.zig").AccountInfoQuery;
pub const AccountStakingInfo = @import("account/account_info_query.zig").StakingInfo;
pub const AccountRecordsQuery = @import("account/account_records_query.zig").AccountRecordsQuery;
pub const AccountBalance = @import("account/account_balance_query.zig").AccountBalance;
pub const AccountInfo = @import("account/account_info_query.zig").AccountInfo;
pub const AccountStakersQuery = @import("account/account_stakers_query.zig").AccountStakersQuery;
pub const AccountStakers = @import("account/account_stakers_query.zig").AccountStakers;
pub const AccountRecords = @import("account/account_records.zig").AccountRecords;

// NEW Account Allowance operations - HIP-336 CRITICAL
pub const AccountAllowanceApproveTransaction = @import("account/account_allowance_approve_transaction.zig").AccountAllowanceApproveTransaction;
pub const AccountAllowanceDeleteTransaction = @import("account/account_allowance_delete_transaction.zig").AccountAllowanceDeleteTransaction;
pub const HbarAllowance = @import("account/account_allowance_approve_transaction.zig").HbarAllowance;
pub const TokenAllowance = @import("account/account_allowance_approve_transaction.zig").TokenAllowance;
pub const NftAllowance = @import("account/account_allowance_approve_transaction.zig").NftAllowance;

// Transfer operations
pub const TransferTransaction = @import("transfer/transfer_transaction.zig").TransferTransaction;
pub const Transfer = @import("transfer/transfer.zig").Transfer;
pub const TokenTransfer = @import("transfer/transfer.zig").TokenTransfer;
pub const AccountAmount = @import("transfer/transfer_transaction.zig").AccountAmount;
pub const NftTransfer = @import("transfer/transfer_transaction.zig").NftTransfer;

// Token operations
pub const TokenCreateTransaction = @import("token/token_create.zig").TokenCreateTransaction;
pub const TokenAssociateTransaction = @import("token/token_associate.zig").TokenAssociateTransaction;
pub const TokenDissociateTransaction = @import("token/token_dissociate.zig").TokenDissociateTransaction;
pub const TokenMintTransaction = @import("token/token_mint.zig").TokenMintTransaction;
pub const TokenBurnTransaction = @import("token/token_burn.zig").TokenBurnTransaction;
pub const TokenFreezeTransaction = @import("token/token_freeze.zig").TokenFreezeTransaction;
pub const TokenUnfreezeTransaction = @import("token/token_unfreeze.zig").TokenUnfreezeTransaction;
pub const TokenGrantKycTransaction = @import("token/token_grant_kyc.zig").TokenGrantKycTransaction;
pub const TokenRevokeKycTransaction = @import("token/token_revoke_kyc.zig").TokenRevokeKycTransaction;
pub const TokenWipeTransaction = @import("token/token_wipe.zig").TokenWipeTransaction;
pub const TokenUpdateTransaction = @import("token/token_update.zig").TokenUpdateTransaction;
pub const TokenDeleteTransaction = @import("token/token_delete.zig").TokenDeleteTransaction;
pub const TokenPauseTransaction = @import("token/token_pause.zig").TokenPauseTransaction;
pub const TokenUnpauseTransaction = @import("token/token_unpause.zig").TokenUnpauseTransaction;
pub const TokenFeeScheduleUpdateTransaction = @import("token/token_fee_schedule_update.zig").TokenFeeScheduleUpdateTransaction;
pub const TokenInfoQuery = @import("token/token_info_query.zig").TokenInfoQuery;
pub const TokenBalanceQuery = @import("token/token_balance_query.zig").TokenBalanceQuery;
pub const TokenBalance = @import("token/token_balance_query.zig").TokenBalance;
pub const TokenInfo = @import("token/token_info_query.zig").TokenInfo;
pub const TokenNftInfoQuery = @import("token/token_nft_info_query.zig").TokenNftInfoQuery;
pub const TokenNftInfo = @import("token/token_nft_info_query.zig").TokenNftInfo;
pub const TokenType = @import("token/token_create.zig").TokenType;
pub const TokenSupplyType = @import("token/token_create.zig").TokenSupplyType;
pub const CustomFee = @import("token/token_create.zig").CustomFee;
pub const TokenRelationship = @import("token/token_info_query.zig").TokenRelationship;
pub const TokenKycStatus = @import("token/token_info_query.zig").TokenKycStatus;
pub const TokenFreezeStatus = @import("token/token_info_query.zig").TokenFreezeStatus;
pub const TokenPauseStatus = @import("token/token_info_query.zig").TokenPauseStatus;

// Token Balance and Decimal Maps
pub const TokenBalanceMap = @import("token/token_balance_map.zig").TokenBalanceMap;
pub const TokenDecimalMap = @import("token/token_decimal_map.zig").TokenDecimalMap;

// Custom Fee Components - All 4 types
pub const CustomFixedFee = @import("token/custom_fixed_fee.zig").CustomFixedFee;
pub const CustomFractionalFee = @import("token/custom_fractional_fee.zig").CustomFractionalFee;
pub const CustomRoyaltyFee = @import("token/custom_royalty_fee.zig").CustomRoyaltyFee;
pub const CustomFeeList = @import("token/custom_fee.zig").CustomFeeList;

// NFT Info Query
pub const TokenNftInfosQuery = @import("token/token_nft_infos_query.zig").TokenNftInfosQuery;
pub const TokenGetAccountNftInfosQuery = @import("token/token_nft_infos_query.zig").TokenGetAccountNftInfosQuery;

// NEW Token Airdrop operations - HIP-904 CRITICAL
pub const TokenAirdropTransaction = @import("token/token_airdrop_transaction.zig").TokenAirdropTransaction;
pub const TokenCancelAirdropTransaction = @import("token/token_cancel_airdrop_transaction.zig").TokenCancelAirdropTransaction;
pub const TokenClaimAirdropTransaction = @import("token/token_claim_airdrop_transaction.zig").TokenClaimAirdropTransaction;
pub const TokenRejectTransaction = @import("token/token_reject_transaction.zig").TokenRejectTransaction;
pub const TokenUpdateNftsTransaction = @import("token/token_update_nfts_transaction.zig").TokenUpdateNftsTransaction;
pub const PendingAirdropId = @import("token/token_cancel_airdrop_transaction.zig").PendingAirdropId;
pub const TokenReference = @import("token/token_reject_transaction.zig").TokenReference;

// Smart contract operations
pub const ContractCreateTransaction = @import("contract/contract_create.zig").ContractCreateTransaction;
pub const ContractExecuteTransaction = @import("contract/contract_execute.zig").ContractExecuteTransaction;
pub const ContractUpdateTransaction = @import("contract/contract_update_transaction.zig").ContractUpdateTransaction;
pub const ContractDeleteTransaction = @import("contract/contract_delete.zig").ContractDeleteTransaction;
pub const ContractCallQuery = @import("contract/contract_call_query.zig").ContractCallQuery;
pub const ContractInfoQuery = @import("contract/contract_info_query.zig").ContractInfoQuery;
pub const ContractInfo = @import("contract/contract_info_query.zig").ContractInfo;
pub const ContractBytecodeQuery = @import("contract/contract_bytecode_query.zig").ContractBytecodeQuery;
pub const ContractBytecode = @import("contract/contract_bytecode_query.zig").ContractBytecode;
pub const ContractFunctionParameters = @import("contract/contract_execute.zig").ContractFunctionParameters;
pub const ContractFunctionResult = @import("contract/contract_execute.zig").ContractFunctionResult;

// Contract Function Selector and Parameters
pub const FunctionSelector = @import("contract/function_selector.zig").FunctionSelector;
pub const FunctionParameters = @import("contract/function_selector.zig").FunctionParameters;
pub const ContractFunctionCall = @import("contract/function_selector.zig").ContractFunctionCall;

// Contract Log Info and State Changes
pub const ContractLogInfoList = @import("contract/contract_log_info.zig").ContractLogInfoList;
pub const ContractStateChange = @import("contract/contract_log_info.zig").ContractStateChange;
pub const StorageChange = @import("contract/contract_log_info.zig").StorageChange;

// Topic operations (Consensus Service)
pub const TopicCreateTransaction = @import("topic/topic_create.zig").TopicCreateTransaction;
pub const TopicMessageSubmitTransaction = @import("topic/topic_message_submit.zig").TopicMessageSubmitTransaction;
pub const TopicUpdateTransaction = @import("topic/topic_update.zig").TopicUpdateTransaction;
pub const TopicDeleteTransaction = @import("topic/topic_delete.zig").TopicDeleteTransaction;
pub const TopicInfoQuery = @import("topic/topic_info_query.zig").TopicInfoQuery;
pub const TopicInfo = @import("topic/topic_info_query.zig").TopicInfo;
pub const TopicMessageQuery = @import("topic/topic_message_query.zig").TopicMessageQuery;
pub const TopicMessage = @import("topic/topic_message_query.zig").TopicMessage;
pub const ChunkInfo = @import("topic/topic_message_query.zig").ChunkInfo;

pub const ScheduleInfoQuery = @import("schedule/schedule_info_query.zig").ScheduleInfoQuery;
pub const ScheduleInfo = @import("schedule/schedule_info_query.zig").ScheduleInfo;

// File service operations
pub const FileCreateTransaction = @import("file/file_create.zig").FileCreateTransaction;
pub const FileAppendTransaction = @import("file/file_append.zig").FileAppendTransaction;
pub const FileDeleteTransaction = @import("file/file_delete.zig").FileDeleteTransaction;
pub const FileUpdateTransaction = @import("file/file_update_transaction.zig").FileUpdateTransaction;
pub const FileInfoQuery = @import("file/file_info_query.zig").FileInfoQuery;
pub const FileInfo = @import("file/file_info_query.zig").FileInfo;
pub const FileContentsQuery = @import("file/file_contents_query.zig").FileContentsQuery;
pub const FileContents = @import("file/file_contents_query.zig").FileContents;
pub const FileContentsResponse = @import("file/file_contents_response.zig").FileContentsResponse;

// Freeze operations
pub const FreezeTransaction = @import("freeze/freeze_transaction.zig").FreezeTransaction;
pub const FreezeType = @import("freeze/freeze_transaction.zig").FreezeType;

// System operations

// Network operations
pub const NetworkVersionInfoQuery = @import("network/network_version_info_query.zig").NetworkVersionInfoQuery;
pub const NetworkVersionInfo = @import("network/network_version_info_query.zig").NetworkVersionInfo;
pub const SemanticVersion = @import("network/network_version_info_query.zig").SemanticVersion;
pub const NetworkGetExecutionTimeQuery = @import("network/network_status_query.zig").NetworkGetExecutionTimeQuery;
pub const NetworkExecutionTimes = @import("network/network_status_query.zig").NetworkExecutionTimes;
pub const TransactionExecutionTime = @import("network/network_status_query.zig").TransactionExecutionTime;
pub const NetworkManager = @import("network/network_manager.zig").NetworkManager;
pub const HealthCheckResults = @import("network/network_manager.zig").HealthCheckResults;
pub const NetworkStats = @import("network/network_manager.zig").NetworkStats;

// Receipt and records
pub const TransactionReceipt = @import("transaction/transaction_receipt.zig").TransactionReceipt;
pub const TransactionReceiptQuery = @import("query/receipt_query.zig").TransactionReceiptQuery;
pub const TransactionRecord = @import("transaction/transaction_record.zig").TransactionRecord;
pub const TransactionRecordQuery = @import("query/transaction_record_query.zig").TransactionRecordQuery;

// Live hash operations (LiveHashAddTransaction, LiveHashDeleteTransaction and LiveHash already exported above)
pub const LiveHashQuery = @import("crypto/live_hash_query.zig").LiveHashQuery;

// Ethereum operations
pub const EthereumTransaction = @import("ethereum/ethereum_transaction.zig").EthereumTransaction;
pub const EthereumTransactionData = @import("ethereum/ethereum_transaction.zig").EthereumTransactionData;
pub const EthereumEip1559Transaction = @import("ethereum/ethereum_eip1559_transaction.zig").EthereumEip1559Transaction;
pub const EthereumEip2930Transaction = @import("ethereum/ethereum_eip2930_transaction.zig").EthereumEip2930Transaction;
pub const EthereumLegacyTransaction = @import("ethereum/ethereum_legacy_transaction.zig").EthereumLegacyTransaction;

// Schedule operations
pub const ScheduleCreateTransaction = @import("schedule/schedule_create_transaction.zig").ScheduleCreateTransaction;
pub const ScheduleDeleteTransaction = @import("schedule/schedule_delete_transaction.zig").ScheduleDeleteTransaction;
pub const ScheduleSignTransaction = @import("schedule/schedule_sign_transaction.zig").ScheduleSignTransaction;
pub const ScheduleCreateResponse = @import("schedule/schedule_create_response.zig").ScheduleCreateResponse;

// System operations
pub const SystemDeleteTransaction = @import("system/system_delete_transaction.zig").SystemDeleteTransaction;
pub const SystemUndeleteTransaction = @import("system/system_undelete_transaction.zig").SystemUndeleteTransaction;

// Flows
pub const ContractCreateFlow = @import("flow/contract_create_flow.zig").ContractCreateFlow;
pub const TokenRejectFlow = @import("flow/token_reject_flow.zig").TokenRejectFlow;
pub const EthereumFlow = @import("flow/ethereum_flow.zig").EthereumFlow;
pub const AccountInfoFlow = @import("flow/account_info_flow.zig").AccountInfoFlow;
pub const CompleteAccountInfo = @import("flow/account_info_flow.zig").CompleteAccountInfo;
pub const AccountSummary = @import("flow/account_info_flow.zig").AccountSummary;

// Utility operations
pub const PrngTransaction = @import("utils/prng_transaction.zig").PrngTransaction;
pub const ReceiptValidator = @import("utils/receipt_validator.zig").ReceiptValidator;
pub const ValidationResult = @import("utils/receipt_validator.zig").ValidationResult;
pub const BatchValidationResult = @import("utils/receipt_validator.zig").BatchValidationResult;
pub const ValidationIssue = @import("utils/receipt_validator.zig").ValidationIssue;

// Protobuf encoding/decoding
pub const ProtoWriter = @import("protobuf/encoding.zig").ProtoWriter;
pub const ProtoReader = @import("protobuf/encoding.zig").ProtoReader;

// Smart Contract ABI
pub const ABI = @import("contract/abi.zig").ABI;
pub const ContractAbi = @import("contract/contract_abi.zig").ContractAbi;
pub const ContractCallResult = @import("contract/contract_call_result.zig").ContractCallResult;
pub const ContractLogInfo = @import("contract/contract_call_result.zig").ContractLogInfo;

// Mirror Node
pub const MirrorNodeClient = @import("mirror/mirror_node_client.zig").MirrorNodeClient;

// Network
pub const AddressBookQuery = @import("network/address_book_query.zig").AddressBookQuery;
pub const NodeAddressBook = @import("network/address_book_query.zig").NodeAddressBook;

// gRPC
pub const GrpcClient = @import("grpc/grpc_client.zig").GrpcClient;
pub const HPACK = @import("grpc/hpack.zig").HPACK;

// Ethereum
pub const RLP = @import("ethereum/rlp.zig").RLP;

// Cryptography utilities
pub const PBKDF2 = @import("crypto/pbkdf2.zig");

// Staking Components
pub const ProxyStaker = @import("staking/proxy_staker.zig").ProxyStaker;
pub const StakingInfo = @import("staking/proxy_staker.zig").StakingInfo;

// Exchange Rate Components
pub const ExchangeRate = @import("core/exchange_rate.zig").ExchangeRate;
pub const ExchangeRates = @import("core/exchange_rate.zig").ExchangeRates;

// Fee Components
pub const FeeComponents = @import("core/fee_components.zig").FeeComponents;
pub const FeeData = @import("core/fee_components.zig").FeeData;
pub const FeeSchedule = @import("core/fee_components.zig").FeeSchedule;

// Network Identification
pub const LedgerId = @import("core/ledger_id.zig").LedgerId;
pub const NetworkName = @import("core/ledger_id.zig").NetworkName;
pub const NetworkEndpoint = @import("core/ledger_id.zig").NetworkEndpoint;

// Advanced Network Management
pub const ManagedNode = @import("network/managed_node.zig").ManagedNode;
pub const ManagedNetwork = @import("network/managed_network.zig").ManagedNetwork;
pub const NodeHealth = @import("network/managed_node.zig").NodeHealth;
pub const NodeStats = @import("network/managed_node.zig").NodeStats;
pub const NodeAddress = @import("network/managed_node.zig").NodeAddress;
pub const NodeInfo = @import("network/managed_node.zig").NodeInfo;
pub const NetworkConfig = @import("network/managed_network.zig").NetworkConfig;
pub const LoadBalancingStrategy = @import("network/managed_network.zig").LoadBalancingStrategy;
pub const ManagedNetworkStats = @import("network/managed_network.zig").NetworkStats;
pub const ServiceEndpoint = @import("network/managed_node.zig").ServiceEndpoint;

// Address book and mirror network
pub const AddressBook = @import("network/address_book.zig").AddressBook;
pub const MirrorNetwork = @import("network/mirror_network.zig").MirrorNetwork;

// gRPC and Network types for testing
pub const GrpcChannel = @import("network/grpc_channel.zig").GrpcChannel;
pub const RetryConfig = @import("network/retry_config.zig").RetryConfig;
pub const Request = @import("network/request.zig").Request;
pub const Response = @import("network/request.zig").Response;
pub const RequestType = @import("network/request.zig").RequestType;
pub const ResponseType = @import("network/request.zig").ResponseType;
pub const LoadBalancer = @import("network/load_balancer.zig").LoadBalancer;
pub const TlsConfig = @import("network/tls_config.zig").TlsConfig;

// Version information
pub const SDK_VERSION = "1.0.0";
pub const SUPPORTED_HEDERA_VERSION = "0.50.0";

// SDK initialization
pub fn init() void {
    // Perform any necessary SDK initialization
    // Currently no global initialization required
}

// SDK cleanup
pub fn deinit() void {
    // Perform any necessary SDK cleanup
    // Currently no global cleanup required
}

test "Hedera SDK basic initialization" {
    const testing = std.testing;
    
    // Test that we can create basic types
    const account = AccountId.init(0, 0, 3);
    try testing.expectEqual(@as(u64, 0), account.shard);
    try testing.expectEqual(@as(u64, 0), account.realm);
    try testing.expectEqual(@as(u64, 3), account.account);
    
    // Test Hbar creation
    const amount = try Hbar.from(100);
    try testing.expectEqual(@as(i64, 10_000_000_000), amount.toTinybars());
    
    // Test TransactionId generation
    const tx_id = TransactionId.generate(account);
    try testing.expect(tx_id.isValid());
    try testing.expect(tx_id.account_id.equals(account));
}

test "Hedera SDK error handling" {
    const testing = std.testing;
    
    // Test error conversion
    const err = StatusCode.fromCode(7);
    try testing.expectEqual(HederaError.InvalidSignature, err);
    
    // Test error description
    const desc = StatusCode.getDescription(HederaError.InsufficientTxFee);
    try testing.expect(desc.len > 0);
}

test "Hedera SDK cryptography" {
    const testing = std.testing;
    
    // Test ED25519 key generation
    const ed_key = try Ed25519PrivateKey.generate();
    const pub_key = ed_key.getPublicKey();
    
    // Test signing
    const message = "Hello Hedera";
    const signature = try ed_key.sign(message);
    try testing.expectEqual(@as(usize, 64), signature.len);
    
    // Test verification
    const valid = pub_key.verify(message, &signature);
    try testing.expect(valid);
}