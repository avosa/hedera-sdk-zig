const std = @import("std");
const hedera = @import("hedera");
const json = std.json;
const utils = @import("../utils/utils.zig");

const log = std.log.scoped(.sdk_service);

// Setup parameters
pub const SetupParams = struct {
    operatorAccountId: ?[]const u8 = null,
    operatorPrivateKey: ?[]const u8 = null,
    nodeIp: ?[]const u8 = null,
    nodeAccountId: ?[]const u8 = null,
    mirrorNetworkIp: ?[]const u8 = null,
    network: ?[]const u8 = null, // "testnet", "mainnet", "previewnet", or custom
};

// Setup the SDK client
pub fn setup(allocator: std.mem.Allocator, client_ptr: *?*hedera.Client, params: ?json.Value) !json.Value {
    // Clean up existing client if any
    if (client_ptr.*) |client| {
        client.deinit();
        client_ptr.* = null;
    }
    
    // Parse parameters
    var setup_params = SetupParams{};
    if (params) |p| {
        if (utils.getString(p, "operatorAccountId")) |op_id| setup_params.operatorAccountId = op_id;
        if (utils.getString(p, "operatorPrivateKey")) |op_key| setup_params.operatorPrivateKey = op_key;
        if (utils.getString(p, "nodeIp")) |node_ip| setup_params.nodeIp = node_ip;
        if (utils.getString(p, "nodeAccountId")) |node_id| setup_params.nodeAccountId = node_id;
        if (utils.getString(p, "mirrorNetworkIp")) |mirror_ip| setup_params.mirrorNetworkIp = mirror_ip;
        if (utils.getString(p, "network")) |network| setup_params.network = network;
    }
    
    // Create client based on network parameter
    var client: *hedera.Client = undefined;
    
    if (setup_params.network) |network| {
        if (std.mem.eql(u8, network, "testnet")) {
            client = try allocator.create(hedera.Client);
            client.* = try hedera.Client.forTestnet();
            log.info("Client configured for Testnet", .{});
        } else if (std.mem.eql(u8, network, "mainnet")) {
            client = try allocator.create(hedera.Client);
            client.* = try hedera.Client.forMainnet();
            log.info("Client configured for Mainnet", .{});
        } else if (std.mem.eql(u8, network, "previewnet")) {
            client = try allocator.create(hedera.Client);
            client.* = try hedera.Client.forPreviewnet();
            log.info("Client configured for Previewnet", .{});
        } else if (std.mem.eql(u8, network, "local-node")) {
            // For local node, just use testnet for now and modify later
            client = try allocator.create(hedera.Client);
            client.* = try hedera.Client.forTestnet();
            log.info("Client configured for Local Node (using testnet base)", .{});
            
            // Local node network setup would go here
            _ = setup_params.nodeIp;
            _ = setup_params.nodeAccountId;
        } else {
            return error.InvalidNetwork;
        }
    } else {
        // Default to testnet
        client = try allocator.create(hedera.Client);
        client.* = try hedera.Client.forTestnet();
        log.info("Client configured for Testnet (default)", .{});
    }
    
    // Set operator if provided
    if (setup_params.operatorAccountId) |account_id_str| {
        if (setup_params.operatorPrivateKey) |private_key_str| {
            const account_id = try utils.parseAccountId(allocator, account_id_str);
            var private_key = try utils.parsePrivateKey(allocator, private_key_str);
            defer private_key.deinit();
            
            const operator_key = try private_key.toOperatorKey();
            _ = try client.setOperator(account_id, operator_key);
            
            log.info("Operator set: {s}", .{account_id_str});
        }
    }
    
    // Set mirror network if provided
    if (setup_params.mirrorNetworkIp) |mirror_ip| {
        // Mirror network setup would go here
        _ = mirror_ip;
        log.info("Mirror network configuration skipped for now", .{});
    }
    
    // Store client
    client_ptr.* = client;
    
    // Return success status
    return try utils.createResponse(allocator, "SUCCESS", null);
}

// Reset the SDK client
pub fn reset(allocator: std.mem.Allocator, client_ptr: *?*hedera.Client, params: ?json.Value) !json.Value {
    _ = params; // Unused
    
    // Clean up existing client
    if (client_ptr.*) |client| {
        client.deinit();
        allocator.destroy(client);
        client_ptr.* = null;
        log.info("Client reset successfully", .{});
    }
    
    // Return success status
    return try utils.createResponse(allocator, "SUCCESS", null);
}

