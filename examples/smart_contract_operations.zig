const std = @import("std");
const hedera = @import("hedera");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Initialize client for testnet
    var client = try hedera.Client.forTestnet();
    defer client.deinit();

    // Set operator account from environment variables
    const operator_id_str = std.posix.getenv("HEDERA_OPERATOR_ID") orelse {
        std.log.err("HEDERA_OPERATOR_ID environment variable not set", .{});
        return;
    };
    const operator_key_str = std.posix.getenv("HEDERA_OPERATOR_KEY") orelse {
        std.log.err("HEDERA_OPERATOR_KEY environment variable not set", .{});
        return;
    };

    const operator_id = try hedera.AccountId.fromString(allocator, operator_id_str);
    const operator_key = try hedera.PrivateKey.fromString(allocator, operator_key_str);

    const operator_key_converted = try operator_key.toOperatorKey();
    _ = try client.setOperator(operator_id, operator_key_converted);

    std.log.info("Smart Contract Operations Example", .{});
    std.log.info("================================", .{});

    // Simple Solidity contract bytecode for a counter contract
    // pragma solidity ^0.8.0;
    // contract Counter {
    //     uint256 private count = 0;
    //     function increment() public { count += 1; }
    //     function decrement() public { count -= 1; }
    //     function getCount() public view returns (uint256) { return count; }
    // }
    const contract_bytecode = "608060405234801561001057600080fd5b50600080556101b9806100246000396000f3fe608060405234801561001057600080fd5b50600436106100415760003560e01c80632baeceb71461004657806361bc221a1461005c578063d09de08a14610066575b600080fd5b61005e610070565b005b61006461008c565b005b61006e610099565b005b600160008082825461008291906100a8565b9250508190555050565b60008054905090565b6001600060008282546100a59190610103565b92505081905550565b60006100b9826100fd565b91506100c4836100fd565b9250827fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff038211156100f9576100f8610137565b5b828201905092915050565b6000819050919050565b600061011982610166565b915061012483610166565b92508282101561013757610136610137565b5b828203905092915050565b7f4e487b7100000000000000000000000000000000000000000000000000000000600052601160045260246000fd5b600081905091905056fea26469706673582212207c9c02f7a9b0b2e1b5e9e4a0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e064736f6c63430008070033";

    // Example 1: Create and deploy smart contract
    std.log.info("\n1. Deploying smart contract...", .{});
    
    var contract_create_tx = hedera.ContractCreateTransaction.init(allocator);
    defer contract_create_tx.deinit();
    
    const bytecode_bytes = try allocator.alloc(u8, contract_bytecode.len / 2);
    _ = try std.fmt.hexToBytes(bytecode_bytes, contract_bytecode);
    defer allocator.free(bytecode_bytes);
    
    _ = try contract_create_tx.setBytecode(bytecode_bytes);
    _ = try contract_create_tx.setGas(100000);
    _ = try contract_create_tx.setConstructorParameters(&[_]u8{});
    _ = try contract_create_tx.setContractMemo("Contract deployed by Hedera Zig SDK");
    
    var create_response = try contract_create_tx.execute(&client);
    const create_receipt = try create_response.getReceipt(&client);
    
    if (create_receipt.contract_id) |contract_id| {
        std.log.info("✓ Smart contract deployed: {s}", .{try contract_id.toString(allocator)});
        
        // Example 2: Query contract info
        std.log.info("\n2. Querying contract info...", .{});
        
        var contract_info_query = hedera.ContractInfoQuery.init(allocator);
        defer contract_info_query.deinit();
        
        _ = try contract_info_query.setContractId(contract_id);
        const contract_info = try contract_info_query.execute(&client);
        
        std.log.info("✓ Contract ID: {s}", .{try contract_info.contract_id.toString(allocator)});
        std.log.info("✓ Account ID: {s}", .{try contract_info.account_id.toString(allocator)});
        std.log.info("✓ Admin key present: {}", .{contract_info.admin_key != null});
        std.log.info("✓ Storage size: {} bytes", .{contract_info.storage});
        
        // Example 3: Query contract bytecode
        std.log.info("\n3. Querying contract bytecode...", .{});
        
        var bytecode_query = hedera.ContractBytecodeQuery.init(allocator);
        defer bytecode_query.deinit();
        
        _ = try bytecode_query.setContractId(contract_id);
        const bytecode_result = try bytecode_query.execute(&client);
        
        std.log.info("✓ Bytecode retrieved: {} bytes", .{bytecode_result.bytecode.len});
        
        // Example 4: Execute contract function (increment)
        std.log.info("\n4. Calling increment function...", .{});
        
        var contract_execute_tx = hedera.ContractExecuteTransaction.init(allocator);
        defer contract_execute_tx.deinit();
        
        _ = try contract_execute_tx.setContractId(contract_id);
        _ = try contract_execute_tx.setGas(75000);
        
        _ = try contract_execute_tx.setFunction("increment", null);
        
        var execute_response = try contract_execute_tx.execute(&client);
        const execute_receipt = try execute_response.getReceipt(&client);
        
        std.log.info("✓ Increment function called with status: {}", .{execute_receipt.status});
        
        // Example 5: Call contract function (getCount) - read-only
        std.log.info("\n5. Querying count value...", .{});
        
        var contract_call_query = hedera.ContractCallQuery.init(allocator);
        defer contract_call_query.deinit();
        
        _ = try contract_call_query.setContractId(contract_id);
        _ = try contract_call_query.setGas(30000);
        
        _ = try contract_call_query.setFunction("getCount", null);
        
        const call_result = try contract_call_query.execute(&client);
        
        std.log.info("✓ Contract call completed", .{});

        // Get the count value using getUint256
        const count_value = try call_result.getUint256(0);
        std.log.info("✓ Current count value: {any}", .{count_value});
        
        // Example 6: Execute increment function multiple times
        std.log.info("\n6. Incrementing counter multiple times...", .{});
        
        var i: u32 = 0;
        while (i < 3) : (i += 1) {
            var increment_tx = hedera.ContractExecuteTransaction.init(allocator);
            defer increment_tx.deinit();
            
            _ = try increment_tx.setContractId(contract_id);
            _ = try increment_tx.setGas(75000);
            
            _ = try increment_tx.setFunction("increment", null);
            
            var increment_response = try increment_tx.execute(&client);
            const increment_receipt = try increment_response.getReceipt(&client);
            
            std.log.info("✓ Increment #{} completed with status: {}", .{ i + 2, increment_receipt.status });
        }
        
        // Example 7: Query final count
        std.log.info("\n7. Querying final count...", .{});
        
        var final_call_query = hedera.ContractCallQuery.init(allocator);
        defer final_call_query.deinit();
        
        _ = try final_call_query.setContractId(contract_id);
        _ = try final_call_query.setGas(30000);
        
        _ = try final_call_query.setFunction("getCount", null);
        
        const final_result = try final_call_query.execute(&client);

        const final_count = try final_result.getUint256(0);
        std.log.info("✓ Final count value: {any}", .{final_count});
        
        // Example 8: Execute decrement function
        std.log.info("\n8. Calling decrement function...", .{});
        
        var decrement_tx = hedera.ContractExecuteTransaction.init(allocator);
        defer decrement_tx.deinit();
        
        _ = try decrement_tx.setContractId(contract_id);
        _ = try decrement_tx.setGas(75000);
        
        _ = try decrement_tx.setFunction("decrement", null);
        
        var decrement_response = try decrement_tx.execute(&client);
        const decrement_receipt = try decrement_response.getReceipt(&client);
        
        std.log.info("✓ Decrement function called with status: {}", .{decrement_receipt.status});
        
        // Example 9: Query count after decrement
        std.log.info("\n9. Querying count after decrement...", .{});
        
        var after_decrement_query = hedera.ContractCallQuery.init(allocator);
        defer after_decrement_query.deinit();
        
        _ = try after_decrement_query.setContractId(contract_id);
        _ = try after_decrement_query.setGas(30000);
        
        _ = try after_decrement_query.setFunction("getCount", null);

        const after_result = try after_decrement_query.execute(&client);

        const after_count = try after_result.getUint256(0);
        std.log.info("✓ Count after decrement: {any}", .{after_count});
        
        std.log.info("✓ Smart contract operations completed successfully!", .{});
        
    } else {
        std.log.err("Failed to get contract ID from receipt", .{});
    }
    
    std.log.info("\nSmart contract operations example completed successfully!", .{});
}