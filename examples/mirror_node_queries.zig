const std = @import("std");
const hedera = @import("hedera");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    std.log.info("Mirror Node REST API Example", .{});
    std.log.info("============================", .{});

    // Example 1: Initialize Mirror Node REST client
    std.log.info("\n1. Initializing Mirror Node client...", .{});
    
    const mirror_base_url = std.posix.getenv("HEDERA_MIRROR_NODE_URL") orelse "https://testnet.mirrornode.hedera.com";
    
    var mirror_client = hedera.MirrorNodeClient.init(allocator, mirror_base_url);
    defer mirror_client.deinit();
    
    std.log.info("✓ Mirror Node client initialized", .{});
    std.log.info("✓ Base URL: {s}", .{mirror_base_url});

    // Example 2: Query network information
    std.log.info("\n2. Querying network information...", .{});
    
    const network_info = try mirror_client.getNetworkSupply();
    std.log.info("✓ Total supply: {} tinybars", .{network_info.total_supply});
    std.log.info("✓ Released supply: {} tinybars", .{network_info.released_supply});
    
    // Example 3: Query account information
    std.log.info("\n3. Querying account information...", .{});
    
    // Query treasury account (0.0.2)
    const treasury_account = hedera.AccountId.init(0, 0, 2);
    
    if (mirror_client.getAccountInfo(treasury_account)) |account_info| {
        std.log.info("✓ Account ID: {}", .{account_info.account});
        std.log.info("✓ Balance: {} tinybars", .{account_info.balance});
        std.log.info("✓ Auto renew period: {} seconds", .{account_info.auto_renew_period orelse 0});
        std.log.info("✓ Created timestamp: {}", .{account_info.created_timestamp.seconds});
        std.log.info("✓ Deleted: {}", .{account_info.deleted});
    } else |err| {
        std.log.warn("Could not query treasury account: {}", .{err});
    }

    // Example 4: Query account balances
    std.log.info("\n4. Querying account balances...", .{});
    
    if (mirror_client.getAccountBalances(null, 5)) |balances| {
        defer allocator.free(balances);
        
        std.log.info("✓ Retrieved {} account balances", .{balances.len});
        for (balances[0..@min(3, balances.len)], 0..) |balance, i| {
            std.log.info("  Account {}: {} tinybars", .{ i + 1, balance.balance });
        }
    } else |err| {
        std.log.warn("Could not query account balances: {}", .{err});
    }

    // Example 5: Query recent transactions
    std.log.info("\n5. Querying recent transactions...", .{});
    
    if (mirror_client.getTransactions(null, null, 10)) |transactions| {
        defer allocator.free(transactions);
        
        std.log.info("✓ Retrieved {} recent transactions", .{transactions.len});
        for (transactions[0..@min(3, transactions.len)], 0..) |tx, i| {
            std.log.info("  Transaction {}: {} - Status: {}", .{ i + 1, tx.transaction_id, tx.result });
            if (tx.consensus_timestamp) |timestamp| {
                std.log.info("    Consensus: {}", .{timestamp.seconds});
            }
        }
    } else |err| {
        std.log.warn("Could not query transactions: {}", .{err});
    }

    // Example 6: Query tokens
    std.log.info("\n6. Querying tokens...", .{});
    
    if (mirror_client.getTokens(10)) |tokens| {
        defer allocator.free(tokens);
        
        std.log.info("✓ Retrieved {} tokens", .{tokens.len});
        for (tokens[0..@min(3, tokens.len)], 0..) |token, i| {
            std.log.info("  Token {}: {} - {s} ({s})", .{ i + 1, token.token_id, token.name, token.symbol });
            std.log.info("    Type: {}, Total Supply: {}", .{ token.token_type, token.total_supply });
        }
    } else |err| {
        std.log.warn("Could not query tokens: {}", .{err});
    }

    // Example 7: Query topics
    std.log.info("\n7. Querying topics...", .{});
    
    if (mirror_client.getTopics(5)) |topics| {
        defer allocator.free(topics);
        
        std.log.info("✓ Retrieved {} topics", .{topics.len});
        for (topics[0..@min(3, topics.len)], 0..) |topic, i| {
            std.log.info("  Topic {}: {}", .{ i + 1, topic.topic_id });
            std.log.info("    Memo: {s}", .{topic.memo});
            std.log.info("    Messages: {}", .{topic.sequence_number});
        }
    } else |err| {
        std.log.warn("Could not query topics: {}", .{err});
    }

    // Example 8: Query contracts
    std.log.info("\n8. Querying contracts...", .{});
    
    if (mirror_client.getContracts(5)) |contracts| {
        defer allocator.free(contracts);
        
        std.log.info("✓ Retrieved {} contracts", .{contracts.len});
        for (contracts[0..@min(3, contracts.len)], 0..) |contract, i| {
            std.log.info("  Contract {}: {}", .{ i + 1, contract.contract_id });
            if (contract.file_id) |file_id| {
                std.log.info("    Bytecode File: {}", .{file_id});
            }
            std.log.info("    Created: {}", .{contract.created_timestamp.seconds});
        }
    } else |err| {
        std.log.warn("Could not query contracts: {}", .{err});
    }

    // Example 9: Query specific account with detailed information
    std.log.info("\n9. Detailed account query...", .{});
    
    const test_account = hedera.AccountId.init(0, 0, 98); // Known testnet account
    
    if (mirror_client.getAccount(test_account)) |detailed_account| {
        std.log.info("✓ Detailed Account Information:", .{});
        std.log.info("  ID: {}", .{detailed_account.account_id});
        std.log.info("  Balance: {} HBAR", .{detailed_account.balance.toHbars()});
        std.log.info("  Auto Renew Period: {} days", .{detailed_account.auto_renew_period.seconds / 86400});
        std.log.info("  Created: {}", .{detailed_account.created_timestamp.seconds});
        std.log.info("  Deleted: {}", .{detailed_account.deleted});
        std.log.info("  Receiver Signature Required: {}", .{detailed_account.receiver_sig_required});
        
        if (detailed_account.key) |key| {
            std.log.info("  Public Key Type: {}", .{key.key_type});
        }
        
        if (detailed_account.proxy_account_id) |proxy| {
            std.log.info("  Proxy Account: {}", .{proxy});
        }
    } else |err| {
        std.log.warn("Could not query detailed account: {}", .{err});
    }

    // Example 10: Query transactions by type
    std.log.info("\n10. Querying transactions by type...", .{});
    
    const transaction_types = [_][]const u8{
        "CRYPTOTRANSFER",
        "CRYPTOCREATEACCOUNT",
        "CONSENSUSSUBMITMESSAGE",
        "CONTRACTCREATEINSTANCE",
        "TOKENCREATION",
    };
    
    for (transaction_types) |tx_type| {
        if (mirror_client.getTransactions(null, tx_type, 3)) |typed_transactions| {
            defer allocator.free(typed_transactions);
            
            std.log.info("✓ Found {} {} transactions", .{ typed_transactions.len, tx_type });
            
            if (typed_transactions.len > 0) {
                const latest = typed_transactions[0];
                std.log.info("  Latest: {} - Status: {}", .{ latest.transaction_id, latest.result });
            }
        } else |err| {
            std.log.warn("Could not query {} transactions: {}", .{ tx_type, err });
        }
    }

    // Example 11: Performance timing test
    std.log.info("\n11. Performance timing test...", .{});
    
    const start_time = std.time.milliTimestamp();
    
    var successful_queries: u32 = 0;
    const total_queries: u32 = 5;
    
    var i: u32 = 0;
    while (i < total_queries) : (i += 1) {
        if (mirror_client.getAccountBalances(null, 1)) |test_balances| {
            allocator.free(test_balances);
            successful_queries += 1;
        } else |_| {
            // Count failures but continue
        }
    }
    
    const end_time = std.time.milliTimestamp();
    const elapsed_ms = end_time - start_time;
    
    std.log.info("✓ Performance Test Results:", .{});
    std.log.info("  Total queries: {}", .{total_queries});
    std.log.info("  Successful: {}", .{successful_queries});
    std.log.info("  Failed: {}", .{total_queries - successful_queries});
    std.log.info("  Total time: {} ms", .{elapsed_ms});
    if (successful_queries > 0) {
        std.log.info("  Average time per query: {} ms", .{elapsed_ms / successful_queries});
    }

    // Example 12: Query error handling demonstration
    std.log.info("\n12. Error handling demonstration...", .{});
    
    // Try to query a non-existent account
    const fake_account = hedera.AccountId.init(0, 0, 999999999);
    
    if (mirror_client.getAccount(fake_account)) |_| {
        std.log.info("Unexpected: fake account found", .{});
    } else |err| {
        std.log.info("✓ Expected error for non-existent account: {}", .{err});
    }
    
    // Try to query with invalid parameters
    if (mirror_client.getTransactions(null, "INVALID_TYPE", 1)) |invalid_tx| {
        allocator.free(invalid_tx);
        std.log.info("Unexpected: invalid transaction type accepted", .{});
    } else |err| {
        std.log.info("✓ Expected error for invalid transaction type: {}", .{err});
    }
    
    std.log.info("\nMirror Node queries example completed successfully!", .{});
}