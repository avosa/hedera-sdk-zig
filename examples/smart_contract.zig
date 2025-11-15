const std = @import("std");
const hedera = @import("hedera");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Match Go SDK pattern: ClientForName
    var client = try hedera.clientForName(std.posix.getenv("HEDERA_NETWORK") orelse "testnet");
    defer client.deinit();

    // Match Go SDK pattern: AccountIDFromString and PrivateKeyFromString
    const operator_id_str = std.posix.getenv("OPERATOR_ID") orelse {
        std.log.err("OPERATOR_ID environment variable not set", .{});
        return;
    };
    const operator_key_str = std.posix.getenv("OPERATOR_KEY") orelse {
        std.log.err("OPERATOR_KEY environment variable not set", .{});
        return;
    };

    const operator_id = try hedera.accountIdFromString(allocator, operator_id_str);
    var operator_key = try hedera.privateKeyFromString(allocator, operator_key_str);
    defer operator_key.deinit();

    // Match Go SDK pattern: SetOperator
    const operator_key_converted = try operator_key.toOperatorKey();
    _ = try client.setOperator(operator_id, operator_key_converted);
    
    std.log.info("Smart Contract Example", .{});
    std.log.info("=====================", .{});
    
    // Simple storage contract bytecode (stores and retrieves a uint256)
    // pragma solidity ^0.8.0;
    // contract SimpleStorage {
    //     uint256 public storedData;
    //     constructor(uint256 initVal) { storedData = initVal; }
    //     function set(uint256 x) public { storedData = x; }
    //     function get() public view returns (uint256) { return storedData; }
    // }
    const bytecode = "608060405234801561001057600080fd5b506040516101c83803806101c88339818101604052810190610032919061007a565b80600081905550506100a7565b600080fd5b6000819050919050565b61005781610044565b811461006257600080fd5b50565b6000815190506100748161004e565b92915050565b6000602082840312156100905761008f61003f565b5b600061009e84828501610065565b91505092915050565b610112806100b66000396000f3fe6080604052348015600f57600080fd5b506004361060325760003560e01c806360fe47b11460375780636d4ce63c14604f575b600080fd5b604d600480360381019060499190609b565b6069565b005b60556073565b604051606091906099565b60405180910390f35b8060008190555050565b60008054905090565b600081905091565b6000819050919050565b6093816082565b8201565b50565b600060208201905060ae6000830184608c565b92915050565b600060b48261607c565b91506000820361013573ffffffffffffffffffffffffffffffffffffffff16815260200191505056fea2646970667358fe1220e0b46a978c20dd9f43a8c5a9e0c6b3d6f4a1b9c7e8f2d3c4b5a6978d8e7f6c64736f6c63430008120033";
    
    // Create file with contract bytecode
    var file_create = hedera.FileCreateTransaction.init(allocator);
    defer file_create.deinit();

    _ = try file_create.setContents(bytecode);
    _ = try file_create.addKey(hedera.Key.fromPublicKey(operator_key.getPublicKey()));

    var file_response = try file_create.execute(&client);
    const file_receipt = try file_response.getReceipt(&client);
    
    const file_id = file_receipt.file_id orelse {
        std.log.err("Failed to get file ID", .{});
        return;
    };
    
    std.log.info("Created file: {s}", .{try file_id.toString(allocator)});
    
    // Create contract with initial value of 42
    var contract_create = hedera.ContractCreateTransaction.init(allocator);
    defer contract_create.deinit();
    
    _ = try contract_create.setBytecodeFileId(file_id);
    _ = try contract_create.setGas(100000);
    
    // Set constructor parameters (uint256 = 42)
    var params = hedera.ContractFunctionParameters.init(allocator);
    defer params.deinit();
    try params.addUint256(42);
    
    _ = try contract_create.setConstructorParameters(try params.toBytes());
    _ = try contract_create.setContractMemo("Simple Storage Contract");
    
    var contract_response = try contract_create.execute(&client);
    const contract_receipt = try contract_response.getReceipt(&client);
    
    const contract_id = contract_receipt.contract_id orelse {
        std.log.err("Failed to get contract ID", .{});
        return;
    };
    
    std.log.info("Created contract: {s}", .{try contract_id.toString(allocator)});
    
    // Call contract get() function
    var contract_query = hedera.ContractCallQuery.init(allocator);
    defer contract_query.deinit();
    
    _ = try contract_query.setContractId(contract_id);
    _ = try contract_query.setGas(30000);
    _ = try contract_query.setFunction("get", null);
    
    const query_result = try contract_query.execute(&client);
    const stored_value = try query_result.getUint256(0);

    std.log.info("Initial stored value: {any}", .{stored_value});
    
    // Execute contract set() function with new value
    var contract_execute = hedera.ContractExecuteTransaction.init(allocator);
    defer contract_execute.deinit();
    
    _ = try contract_execute.setContractId(contract_id);
    _ = try contract_execute.setGas(30000);
    
    var set_params = hedera.ContractFunctionParameters.init(allocator);
    defer set_params.deinit();
    try set_params.addUint256(123);
    
    _ = try contract_execute.setFunction("set", &set_params);
    
    var execute_response = try contract_execute.execute(&client);
    const execute_receipt = try execute_response.getReceipt(&client);
    
    std.log.info("Set function executed with status: {}", .{execute_receipt.status});
    
    // Query the new value
    var final_query = hedera.ContractCallQuery.init(allocator);
    defer final_query.deinit();
    
    _ = try final_query.setContractId(contract_id);
    _ = try final_query.setGas(30000);
    _ = try final_query.setFunction("get", null);
    
    const final_result = try final_query.execute(&client);
    const final_value = try final_result.getUint256(0);

    std.log.info("Final stored value: {any}", .{final_value});
}