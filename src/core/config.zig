// Central configuration for Hedera SDK
// Contains all network-specific configurations, file IDs, and system constants

const std = @import("std");
const FileId = @import("id.zig").FileId;
const AccountId = @import("id.zig").AccountId;
const Duration = @import("duration.zig").Duration;
const Hbar = @import("hbar.zig").Hbar;

// Network-specific file IDs for system files
pub const NetworkFiles = struct {
    address_book: FileId,
    node_details: FileId,
    fee_schedule: FileId,
    exchange_rates: FileId,
    throttles: FileId,
    
    pub const mainnet = NetworkFiles{
        .address_book = FileId.init(0, 0, 101),
        .node_details = FileId.init(0, 0, 102),
        .fee_schedule = FileId.init(0, 0, 111),
        .exchange_rates = FileId.init(0, 0, 112),
        .throttles = FileId.init(0, 0, 123),
    };
    
    pub const testnet = NetworkFiles{
        .address_book = FileId.init(0, 0, 101),
        .node_details = FileId.init(0, 0, 102),
        .fee_schedule = FileId.init(0, 0, 111),
        .exchange_rates = FileId.init(0, 0, 112),
        .throttles = FileId.init(0, 0, 123),
    };
    
    pub const previewnet = NetworkFiles{
        .address_book = FileId.init(0, 0, 101),
        .node_details = FileId.init(0, 0, 102),
        .fee_schedule = FileId.init(0, 0, 111),
        .exchange_rates = FileId.init(0, 0, 112),
        .throttles = FileId.init(0, 0, 123),
    };
};

// Well-known system file IDs
pub const SystemFiles = struct {
    pub const ADDRESS_BOOK = FileId.init(0, 0, 101);
    pub const NODE_DETAILS = FileId.init(0, 0, 102);
    pub const FEE_SCHEDULE = FileId.init(0, 0, 111);
    pub const EXCHANGE_RATES = FileId.init(0, 0, 112);
    pub const APPLICATION_PROPERTIES = FileId.init(0, 0, 121);
    pub const API_PERMISSIONS = FileId.init(0, 0, 122);
    pub const THROTTLES = FileId.init(0, 0, 123);
};

// Network-specific configurations
pub const NetworkConfig = struct {
    name: []const u8,
    nodes: []const NodeConfig,
    mirror_nodes: []const MirrorNodeConfig,
    
    pub const mainnet = NetworkConfig{
        .name = "mainnet",
        .nodes = &mainnet_nodes,
        .mirror_nodes = &mainnet_mirror_nodes,
    };
    
    pub const testnet = NetworkConfig{
        .name = "testnet",
        .nodes = &testnet_nodes,
        .mirror_nodes = &testnet_mirror_nodes,
    };
    
    pub const previewnet = NetworkConfig{
        .name = "previewnet",
        .nodes = &previewnet_nodes,
        .mirror_nodes = &previewnet_mirror_nodes,
    };
};

// Node configuration
pub const NodeConfig = struct {
    account_id: AccountId,
    address: []const u8,
    port: u16,
    cert_hash: ?[]const u8 = null,
};

// Mirror node configuration  
pub const MirrorNodeConfig = struct {
    endpoint: []const u8,
    api_version: []const u8 = "v1",
};

// Default transaction parameters
pub const TransactionDefaults = struct {
    pub const MAX_TRANSACTION_FEE = Hbar.fromTinybars(200_000_000) catch unreachable; // 2 HBAR
    pub const TRANSACTION_VALID_DURATION = Duration.fromSeconds(120);
    pub const MAX_MEMO_LENGTH = 100;
    pub const AUTO_RENEW_PERIOD = Duration.fromDays(90);
    pub const MAX_CHUNKS = 20;
    pub const CHUNK_SIZE = 4096; // 4KB chunks for file operations
};

// Query defaults
pub const QueryDefaults = struct {
    pub const MAX_QUERY_PAYMENT = Hbar.fromTinybars(100_000_000) catch unreachable; // 1 HBAR
    pub const QUERY_TIMEOUT = Duration.fromSeconds(30);
    pub const MAX_RETRIES = 3;
};

// Network timeouts
pub const NetworkTimeouts = struct {
    pub const MIN_TIMEOUT = Duration.fromMilliseconds(100);
    pub const DEFAULT_TIMEOUT = Duration.fromSeconds(120);
    pub const MAX_TIMEOUT = Duration.fromMinutes(10);
    pub const GRPC_DEADLINE = Duration.fromSeconds(60);
    pub const REQUEST_TIMEOUT = Duration.fromSeconds(30);
};

// Cryptography settings
pub const CryptoConfig = struct {
    pub const MNEMONIC_WORD_COUNT = 24;
    pub const ED25519_KEY_SIZE = 32;
    pub const ECDSA_KEY_SIZE = 33;
    pub const EVM_ADDRESS_SIZE = 20;
    pub const PRIVATE_KEY_PREFIX = "302e020100300506032b657004220420";
    pub const PUBLIC_KEY_PREFIX_ED25519 = "302a300506032b6570032100";
    pub const PUBLIC_KEY_PREFIX_ECDSA = "302d300706052b8104000a032200";
};

// Token settings
pub const TokenConfig = struct {
    pub const MAX_TOKEN_SYMBOL_LENGTH = 100;
    pub const MAX_TOKEN_NAME_LENGTH = 100;
    pub const MAX_TOKEN_MEMO_LENGTH = 100;
    pub const MAX_DECIMALS = 18;
    pub const MAX_SUPPLY = 9_223_372_036_854_775_807; // Max i64
    pub const MAX_AUTOMATIC_ASSOCIATIONS = 1000;
    pub const MAX_CUSTOM_FEES = 10;
};

// Account settings
pub const AccountConfig = struct {
    pub const MAX_AUTOMATIC_TOKEN_ASSOCIATIONS = 5000;
    pub const DEFAULT_MAX_AUTOMATIC_TOKEN_ASSOCIATIONS = 0;
    pub const MAX_MEMO_LENGTH = 100;
    pub const DEFAULT_RECEIVER_SIG_REQUIRED = false;
    pub const RECEIVER_SIGNATURE_THRESHOLD = Hbar.fromTinybars(9_223_372_036_854_775_807) catch unreachable;
};

// Topic settings  
pub const TopicConfig = struct {
    pub const MAX_MEMO_LENGTH = 100;
    pub const MAX_MESSAGE_SIZE = 1024;
    pub const DEFAULT_AUTO_RENEW_PERIOD = Duration.fromDays(90);
};

// Contract settings
pub const ContractConfig = struct {
    pub const MAX_GAS = 15_000_000;
    pub const DEFAULT_GAS = 100_000;
    pub const MAX_CONSTRUCTOR_PARAMS_SIZE = 4096;
    pub const MAX_CONTRACT_MEMO_LENGTH = 100;
    pub const DEFAULT_AUTO_RENEW_PERIOD = Duration.fromDays(90);
};

// Schedule settings
pub const ScheduleConfig = struct {
    pub const MAX_EXPIRATION_TIME = Duration.fromDays(62); // ~2 months
    pub const MIN_EXPIRATION_TIME = Duration.fromMinutes(1);
    pub const MAX_MEMO_LENGTH = 100;
};

// Network node lists (simplified for core implementation)
const mainnet_nodes = [_]NodeConfig{
    .{ .account_id = AccountId.init(0, 0, 3), .address = "35.237.200.180", .port = 50211 },
    .{ .account_id = AccountId.init(0, 0, 4), .address = "35.186.191.247", .port = 50211 },
    .{ .account_id = AccountId.init(0, 0, 5), .address = "35.192.2.25", .port = 50211 },
    .{ .account_id = AccountId.init(0, 0, 6), .address = "35.199.161.108", .port = 50211 },
    .{ .account_id = AccountId.init(0, 0, 7), .address = "35.203.82.240", .port = 50211 },
};

const testnet_nodes = [_]NodeConfig{
    .{ .account_id = AccountId.init(0, 0, 3), .address = "0.testnet.hedera.com", .port = 50211 },
    .{ .account_id = AccountId.init(0, 0, 4), .address = "1.testnet.hedera.com", .port = 50211 },
    .{ .account_id = AccountId.init(0, 0, 5), .address = "2.testnet.hedera.com", .port = 50211 },
    .{ .account_id = AccountId.init(0, 0, 6), .address = "3.testnet.hedera.com", .port = 50211 },
    .{ .account_id = AccountId.init(0, 0, 7), .address = "4.testnet.hedera.com", .port = 50211 },
};

const previewnet_nodes = [_]NodeConfig{
    .{ .account_id = AccountId.init(0, 0, 3), .address = "0.previewnet.hedera.com", .port = 50211 },
    .{ .account_id = AccountId.init(0, 0, 4), .address = "1.previewnet.hedera.com", .port = 50211 },
    .{ .account_id = AccountId.init(0, 0, 5), .address = "2.previewnet.hedera.com", .port = 50211 },
    .{ .account_id = AccountId.init(0, 0, 6), .address = "3.previewnet.hedera.com", .port = 50211 },
    .{ .account_id = AccountId.init(0, 0, 7), .address = "4.previewnet.hedera.com", .port = 50211 },
};

const mainnet_mirror_nodes = [_]MirrorNodeConfig{
    .{ .endpoint = "mainnet-public.mirrornode.hedera.com" },
    .{ .endpoint = "mainnet.mirrornode.hedera.com" },
};

const testnet_mirror_nodes = [_]MirrorNodeConfig{
    .{ .endpoint = "testnet.mirrornode.hedera.com" },
};

const previewnet_mirror_nodes = [_]MirrorNodeConfig{
    .{ .endpoint = "previewnet.mirrornode.hedera.com" },
};

// Retry configuration
pub const RetryConfig = struct {
    pub const DEFAULT_MAX_ATTEMPTS = 3;
    pub const DEFAULT_MIN_BACKOFF = Duration.fromMilliseconds(100);
    pub const DEFAULT_MAX_BACKOFF = Duration.fromSeconds(10);
    pub const DEFAULT_BACKOFF_MULTIPLIER = 2.0;
    pub const DEFAULT_JITTER = 0.1;
};

// Connection pool configuration
pub const ConnectionPoolConfig = struct {
    pub const DEFAULT_MAX_CONNECTIONS = 10;
    pub const DEFAULT_MIN_CONNECTIONS = 2;
    pub const DEFAULT_MAX_IDLE_TIME = Duration.fromMinutes(5);
    pub const DEFAULT_CONNECTION_TIMEOUT = Duration.fromSeconds(10);
    pub const DEFAULT_KEEP_ALIVE_INTERVAL = Duration.fromSeconds(30);
};

// TLS configuration
pub const TlsConfig = struct {
    pub const ENABLE_TLS = true;
    pub const VERIFY_CERTIFICATES = true;
    pub const MIN_TLS_VERSION = "1.2";
    pub const MAX_TLS_VERSION = "1.3";
};

// Compression configuration
pub const CompressionConfig = struct {
    pub const ENABLE_COMPRESSION = true;
    pub const COMPRESSION_ALGORITHM = "gzip";
    pub const COMPRESSION_LEVEL = 6; // 1-9, where 9 is max compression
    pub const MIN_SIZE_TO_COMPRESS = 1024; // 1KB minimum
};

// Query cache configuration  
pub const QueryCacheConfig = struct {
    pub const ENABLE_CACHE = true;
    pub const MAX_CACHE_SIZE = 100; // Maximum number of cached queries
    pub const DEFAULT_TTL = Duration.fromMinutes(5);
    pub const MAX_TTL = Duration.fromHours(1);
};

// Rate limiting configuration
pub const RateLimitConfig = struct {
    pub const MAX_REQUESTS_PER_SECOND = 100;
    pub const MAX_BURST_SIZE = 200;
    pub const RATE_LIMIT_WINDOW = Duration.fromSeconds(1);
};

// Logging configuration
pub const LogConfig = struct {
    pub const LOG_LEVEL = "info"; // debug, info, warn, error
    pub const LOG_FORMAT = "json"; // json, text
    pub const LOG_TO_FILE = false;
    pub const LOG_FILE_PATH = "/var/log/hedera-sdk.log";
    pub const MAX_LOG_SIZE_MB = 100;
    pub const LOG_ROTATION_COUNT = 10;
};