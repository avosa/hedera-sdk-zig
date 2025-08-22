const std = @import("std");
const testing = std.testing;
const hedera = @import("hedera");

test "Client network initialization" {
    // Test mainnet initialization
    var mainnet_client = try hedera.Client.forMainnet();
    defer mainnet_client.deinit();
    
    try testing.expect(mainnet_client.network == .Mainnet);
    try testing.expectEqualStrings("mainnet", mainnet_client.ledger_id);
    
    // Test testnet initialization
    var testnet_client = try hedera.Client.forTestnet();
    defer testnet_client.deinit();
    
    try testing.expect(testnet_client.network == .Testnet);
    try testing.expectEqualStrings("testnet", testnet_client.ledger_id);
    
    // Test previewnet initialization
    var previewnet_client = try hedera.Client.forPreviewnet();
    defer previewnet_client.deinit();
    
    try testing.expect(previewnet_client.network == .Previewnet);
    try testing.expectEqualStrings("previewnet", previewnet_client.ledger_id);
}

test "Client for name (Go SDK compatible)" {
    // Test mainnet by name
    var mainnet = try hedera.client_for_name("mainnet");
    defer mainnet.deinit();
    try testing.expect(mainnet.network == .Mainnet);
    
    // Test testnet by name
    var testnet = try hedera.client_for_name("testnet");
    defer testnet.deinit();
    try testing.expect(testnet.network == .Testnet);
    
    // Test previewnet by name
    var previewnet = try hedera.client_for_name("previewnet");
    defer previewnet.deinit();
    try testing.expect(previewnet.network == .Previewnet);
    
    // Test invalid network name
    try testing.expectError(error.InvalidNetworkName, hedera.client_for_name("invalid"));
}

test "Client operator configuration" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var client = try hedera.Client.forTestnet();
    defer client.deinit();
    
    // Set operator
    const operator_id = hedera.AccountId.init(0, 0, 1001);
    var operator_key = try hedera.generate_private_key(allocator);
    defer operator_key.deinit();
    
    try client.set_operator(operator_id, operator_key);
    
    // Get operator account ID
    const retrieved_id = client.getOperatorAccountId();
    try testing.expect(retrieved_id != null);
    try testing.expectEqual(@as(u64, 1001), retrieved_id.?.entity.num);
    
    // Get operator public key
    const retrieved_key = client.getOperatorPublicKey();
    try testing.expect(retrieved_key != null);
}

test "Client network nodes" {
    var client = try hedera.Client.forTestnet();
    defer client.deinit();
    
    // Get network nodes
    const nodes = client.getNetwork();
    try testing.expect(nodes.count() > 0);
    
    // Verify testnet nodes
    try testing.expect(nodes.contains(hedera.AccountId.init(0, 0, 3)));
    try testing.expect(nodes.contains(hedera.AccountId.init(0, 0, 4)));
    try testing.expect(nodes.contains(hedera.AccountId.init(0, 0, 5)));
    try testing.expect(nodes.contains(hedera.AccountId.init(0, 0, 6)));
    try testing.expect(nodes.contains(hedera.AccountId.init(0, 0, 7)));
}

test "Client configuration settings" {
    var client = try hedera.Client.forTestnet();
    defer client.deinit();
    
    // Set request timeout
    client.setRequestTimeoutDuration(hedera.Duration.fromSeconds(60));
    try testing.expectEqual(@as(i64, 60_000_000_000), client.config.request_timeout);
    
    // Set max retry
    client.setMaxRetry(5);
    try testing.expectEqual(@as(u32, 5), client.config.max_attempts);
    
    // Set max backoff
    client.setMaxBackoff(hedera.Duration.fromSeconds(8));
    try testing.expectEqual(@as(i64, 8), client.max_backoff.seconds);
    
    // Set min backoff
    client.setMinBackoff(hedera.Duration.fromMillis(250));
    try testing.expectEqual(@as(i32, 250000000), client.min_backoff.nanos);
    
    // Set max node attempts
    client.setMaxNodeAttempts(3);
    try testing.expectEqual(@as(u32, 3), client.max_node_attempts);
    
    // Set node wait time
    client.setNodeWaitTime(hedera.Duration.fromSeconds(5));
    try testing.expectEqual(@as(i64, 5), client.node_wait_time.seconds);
}

test "Node connection management" {
    // Node test doesn't need allocator
    
    const account_id = hedera.AccountId.init(0, 0, 3);
    const address = try std.net.Address.parseIp4("35.237.200.180", 50211);
    var node = hedera.Node.init(account_id, address);
    
    // Node already initialized with account_id and address
    // cert_hash is already null by default
    
    // Test getting node info
    try testing.expectEqual(@as(u64, 3), node.account_id.entity.num);
    try testing.expectEqual(@as(u16, 50211), node.address.getPort());
    try testing.expectEqual(@as(u64, 0), node.used_count);
}

test "Network version info" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const version_info = hedera.NetworkVersionInfo{
        .hapi_proto_version = hedera.SemanticVersion.init(0, 30, 0, allocator),
        .hedera_services_version = hedera.SemanticVersion.init(0, 30, 0, allocator),
    };
    
    // Verify versions
    try testing.expectEqual(@as(i32, 0), version_info.hapi_proto_version.major);
    try testing.expectEqual(@as(i32, 30), version_info.hapi_proto_version.minor);
    try testing.expectEqual(@as(i32, 0), version_info.hapi_proto_version.patch);
}

test "Address book management" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var address_book = hedera.AddressBook.init(allocator);
    defer address_book.deinit();
    
    // Add node addresses
    const node1 = hedera.NodeAddress{
        .node_id = 1,
        .account_id = hedera.AccountId.init(0, 0, 1),
        .address = "0.0.0.1",
        .port = 50211,
        .tls_port = null,
        .owns_address = false,
        .owns_rsa_key = false,
        .owns_description = false,
        .rsa_pub_key = "node1_key",
        .node_account_id = hedera.AccountId.init(0, 0, 3),
        .node_cert_hash = null,
        .service_endpoints = std.ArrayList(hedera.ServiceEndpoint).init(allocator),
        .description = "Node 1",
    };
    
    const node2 = hedera.NodeAddress{
        .node_id = 2,
        .account_id = hedera.AccountId.init(0, 0, 2),
        .address = "0.0.0.2",
        .port = 50211,
        .tls_port = null,
        .owns_address = false,
        .owns_rsa_key = false,
        .owns_description = false,
        .rsa_pub_key = "node2_key",
        .node_account_id = hedera.AccountId.init(0, 0, 4),
        .node_cert_hash = null,
        .service_endpoints = std.ArrayList(hedera.ServiceEndpoint).init(allocator),
        .description = "Node 2",
    };
    
    try address_book.node_addresses.append(node1);
    try address_book.node_addresses.append(node2);
    
    try testing.expectEqual(@as(usize, 2), address_book.node_addresses.items.len);
    try testing.expectEqual(@as(i64, 1), address_book.node_addresses.items[0].node_id);
    try testing.expectEqual(@as(i64, 2), address_book.node_addresses.items[1].node_id);
}

test "Mirror node configuration" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var mirror_network = hedera.MirrorNetwork.init(allocator);
    defer mirror_network.deinit();
    
    // Add mirror nodes
    try mirror_network.addNode("hcs.testnet.mirrornode.hedera.com:5600");
    try mirror_network.addNode("hcs.testnet.mirrornode.hedera.com:5601");
    
    // Set network name
    mirror_network.network_name = "testnet";
    
    // Get nodes
    const nodes = mirror_network.getNodes();
    try testing.expectEqual(@as(usize, 2), nodes.len);
    try testing.expectEqualStrings("testnet", mirror_network.network_name);
}

test "gRPC channel management" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var channel = hedera.GrpcChannel.init(allocator);
    defer channel.deinit();
    
    // Set channel properties
    channel.address = "0.testnet.hedera.com:50211";
    channel.secure = true;
    channel.max_inbound_message_size = 4 * 1024 * 1024; // 4MB
    channel.max_inbound_metadata_size = 8 * 1024; // 8KB
    
    try testing.expectEqualStrings("0.testnet.hedera.com:50211", channel.address);
    try testing.expect(channel.secure);
    try testing.expectEqual(@as(u32, 4194304), channel.max_inbound_message_size);
    try testing.expectEqual(@as(u32, 8192), channel.max_inbound_metadata_size);
}

test "Network retry logic" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    
    const retry_config = hedera.RetryConfig{
        .max_attempts = 5,
        .min_backoff = hedera.Duration.fromMillis(250),
        .max_backoff = hedera.Duration.fromSeconds(8),
        .backoff_multiplier = 2.0,
        .jitter = 0.1,
    };
    
    // Calculate backoff times
    var backoff = retry_config.min_backoff;
    var attempt: u32 = 0;
    
    while (attempt < retry_config.max_attempts) : (attempt += 1) {
        // Verify backoff is within limits
        try testing.expect(backoff.seconds <= retry_config.max_backoff.seconds);
        
        // Calculate next backoff
        const next_seconds = @as(i64, @intFromFloat(@as(f64, @floatFromInt(backoff.seconds)) * retry_config.backoff_multiplier));
        backoff = hedera.Duration.fromSeconds(@min(next_seconds, retry_config.max_backoff.seconds));
    }
    
    try testing.expectEqual(@as(u32, 5), attempt);
}

test "Request and response handling" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    
    // Create mock request
    const request = hedera.Request{
        .type = .Query,
        .transaction = null,
        .query = null,
        .node_account_id = hedera.AccountId.init(0, 0, 3),
        .max_retry = 3,
        .timeout = hedera.Duration.fromSeconds(30),
    };
    
    // Create mock response
    const response = hedera.Response{
        .type = .Query,
        .transaction_response = null,
        .query_response = null,
        .node_account_id = hedera.AccountId.init(0, 0, 3),
        .status = .OK,
    };
    
    try testing.expectEqual(hedera.RequestType.Query, request.type);
    try testing.expectEqual(hedera.ResponseType.Query, response.type);
    try testing.expectEqual(@as(u64, 3), request.node_account_id.entity.num);
    try testing.expectEqual(@as(u64, 3), response.node_account_id.entity.num);
    try testing.expectEqual(hedera.Status.OK, response.status);
}

test "Load balancing strategies" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Round-robin strategy
    var round_robin = hedera.LoadBalancer{
        .strategy = .round_robin,
        .current_index = 0,
        .nodes = std.ArrayList(hedera.AccountId).init(allocator),
    };
    defer round_robin.nodes.deinit();
    
    try round_robin.nodes.append(hedera.AccountId.init(0, 0, 3));
    try round_robin.nodes.append(hedera.AccountId.init(0, 0, 4));
    try round_robin.nodes.append(hedera.AccountId.init(0, 0, 5));
    
    // Get next node (round-robin)
    const node1 = round_robin.nodes.items[round_robin.current_index];
    round_robin.current_index = (round_robin.current_index + 1) % round_robin.nodes.items.len;
    
    const node2 = round_robin.nodes.items[round_robin.current_index];
    round_robin.current_index = (round_robin.current_index + 1) % round_robin.nodes.items.len;
    
    try testing.expectEqual(@as(u64, 3), node1.entity.num);
    try testing.expectEqual(@as(u64, 4), node2.entity.num);
    
    // Random strategy
    var random = hedera.LoadBalancer{
        .strategy = .random,
        .current_index = 0,
        .nodes = std.ArrayList(hedera.AccountId).init(allocator),
    };
    defer random.nodes.deinit();
    
    try random.nodes.append(hedera.AccountId.init(0, 0, 3));
    try random.nodes.append(hedera.AccountId.init(0, 0, 4));
    try random.nodes.append(hedera.AccountId.init(0, 0, 5));
    
    // Random selection
    var prng = std.Random.DefaultPrng.init(42);
    const rand = prng.random();
    const random_index = rand.intRangeAtMost(usize, 0, random.nodes.items.len - 1);
    const random_node = random.nodes.items[random_index];
    
    try testing.expect(random_node.entity.num >= 3 and random_node.entity.num <= 5);
}

test "TLS certificate handling" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var tls_config = hedera.TlsConfig{
        .cert_path = "/path/to/cert.pem",
        .key_path = "/path/to/key.pem",
        .ca_path = "/path/to/ca.pem",
        .verify_server = true,
        .alpn_protocols = std.ArrayList([]const u8).init(allocator),
    };
    defer tls_config.alpn_protocols.deinit();
    
    // Add ALPN protocols
    try tls_config.alpn_protocols.append("h2");
    try tls_config.alpn_protocols.append("http/1.1");
    
    try testing.expectEqualStrings("/path/to/cert.pem", tls_config.cert_path);
    try testing.expectEqualStrings("/path/to/key.pem", tls_config.key_path);
    try testing.expectEqualStrings("/path/to/ca.pem", tls_config.ca_path);
    try testing.expect(tls_config.verify_server);
    try testing.expectEqual(@as(usize, 2), tls_config.alpn_protocols.items.len);
    try testing.expectEqualStrings("h2", tls_config.alpn_protocols.items[0]);
}

test "Network error handling" {
    // Test network errors
    const timeout_error = error.NetworkTimeout;
    const connection_error = error.ConnectionFailed;
    const dns_error = error.DnsResolutionFailed;
    const tls_error = error.TlsHandshakeFailed;
    
    // These errors should be distinct
    try testing.expect(timeout_error != connection_error);
    try testing.expect(connection_error != dns_error);
    try testing.expect(dns_error != tls_error);
}

test "Client close and cleanup" {
    var client = try hedera.Client.forTestnet();
    
    // Use client
    const nodes = client.getNetwork();
    try testing.expect(nodes.count() > 0);
    
    // Close client
    client.close();
    
    // Verify client is closed
    try testing.expect(client.closed);
    
    // Cleanup
    client.deinit();
}