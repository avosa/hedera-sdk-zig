const std = @import("std");
const testing = std.testing;
const hedera = @import("hedera");

test "Node creation and validation" {
    const allocator = testing.allocator;
    
    // Test node creation with IP address
    var node1 = try hedera.Node.init(allocator, "35.237.200.180:50211", hedera.AccountId.init(0, 0, 3));
    defer node1.deinit();
    
    try testing.expectEqualStrings("35.237.200.180:50211", node1.address);
    try testing.expect(node1.account_id.equals(hedera.AccountId.init(0, 0, 3)));
    try testing.expect(node1.isHealthy());
    
    // Test node creation with hostname
    var node2 = try hedera.Node.init(allocator, "testnet.hedera.com:50211", hedera.AccountId.init(0, 0, 4));
    defer node2.deinit();
    
    try testing.expectEqualStrings("testnet.hedera.com:50211", node2.address);
    try testing.expect(node2.account_id.equals(hedera.AccountId.init(0, 0, 4)));
    
    // Test node health management
    try testing.expect(node1.isHealthy());
    
    node1.markUnhealthy();
    try testing.expect(!node1.isHealthy());
    
    // Wait for health to potentially recover (or force it for testing)
    node1.markHealthy();
    try testing.expect(node1.isHealthy());
}

test "Network creation and node management" {
    const allocator = testing.allocator;
    
    var network = hedera.Network.init(allocator);
    defer network.deinit();
    
    // Test adding nodes
    try network.addNode("35.237.200.180:50211", hedera.AccountId.init(0, 0, 3));
    try network.addNode("35.186.191.247:50211", hedera.AccountId.init(0, 0, 4));
    try network.addNode("35.192.2.25:50211", hedera.AccountId.init(0, 0, 5));
    
    try testing.expectEqual(@as(usize, 3), network.nodes.count());
    
    // Test node lookup by account ID
    const node3 = network.getNode(hedera.AccountId.init(0, 0, 3));
    try testing.expect(node3 != null);
    try testing.expectEqualStrings("35.237.200.180:50211", node3.?.address);
    
    const missing_node = network.getNode(hedera.AccountId.init(0, 0, 999));
    try testing.expect(missing_node == null);
    
    // Test getting healthy nodes
    const healthy_nodes = try network.getHealthyNodes(allocator);
    defer allocator.free(healthy_nodes);
    
    try testing.expectEqual(@as(usize, 3), healthy_nodes.len);
    
    // Mark one node as unhealthy and test again
    if (network.getNode(hedera.AccountId.init(0, 0, 3))) |node| {
        node.markUnhealthy();
    }
    
    const healthy_nodes_after = try network.getHealthyNodes(allocator);
    defer allocator.free(healthy_nodes_after);
    
    try testing.expectEqual(@as(usize, 2), healthy_nodes_after.len);
    
    // Test node selection with round-robin
    const selected1 = try network.selectNode();
    const selected2 = try network.selectNode();
    const selected3 = try network.selectNode();
    
    try testing.expect(selected1 != null);
    try testing.expect(selected2 != null);
    try testing.expect(selected3 != null);
    
    // Should cycle through different nodes (though specific order isn't guaranteed)
    // Just verify we get valid, healthy nodes
    try testing.expect(selected1.?.isHealthy());
    try testing.expect(selected2.?.isHealthy());
    try testing.expect(selected3.?.isHealthy());
}

test "Network presets (testnet/mainnet)" {
    const allocator = testing.allocator;
    
    // Test testnet preset
    var testnet = try hedera.Network.forTestnet(allocator);
    defer testnet.deinit();
    
    try testing.expect(testnet.nodes.count() > 0);
    
    // Verify testnet has expected nodes (check a few known ones)
    const testnet_node3 = testnet.getNode(hedera.AccountId.init(0, 0, 3));
    try testing.expect(testnet_node3 != null);
    
    const testnet_node4 = testnet.getNode(hedera.AccountId.init(0, 0, 4));
    try testing.expect(testnet_node4 != null);
    
    // Test mainnet preset
    var mainnet = try hedera.Network.forMainnet(allocator);
    defer mainnet.deinit();
    
    try testing.expect(mainnet.nodes.count() > 0);
    
    // Verify mainnet has different nodes than testnet
    const mainnet_node3 = mainnet.getNode(hedera.AccountId.init(0, 0, 3));
    try testing.expect(mainnet_node3 != null);
    
    // Addresses should be different between testnet and mainnet
    try testing.expect(!std.mem.eql(u8, testnet_node3.?.address, mainnet_node3.?.address));
    
    // Test previewnet preset
    var previewnet = try hedera.Network.forPreviewnet(allocator);
    defer previewnet.deinit();
    
    try testing.expect(previewnet.nodes.count() > 0);
}

test "Client initialization and configuration" {
    const allocator = testing.allocator;
    
    // Test client creation with testnet preset
    var client = try hedera.Client.forTestnet(allocator);
    defer client.deinit();
    
    try testing.expect(client.network.nodes.count() > 0);
    try testing.expect(client.operator == null); // No operator set initially
    
    // Test setting operator
    const operator_id = hedera.AccountId.init(0, 0, 123);
    var operator_key = try hedera.PrivateKey.generateEd25519(allocator);
    defer operator_key.deinit();
    
    try client.setOperator(operator_id, operator_key);
    
    try testing.expect(client.operator != null);
    try testing.expect(client.operator.?.account_id.equals(operator_id));
    
    // Test operator key access
    const retrieved_key = client.getOperatorKey();
    try testing.expect(retrieved_key != null);
    try testing.expectEqualSlices(u8, operator_key.getBytes(), retrieved_key.?.getBytes());
    
    // Test operator account access
    const retrieved_account = client.getOperatorAccountId();
    try testing.expect(retrieved_account != null);
    try testing.expect(retrieved_account.?.equals(operator_id));
}

test "Client network configuration" {
    const allocator = testing.allocator;
    
    var client = try hedera.Client.forTestnet(allocator);
    defer client.deinit();
    
    // Test setting custom mirror node URL
    try client.setMirrorNodeUrl("https://testnet.mirrornode.hedera.com");
    try testing.expectEqualStrings("https://testnet.mirrornode.hedera.com", client.mirror_node_url.?);
    
    // Test setting request timeout
    client.setRequestTimeout(hedera.Duration.fromSeconds(30));
    try testing.expectEqual(@as(i64, 30), client.request_timeout.seconds);
    
    // Test setting max transaction fee
    try client.setMaxTransactionFee(hedera.Hbar.from(2));
    try testing.expectEqual(@as(f64, 2.0), client.max_transaction_fee.?.toHbars());
    
    // Test setting max query payment
    try client.setMaxQueryPayment(hedera.Hbar.from(1));
    try testing.expectEqual(@as(f64, 1.0), client.max_query_payment.?.toHbars());
    
    // Test setting transaction valid duration
    client.setTransactionValidDuration(hedera.Duration.fromMinutes(5));
    try testing.expectEqual(@as(i64, 300), client.transaction_valid_duration.seconds);
}

test "Client with custom network" {
    const allocator = testing.allocator;
    
    // Create custom network
    var custom_network = hedera.Network.init(allocator);
    defer custom_network.deinit();
    
    try custom_network.addNode("127.0.0.1:50211", hedera.AccountId.init(0, 0, 3));
    try custom_network.addNode("127.0.0.1:50212", hedera.AccountId.init(0, 0, 4));
    
    // Create client with custom network
    var client = hedera.Client.initWithNetwork(allocator, custom_network);
    defer client.deinit();
    
    try testing.expectEqual(@as(usize, 2), client.network.nodes.count());
    
    const node3 = client.network.getNode(hedera.AccountId.init(0, 0, 3));
    try testing.expect(node3 != null);
    try testing.expectEqualStrings("127.0.0.1:50211", node3.?.address);
}

test "Node health and retry logic" {
    const allocator = testing.allocator;
    
    var node = try hedera.Node.init(allocator, "test.example.com:50211", hedera.AccountId.init(0, 0, 99));
    defer node.deinit();
    
    // Initially healthy
    try testing.expect(node.isHealthy());
    try testing.expectEqual(@as(u32, 0), node.consecutive_failures);
    
    // Simulate failures
    node.recordFailure();
    try testing.expectEqual(@as(u32, 1), node.consecutive_failures);
    try testing.expect(node.isHealthy()); // Still healthy after one failure
    
    // More failures
    node.recordFailure();
    node.recordFailure();
    node.recordFailure();
    node.recordFailure(); // 5 total failures
    
    try testing.expectEqual(@as(u32, 5), node.consecutive_failures);
    try testing.expect(!node.isHealthy()); // Should be unhealthy after 5 failures
    
    // Simulate successful operation
    node.recordSuccess();
    try testing.expectEqual(@as(u32, 0), node.consecutive_failures);
    try testing.expect(node.isHealthy()); // Should be healthy again
    
    // Test backoff timing
    node.recordFailure();
    const backoff_duration = node.getBackoffDuration();
    try testing.expect(backoff_duration.seconds > 0);
    
    // More failures should increase backoff
    node.recordFailure();
    node.recordFailure();
    const longer_backoff = node.getBackoffDuration();
    try testing.expect(longer_backoff.seconds >= backoff_duration.seconds);
}

test "Network load balancing and node selection" {
    const allocator = testing.allocator;
    
    var network = hedera.Network.init(allocator);
    defer network.deinit();
    
    // Configure multiple nodes
    try network.addNode("node1.example.com:50211", hedera.AccountId.init(0, 0, 3));
    try network.addNode("node2.example.com:50211", hedera.AccountId.init(0, 0, 4));
    try network.addNode("node3.example.com:50211", hedera.AccountId.init(0, 0, 5));
    try network.addNode("node4.example.com:50211", hedera.AccountId.init(0, 0, 6));
    
    // Track which nodes are selected over multiple calls
    var node_selections = std.AutoHashMap(u64, u32).init(allocator);
    defer node_selections.deinit();
    
    // Select nodes multiple times and track distribution
    for (0..20) |_| {
        const selected_node = try network.selectNode();
        if (selected_node) |node| {
            const node_num = node.account_id.entity.num;
            const current_count = node_selections.get(node_num) orelse 0;
            try node_selections.put(node_num, current_count + 1);
        }
    }
    
    // Verify that multiple nodes were selected (load balancing)
    try testing.expect(node_selections.count() > 1);
    
    // Mark some nodes as unhealthy and verify selection changes
    if (network.getNode(hedera.AccountId.init(0, 0, 3))) |node| {
        node.markUnhealthy();
    }
    if (network.getNode(hedera.AccountId.init(0, 0, 4))) |node| {
        node.markUnhealthy();
    }
    
    // Clear previous selections
    node_selections.clearAndFree();
    
    // Select nodes again
    for (0..10) |_| {
        const selected_node = try network.selectNode();
        if (selected_node) |node| {
            const node_num = node.account_id.entity.num;
            const current_count = node_selections.get(node_num) orelse 0;
            try node_selections.put(node_num, current_count + 1);
            
            // Verify selected nodes are healthy
            try testing.expect(node.isHealthy());
        }
    }
    
    // Should only select from healthy nodes (5 and 6)
    try testing.expect(!node_selections.contains(3));
    try testing.expect(!node_selections.contains(4));
    try testing.expect(node_selections.contains(5) or node_selections.contains(6));
}

test "Network error handling and recovery" {
    const allocator = testing.allocator;
    
    var network = hedera.Network.init(allocator);
    defer network.deinit();
    
    // Configure nodes
    try network.addNode("node1.example.com:50211", hedera.AccountId.init(0, 0, 3));
    try network.addNode("node2.example.com:50211", hedera.AccountId.init(0, 0, 4));
    
    // Mark all nodes as unhealthy
    if (network.getNode(hedera.AccountId.init(0, 0, 3))) |node| {
        node.markUnhealthy();
    }
    if (network.getNode(hedera.AccountId.init(0, 0, 4))) |node| {
        node.markUnhealthy();
    }
    
    // Should return error when no healthy nodes available
    try testing.expectError(error.NoHealthyNodes, network.selectNode());
    
    // Recover one node
    if (network.getNode(hedera.AccountId.init(0, 0, 3))) |node| {
        node.markHealthy();
    }
    
    // Should now be able to select a node
    const recovered_node = try network.selectNode();
    try testing.expect(recovered_node != null);
    try testing.expect(recovered_node.?.account_id.equals(hedera.AccountId.init(0, 0, 3)));
}

test "Client configuration validation" {
    const allocator = testing.allocator;
    
    var client = try hedera.Client.forTestnet(allocator);
    defer client.deinit();
    
    // Test invalid configurations
    try testing.expectError(error.InvalidConfiguration, client.setMaxTransactionFee(hedera.Hbar.ZERO));
    try testing.expectError(error.InvalidConfiguration, client.setMaxQueryPayment(hedera.Hbar.ZERO));
    
    // Test negative values
    try testing.expectError(error.InvalidConfiguration, client.setMaxTransactionFee(hedera.Hbar.fromTinybars(-1000)));
    
    // Test very large values (should be allowed but might warn)
    try client.setMaxTransactionFee(hedera.Hbar.from(1000000)); // Very large fee
    try testing.expectEqual(@as(f64, 1000000.0), client.max_transaction_fee.?.toHbars());
    
    // Test timeout configurations
    client.setRequestTimeout(hedera.Duration.fromSeconds(1)); // Very short timeout
    try testing.expectEqual(@as(i64, 1), client.request_timeout.seconds);
    
    client.setRequestTimeout(hedera.Duration.fromHours(1)); // Very long timeout
    try testing.expectEqual(@as(i64, 3600), client.request_timeout.seconds);
    
    // Test transaction valid duration
    try testing.expectError(error.InvalidConfiguration, 
        client.setTransactionValidDuration(hedera.Duration.fromSeconds(0)));
    
    try testing.expectError(error.InvalidConfiguration, 
        client.setTransactionValidDuration(hedera.Duration.fromMinutes(200))); // Too long
    
    // Valid duration should work
    client.setTransactionValidDuration(hedera.Duration.fromMinutes(2));
    try testing.expectEqual(@as(i64, 120), client.transaction_valid_duration.seconds);
}