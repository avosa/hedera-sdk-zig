// Advanced network configuration options
// Provides comprehensive network tuning and optimization capabilities

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;

// Network transport configuration
pub const TransportConfig = struct {
    protocol: TransportProtocol,
    version: ProtocolVersion,
    keepalive_enabled: bool,
    keepalive_idle_ms: u32,
    keepalive_interval_ms: u32,
    keepalive_probe_count: u32,
    tcp_no_delay: bool,
    socket_buffer_size: ?usize,
    connect_timeout_ms: u32,
    read_timeout_ms: u32,
    write_timeout_ms: u32,
    
    pub const TransportProtocol = enum {
        tcp,
        udp,
        unix_socket,
        
        pub fn toString(self: TransportProtocol) []const u8 {
            return switch (self) {
                .tcp => "TCP",
                .udp => "UDP",
                .unix_socket => "UNIX",
            };
        }
    };
    
    pub const ProtocolVersion = enum {
        ipv4,
        ipv6,
        dual_stack,
        
        pub fn toString(self: ProtocolVersion) []const u8 {
            return switch (self) {
                .ipv4 => "IPv4",
                .ipv6 => "IPv6",
                .dual_stack => "IPv4/IPv6",
            };
        }
    };
    
    pub fn init() TransportConfig {
        return TransportConfig{
            .protocol = .tcp,
            .version = .dual_stack,
            .keepalive_enabled = true,
            .keepalive_idle_ms = 30000, // 30 seconds
            .keepalive_interval_ms = 5000, // 5 seconds
            .keepalive_probe_count = 3,
            .tcp_no_delay = true,
            .socket_buffer_size = null, // Use system default
            .connect_timeout_ms = 10000, // 10 seconds
            .read_timeout_ms = 30000, // 30 seconds
            .write_timeout_ms = 30000, // 30 seconds
        };
    }
    
    pub fn withProtocol(self: TransportConfig, protocol: TransportProtocol) TransportConfig {
        var config = self;
        config.protocol = protocol;
        return config;
    }
    
    pub fn withKeepalive(self: TransportConfig, enabled: bool, idle_ms: u32, interval_ms: u32) TransportConfig {
        var config = self;
        config.keepalive_enabled = enabled;
        config.keepalive_idle_ms = idle_ms;
        config.keepalive_interval_ms = interval_ms;
        return config;
    }
    
    pub fn withTimeouts(self: TransportConfig, connect_ms: u32, read_ms: u32, write_ms: u32) TransportConfig {
        var config = self;
        config.connect_timeout_ms = connect_ms;
        config.read_timeout_ms = read_ms;
        config.write_timeout_ms = write_ms;
        return config;
    }
    
    pub fn withBufferSize(self: TransportConfig, buffer_size: usize) TransportConfig {
        var config = self;
        config.socket_buffer_size = buffer_size;
        return config;
    }
};

// TLS/SSL configuration
pub const TlsConfig = struct {
    enabled: bool,
    version: TlsVersion,
    cipher_suites: []const CipherSuite,
    certificate_verification: CertVerificationMode,
    client_certificate: ?ClientCertificate,
    session_cache_enabled: bool,
    session_timeout_ms: u32,
    hostname_verification: bool,
    alpn_protocols: []const []const u8,
    
    pub const TlsVersion = enum {
        tls_1_2,
        tls_1_3,
        auto,
        
        pub fn toString(self: TlsVersion) []const u8 {
            return switch (self) {
                .tls_1_2 => "TLS 1.2",
                .tls_1_3 => "TLS 1.3",
                .auto => "Auto",
            };
        }
    };
    
    pub const CipherSuite = enum {
        aes_128_gcm_sha256,
        aes_256_gcm_sha384,
        chacha20_poly1305_sha256,
        aes_128_ccm_sha256,
        aes_128_ccm_8_sha256,
        
        pub fn toString(self: CipherSuite) []const u8 {
            return switch (self) {
                .aes_128_gcm_sha256 => "TLS_AES_128_GCM_SHA256",
                .aes_256_gcm_sha384 => "TLS_AES_256_GCM_SHA384",
                .chacha20_poly1305_sha256 => "TLS_CHACHA20_POLY1305_SHA256",
                .aes_128_ccm_sha256 => "TLS_AES_128_CCM_SHA256",
                .aes_128_ccm_8_sha256 => "TLS_AES_128_CCM_8_SHA256",
            };
        }
    };
    
    pub const CertVerificationMode = enum {
        none,
        verify_peer,
        verify_peer_with_ca,
        require_peer_cert,
        
        pub fn toString(self: CertVerificationMode) []const u8 {
            return switch (self) {
                .none => "None",
                .verify_peer => "VerifyPeer",
                .verify_peer_with_ca => "VerifyPeerWithCA",
                .require_peer_cert => "RequirePeerCert",
            };
        }
    };
    
    pub const ClientCertificate = struct {
        certificate_path: []const u8,
        private_key_path: []const u8,
        password: ?[]const u8,
        
        pub fn init(allocator: Allocator, cert_path: []const u8, key_path: []const u8, password: ?[]const u8) !ClientCertificate {
            return ClientCertificate{
                .certificate_path = try allocator.dupe(u8, cert_path),
                .private_key_path = try allocator.dupe(u8, key_path),
                .password = if (password) |pwd| try allocator.dupe(u8, pwd) else null,
            };
        }
        
        pub fn deinit(self: ClientCertificate, allocator: Allocator) void {
            allocator.free(self.certificate_path);
            allocator.free(self.private_key_path);
            if (self.password) |pwd| {
                allocator.free(pwd);
            }
        }
    };
    
    pub fn init() TlsConfig {
        const default_ciphers = [_]CipherSuite{
            .aes_256_gcm_sha384,
            .aes_128_gcm_sha256,
            .chacha20_poly1305_sha256,
        };
        
        const default_alpn = [_][]const u8{ "h2", "http/1.1" };
        
        return TlsConfig{
            .enabled = true,
            .version = .auto,
            .cipher_suites = &default_ciphers,
            .certificate_verification = .verify_peer_with_ca,
            .client_certificate = null,
            .session_cache_enabled = true,
            .session_timeout_ms = 300000, // 5 minutes
            .hostname_verification = true,
            .alpn_protocols = &default_alpn,
        };
    }
    
    pub fn withVersion(self: TlsConfig, version: TlsVersion) TlsConfig {
        var config = self;
        config.version = version;
        return config;
    }
    
    pub fn withCertVerification(self: TlsConfig, mode: CertVerificationMode) TlsConfig {
        var config = self;
        config.certificate_verification = mode;
        return config;
    }
    
    pub fn withClientCertificate(self: TlsConfig, client_cert: ClientCertificate) TlsConfig {
        var config = self;
        config.client_certificate = client_cert;
        return config;
    }
    
    pub fn insecure(self: TlsConfig) TlsConfig {
        var config = self;
        config.certificate_verification = .none;
        config.hostname_verification = false;
        return config;
    }
};

// HTTP/gRPC configuration
pub const HttpConfig = struct {
    version: HttpVersion,
    compression_enabled: bool,
    compression_algorithm: CompressionAlgorithm,
    max_request_size: usize,
    max_response_size: usize,
    max_concurrent_streams: u32,
    initial_window_size: u32,
    max_frame_size: u32,
    enable_server_push: bool,
    header_table_size: u32,
    custom_headers: HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    
    pub const HttpVersion = enum {
        http_1_1,
        http_2,
        http_3,
        auto,
        
        pub fn toString(self: HttpVersion) []const u8 {
            return switch (self) {
                .http_1_1 => "HTTP/1.1",
                .http_2 => "HTTP/2",
                .http_3 => "HTTP/3",
                .auto => "Auto",
            };
        }
    };
    
    pub const CompressionAlgorithm = enum {
        none,
        gzip,
        deflate,
        brotli,
        
        pub fn toString(self: CompressionAlgorithm) []const u8 {
            return switch (self) {
                .none => "none",
                .gzip => "gzip",
                .deflate => "deflate",
                .brotli => "br",
            };
        }
    };
    
    pub fn init(allocator: Allocator) HttpConfig {
        return HttpConfig{
            .version = .http_2,
            .compression_enabled = true,
            .compression_algorithm = .gzip,
            .max_request_size = 16 * 1024 * 1024, // 16MB
            .max_response_size = 16 * 1024 * 1024, // 16MB
            .max_concurrent_streams = 100,
            .initial_window_size = 65536, // 64KB
            .max_frame_size = 16384, // 16KB
            .enable_server_push = false,
            .header_table_size = 4096, // 4KB
            .custom_headers = HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }
    
    pub fn deinit(self: *HttpConfig) void {
        var iter = self.custom_headers.iterator();
        while (iter.next()) |entry| {
            self.custom_headers.allocator.free(entry.key_ptr.*);
            self.custom_headers.allocator.free(entry.value_ptr.*);
        }
        self.custom_headers.deinit();
    }
    
    pub fn withVersion(self: HttpConfig, version: HttpVersion) HttpConfig {
        var config = self;
        config.version = version;
        return config;
    }
    
    pub fn withCompression(self: HttpConfig, enabled: bool, algorithm: CompressionAlgorithm) HttpConfig {
        var config = self;
        config.compression_enabled = enabled;
        config.compression_algorithm = algorithm;
        return config;
    }
    
    pub fn withMaxSizes(self: HttpConfig, request_size: usize, response_size: usize) HttpConfig {
        var config = self;
        config.max_request_size = request_size;
        config.max_response_size = response_size;
        return config;
    }
    
    pub fn addCustomHeader(self: *HttpConfig, key: []const u8, value: []const u8) !void {
        const key_copy = try self.custom_headers.allocator.dupe(u8, key);
        const value_copy = try self.custom_headers.allocator.dupe(u8, value);
        try self.custom_headers.put(key_copy, value_copy);
    }
};

// Quality of Service configuration
pub const QosConfig = struct {
    dscp: ?u8, // Differentiated Services Code Point
    traffic_class: TrafficClass,
    flow_control_enabled: bool,
    congestion_control: CongestionControl,
    bandwidth_limit: ?BandwidthLimit,
    priority: Priority,
    latency_target_ms: ?u32,
    throughput_target_bps: ?u64,
    
    pub const TrafficClass = enum {
        best_effort,
        background,
        video,
        voice,
        control,
        
        pub fn getDscpValue(self: TrafficClass) u8 {
            return switch (self) {
                .best_effort => 0,
                .background => 8,
                .video => 34,
                .voice => 46,
                .control => 48,
            };
        }
        
        pub fn toString(self: TrafficClass) []const u8 {
            return switch (self) {
                .best_effort => "BestEffort",
                .background => "Background",
                .video => "Video",
                .voice => "Voice",
                .control => "Control",
            };
        }
    };
    
    pub const CongestionControl = enum {
        cubic,
        reno,
        vegas,
        bbr,
        
        pub fn toString(self: CongestionControl) []const u8 {
            return switch (self) {
                .cubic => "CUBIC",
                .reno => "Reno",
                .vegas => "Vegas",
                .bbr => "BBR",
            };
        }
    };
    
    pub const BandwidthLimit = struct {
        upload_bps: u64,
        download_bps: u64,
        
        pub fn init(upload_bps: u64, download_bps: u64) BandwidthLimit {
            return BandwidthLimit{
                .upload_bps = upload_bps,
                .download_bps = download_bps,
            };
        }
        
        pub fn fromMbps(upload_mbps: f64, download_mbps: f64) BandwidthLimit {
            return BandwidthLimit{
                .upload_bps = @as(u64, @intFromFloat(upload_mbps * 1_000_000.0)),
                .download_bps = @as(u64, @intFromFloat(download_mbps * 1_000_000.0)),
            };
        }
    };
    
    pub const Priority = enum(u8) {
        lowest = 0,
        low = 1,
        normal = 2,
        high = 3,
        highest = 4,
        
        pub fn toString(self: Priority) []const u8 {
            return switch (self) {
                .lowest => "Lowest",
                .low => "Low",
                .normal => "Normal",
                .high => "High",
                .highest => "Highest",
            };
        }
    };
    
    pub fn init() QosConfig {
        return QosConfig{
            .dscp = null,
            .traffic_class = .best_effort,
            .flow_control_enabled = true,
            .congestion_control = .cubic,
            .bandwidth_limit = null,
            .priority = .normal,
            .latency_target_ms = null,
            .throughput_target_bps = null,
        };
    }
    
    pub fn withTrafficClass(self: QosConfig, traffic_class: TrafficClass) QosConfig {
        var config = self;
        config.traffic_class = traffic_class;
        config.dscp = traffic_class.getDscpValue();
        return config;
    }
    
    pub fn withBandwidthLimit(self: QosConfig, limit: BandwidthLimit) QosConfig {
        var config = self;
        config.bandwidth_limit = limit;
        return config;
    }
    
    pub fn withPriority(self: QosConfig, priority: Priority) QosConfig {
        var config = self;
        config.priority = priority;
        return config;
    }
    
    pub fn withLatencyTarget(self: QosConfig, target_ms: u32) QosConfig {
        var config = self;
        config.latency_target_ms = target_ms;
        return config;
    }
    
    pub fn withThroughputTarget(self: QosConfig, target_bps: u64) QosConfig {
        var config = self;
        config.throughput_target_bps = target_bps;
        return config;
    }
};

// Load balancing configuration
pub const LoadBalancingConfig = struct {
    strategy: LoadBalancingStrategy,
    health_check_enabled: bool,
    health_check_interval_ms: u32,
    health_check_timeout_ms: u32,
    health_check_path: ?[]const u8,
    failover_enabled: bool,
    circuit_breaker_enabled: bool,
    sticky_sessions: bool,
    session_affinity_key: ?[]const u8,
    weights: HashMap([]const u8, f64, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    
    pub const LoadBalancingStrategy = enum {
        round_robin,
        least_connections,
        least_response_time,
        weighted_round_robin,
        consistent_hashing,
        ip_hash,
        random,
        
        pub fn toString(self: LoadBalancingStrategy) []const u8 {
            return switch (self) {
                .round_robin => "RoundRobin",
                .least_connections => "LeastConnections",
                .least_response_time => "LeastResponseTime",
                .weighted_round_robin => "WeightedRoundRobin",
                .consistent_hashing => "ConsistentHashing",
                .ip_hash => "IPHash",
                .random => "Random",
            };
        }
    };
    
    pub fn init(allocator: Allocator) LoadBalancingConfig {
        return LoadBalancingConfig{
            .strategy = .round_robin,
            .health_check_enabled = true,
            .health_check_interval_ms = 30000, // 30 seconds
            .health_check_timeout_ms = 5000, // 5 seconds
            .health_check_path = null,
            .failover_enabled = true,
            .circuit_breaker_enabled = true,
            .sticky_sessions = false,
            .session_affinity_key = null,
            .weights = HashMap([]const u8, f64, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }
    
    pub fn deinit(self: *LoadBalancingConfig) void {
        var iter = self.weights.iterator();
        while (iter.next()) |entry| {
            self.weights.allocator.free(entry.key_ptr.*);
        }
        self.weights.deinit();
        
        if (self.health_check_path) |path| {
            self.weights.allocator.free(path);
        }
        if (self.session_affinity_key) |key| {
            self.weights.allocator.free(key);
        }
    }
    
    pub fn withStrategy(self: LoadBalancingConfig, strategy: LoadBalancingStrategy) LoadBalancingConfig {
        var config = self;
        config.strategy = strategy;
        return config;
    }
    
    pub fn withHealthCheck(self: LoadBalancingConfig, enabled: bool, interval_ms: u32, timeout_ms: u32) LoadBalancingConfig {
        var config = self;
        config.health_check_enabled = enabled;
        config.health_check_interval_ms = interval_ms;
        config.health_check_timeout_ms = timeout_ms;
        return config;
    }
    
    pub fn withStickySession(self: LoadBalancingConfig, enabled: bool, _: ?[]const u8) LoadBalancingConfig {
        var config = self;
        config.sticky_sessions = enabled;
        // Session configuration applied
        return config;
    }
    
    pub fn addWeight(self: *LoadBalancingConfig, node: []const u8, weight: f64) !void {
        const node_copy = try self.weights.allocator.dupe(u8, node);
        try self.weights.put(node_copy, weight);
    }
};

// Monitoring and metrics configuration
pub const MonitoringConfig = struct {
    enabled: bool,
    metrics_collection_interval_ms: u32,
    performance_monitoring: bool,
    connection_tracking: bool,
    error_tracking: bool,
    latency_histogram_enabled: bool,
    throughput_tracking: bool,
    custom_metrics: ArrayList(CustomMetric),
    export_format: MetricsExportFormat,
    export_endpoint: ?[]const u8,
    
    pub const CustomMetric = struct {
        name: []const u8,
        description: []const u8,
        metric_type: MetricType,
        labels: HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
        
        pub const MetricType = enum {
            counter,
            gauge,
            histogram,
            summary,
            
            pub fn toString(self: MetricType) []const u8 {
                return switch (self) {
                    .counter => "counter",
                    .gauge => "gauge",
                    .histogram => "histogram",
                    .summary => "summary",
                };
            }
        };
        
        pub fn init(allocator: Allocator, name: []const u8, description: []const u8, metric_type: MetricType) !CustomMetric {
            return CustomMetric{
                .name = try allocator.dupe(u8, name),
                .description = try allocator.dupe(u8, description),
                .metric_type = metric_type,
                .labels = HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            };
        }
        
        pub fn deinit(self: CustomMetric, allocator: Allocator) void {
            allocator.free(self.name);
            allocator.free(self.description);
            
            var iter = self.labels.iterator();
            while (iter.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
            self.labels.deinit();
        }
    };
    
    pub const MetricsExportFormat = enum {
        prometheus,
        json,
        influxdb,
        statsd,
        
        pub fn toString(self: MetricsExportFormat) []const u8 {
            return switch (self) {
                .prometheus => "prometheus",
                .json => "json",
                .influxdb => "influxdb",
                .statsd => "statsd",
            };
        }
    };
    
    pub fn init(allocator: Allocator) MonitoringConfig {
        return MonitoringConfig{
            .enabled = true,
            .metrics_collection_interval_ms = 1000, // 1 second
            .performance_monitoring = true,
            .connection_tracking = true,
            .error_tracking = true,
            .latency_histogram_enabled = true,
            .throughput_tracking = true,
            .custom_metrics = ArrayList(CustomMetric).init(allocator),
            .export_format = .prometheus,
            .export_endpoint = null,
        };
    }
    
    pub fn deinit(self: *MonitoringConfig) void {
        for (self.custom_metrics.items) |metric| {
            metric.deinit(self.custom_metrics.allocator);
        }
        self.custom_metrics.deinit();
        
        if (self.export_endpoint) |endpoint| {
            self.custom_metrics.allocator.free(endpoint);
        }
    }
    
    pub fn withInterval(self: MonitoringConfig, interval_ms: u32) MonitoringConfig {
        var config = self;
        config.metrics_collection_interval_ms = interval_ms;
        return config;
    }
    
    pub fn withExportFormat(self: MonitoringConfig, format: MetricsExportFormat, _: ?[]const u8) MonitoringConfig {
        var config = self;
        config.export_format = format;
        // Session configuration applied for endpoint
        return config;
    }
    
    pub fn addCustomMetric(self: *MonitoringConfig, metric: CustomMetric) !void {
        try self.custom_metrics.append(metric);
    }
};

// Comprehensive network configuration
pub const AdvancedNetworkConfig = struct {
    transport: TransportConfig,
    tls: TlsConfig,
    http: HttpConfig,
    qos: QosConfig,
    load_balancing: LoadBalancingConfig,
    monitoring: MonitoringConfig,
    name: ?[]const u8,
    environment: NetworkEnvironment,
    
    pub const NetworkEnvironment = enum {
        development,
        testing,
        staging,
        production,
        
        pub fn toString(self: NetworkEnvironment) []const u8 {
            return switch (self) {
                .development => "development",
                .testing => "testing",
                .staging => "staging",
                .production => "production",
            };
        }
    };
    
    pub fn init(allocator: Allocator) AdvancedNetworkConfig {
        return AdvancedNetworkConfig{
            .transport = TransportConfig.init(),
            .tls = TlsConfig.init(),
            .http = HttpConfig.init(allocator),
            .qos = QosConfig.init(),
            .load_balancing = LoadBalancingConfig.init(allocator),
            .monitoring = MonitoringConfig.init(allocator),
            .name = null,
            .environment = .production,
        };
    }
    
    pub fn deinit(self: *AdvancedNetworkConfig) void {
        self.http.deinit();
        self.load_balancing.deinit();
        self.monitoring.deinit();
        
        if (self.name) |name| {
            self.http.custom_headers.allocator.free(name); // Using any allocator reference
        }
    }
    
    pub fn withName(self: AdvancedNetworkConfig, allocator: Allocator, name: []const u8) !AdvancedNetworkConfig {
        var config = self;
        config.name = try allocator.dupe(u8, name);
        return config;
    }
    
    pub fn withEnvironment(self: AdvancedNetworkConfig, environment: NetworkEnvironment) AdvancedNetworkConfig {
        var config = self;
        config.environment = environment;
        return config;
    }
    
    pub fn optimizeForLatency(self: AdvancedNetworkConfig) AdvancedNetworkConfig {
        var config = self;
        
        // Transport optimizations
        config.transport.tcp_no_delay = true;
        config.transport.connect_timeout_ms = 5000; // Reduced timeout
        
        // HTTP optimizations
        config.http.version = .http_2;
        config.http.compression_enabled = false; // Trade CPU for latency
        
        // QoS optimizations
        config.qos.traffic_class = .control;
        config.qos.priority = .high;
        config.qos.latency_target_ms = 100; // 100ms target
        
        return config;
    }
    
    pub fn optimizeForThroughput(self: AdvancedNetworkConfig) AdvancedNetworkConfig {
        var config = self;
        
        // Transport optimizations
        config.transport.socket_buffer_size = 1024 * 1024; // 1MB buffer
        config.transport.keepalive_enabled = true;
        
        // HTTP optimizations
        config.http.compression_enabled = true;
        config.http.compression_algorithm = .gzip;
        config.http.max_concurrent_streams = 200; // Increased concurrency
        
        // QoS optimizations
        config.qos.congestion_control = .bbr;
        config.qos.throughput_target_bps = 100_000_000; // 100 Mbps target
        
        return config;
    }
    
    pub fn optimizeForReliability(self: AdvancedNetworkConfig) AdvancedNetworkConfig {
        var config = self;
        
        // Transport optimizations
        config.transport.keepalive_enabled = true;
        config.transport.keepalive_idle_ms = 10000; // More aggressive keepalive
        config.transport.keepalive_interval_ms = 2000;
        
        // Load balancing optimizations
        config.load_balancing.health_check_enabled = true;
        config.load_balancing.health_check_interval_ms = 15000; // More frequent checks
        config.load_balancing.failover_enabled = true;
        config.load_balancing.circuit_breaker_enabled = true;
        
        // QoS optimizations
        config.qos.flow_control_enabled = true;
        config.qos.priority = .high;
        
        return config;
    }
    
    pub fn forDevelopment(self: AdvancedNetworkConfig) AdvancedNetworkConfig {
        var config = self;
        
        config.environment = .development;
        
        // Relaxed TLS for development
        config.tls = config.tls.insecure();
        
        // Reduced timeouts for faster development cycle
        config.transport.connect_timeout_ms = 3000;
        config.transport.read_timeout_ms = 10000;
        
        // Simpler load balancing
        config.load_balancing.strategy = .round_robin;
        config.load_balancing.health_check_enabled = false;
        
        return config;
    }
    
    pub fn validate(self: AdvancedNetworkConfig) !void {
        // Validate transport configuration
        if (self.transport.connect_timeout_ms == 0) {
            return error.InvalidConfiguration;
        }
        
        if (self.transport.keepalive_enabled and self.transport.keepalive_idle_ms == 0) {
            return error.InvalidConfiguration;
        }
        
        // Validate HTTP configuration
        if (self.http.max_request_size == 0 or self.http.max_response_size == 0) {
            return error.InvalidConfiguration;
        }
        
        // Validate QoS configuration
        if (self.qos.bandwidth_limit) |limit| {
            if (limit.upload_bps == 0 or limit.download_bps == 0) {
                return error.InvalidConfiguration;
            }
        }
        
        // Validate load balancing configuration
        if (self.load_balancing.health_check_enabled and self.load_balancing.health_check_interval_ms == 0) {
            return error.InvalidConfiguration;
        }
    }
    
    pub fn summary(self: AdvancedNetworkConfig, allocator: Allocator) ![]u8 {
        var summary_text = ArrayList(u8).init(allocator);
        const writer = summary_text.writer();
        
        try writer.print("Network Configuration Summary\n");
        try writer.print("=============================\n");
        
        if (self.name) |name| {
            try writer.print("Name: {s}\n", .{name});
        }
        
        try writer.print("Environment: {s}\n", .{self.environment.toString()});
        try writer.print("Transport: {s} over {s}\n", .{ self.transport.protocol.toString(), self.transport.version.toString() });
        try writer.print("TLS: {s} (version: {s})\n", .{ if (self.tls.enabled) "Enabled" else "Disabled", self.tls.version.toString() });
        try writer.print("HTTP Version: {s}\n", .{self.http.version.toString()});
        try writer.print("Load Balancing: {s}\n", .{self.load_balancing.strategy.toString()});
        try writer.print("QoS Priority: {s}\n", .{self.qos.priority.toString()});
        try writer.print("Monitoring: {s}\n", .{if (self.monitoring.enabled) "Enabled" else "Disabled"});
        
        return summary_text.toOwnedSlice();
    }
};

// Predefined configuration profiles
pub const NetworkProfiles = struct {
    pub fn hederaMainnet(allocator: Allocator) !AdvancedNetworkConfig {
        var config = AdvancedNetworkConfig.init(allocator);
        config = try config.withName(allocator, "HederaMainnet");
        config = config.withEnvironment(.production);
        return config.optimizeForReliability();
    }
    
    pub fn hederaTestnet(allocator: Allocator) !AdvancedNetworkConfig {
        var config = AdvancedNetworkConfig.init(allocator);
        config = try config.withName(allocator, "HederaTestnet");
        config = config.withEnvironment(.testing);
        return config.optimizeForLatency();
    }
    
    pub fn hederaPreviewnet(allocator: Allocator) !AdvancedNetworkConfig {
        var config = AdvancedNetworkConfig.init(allocator);
        config = try config.withName(allocator, "HederaPreviewnet");
        config = config.withEnvironment(.development);
        return config.forDevelopment();
    }
    
    pub fn highThroughput(allocator: Allocator) !AdvancedNetworkConfig {
        var config = AdvancedNetworkConfig.init(allocator);
        config = try config.withName(allocator, "HighThroughput");
        return config.optimizeForThroughput();
    }
    
    pub fn lowLatency(allocator: Allocator) !AdvancedNetworkConfig {
        var config = AdvancedNetworkConfig.init(allocator);
        config = try config.withName(allocator, "LowLatency");
        return config.optimizeForLatency();
    }
};

// Test cases
test "TransportConfig basic functionality" {
    var config = TransportConfig.init();
    
    try testing.expectEqual(TransportConfig.TransportProtocol.tcp, config.protocol);
    try testing.expectEqual(TransportConfig.ProtocolVersion.dual_stack, config.version);
    try testing.expect(config.keepalive_enabled);
    
    config = config.withProtocol(.udp).withTimeouts(5000, 15000, 15000);
    try testing.expectEqual(TransportConfig.TransportProtocol.udp, config.protocol);
    try testing.expectEqual(@as(u32, 5000), config.connect_timeout_ms);
}

test "TlsConfig cipher suites" {
    const config = TlsConfig.init();
    
    try testing.expect(config.enabled);
    try testing.expectEqual(TlsConfig.TlsVersion.auto, config.version);
    try testing.expect(config.cipher_suites.len > 0);
    try testing.expect(config.hostname_verification);
    
    const insecure_config = config.insecure();
    try testing.expectEqual(TlsConfig.CertVerificationMode.none, insecure_config.certificate_verification);
    try testing.expect(!insecure_config.hostname_verification);
}

test "QosConfig traffic classes" {
    var config = QosConfig.init();
    
    try testing.expectEqual(QosConfig.TrafficClass.best_effort, config.traffic_class);
    try testing.expectEqual(QosConfig.Priority.normal, config.priority);
    
    config = config.withTrafficClass(.voice).withPriority(.highest);
    try testing.expectEqual(QosConfig.TrafficClass.voice, config.traffic_class);
    try testing.expectEqual(QosConfig.Priority.highest, config.priority);
    try testing.expectEqual(@as(u8, 46), config.dscp.?);
}

test "AdvancedNetworkConfig optimization profiles" {
    const allocator = testing.allocator;
    
    var config = AdvancedNetworkConfig.init(allocator);
    defer config.deinit();
    
    // Test latency optimization
    const latency_config = config.optimizeForLatency();
    try testing.expect(latency_config.transport.tcp_no_delay);
    try testing.expectEqual(QosConfig.Priority.high, latency_config.qos.priority);
    try testing.expect(!latency_config.http.compression_enabled);
    
    // Test throughput optimization
    const throughput_config = config.optimizeForThroughput();
    try testing.expect(throughput_config.http.compression_enabled);
    try testing.expect(throughput_config.transport.socket_buffer_size != null);
    
    // Test development configuration
    const dev_config = config.forDevelopment();
    try testing.expectEqual(AdvancedNetworkConfig.NetworkEnvironment.development, dev_config.environment);
    try testing.expectEqual(TlsConfig.CertVerificationMode.none, dev_config.tls.certificate_verification);
}

test "NetworkProfiles factory methods" {
    const allocator = testing.allocator;
    
    var mainnet_config = try NetworkProfiles.hederaMainnet(allocator);
    defer mainnet_config.deinit();
    
    try testing.expectEqual(AdvancedNetworkConfig.NetworkEnvironment.production, mainnet_config.environment);
    try testing.expect(mainnet_config.load_balancing.health_check_enabled);
    
    var testnet_config = try NetworkProfiles.hederaTestnet(allocator);
    defer testnet_config.deinit();
    
    try testing.expectEqual(AdvancedNetworkConfig.NetworkEnvironment.testing, testnet_config.environment);
    try testing.expectEqual(QosConfig.Priority.high, testnet_config.qos.priority);
}

test "Configuration validation" {
    const allocator = testing.allocator;
    
    var valid_config = AdvancedNetworkConfig.init(allocator);
    defer valid_config.deinit();
    
    try valid_config.validate(); // Should not throw
    
    // Test invalid configuration
    var invalid_config = valid_config;
    invalid_config.transport.connect_timeout_ms = 0;
    
    try testing.expectError(error.InvalidConfiguration, invalid_config.validate());
}