const std = @import("std");
const hedera = @import("hedera");
const json = std.json;
const utils = @import("../utils/utils.zig");
pub fn createNode(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    if (client == null) {
        return json.Value{ .object = (try utils.createErrorMap(allocator, "Client not configured")) };
    }
    const p = params orelse return json.Value{ .object = (try utils.createErrorMap(allocator, "Invalid parameters")) };
    const account_id = try utils.getStringParam(p, "accountId");
    const description = try utils.getOptionalStringParam(p, "description");
    const gossip_endpoint = try utils.getOptionalStringParam(p, "gossipEndpoint");
    const service_endpoint = try utils.getOptionalStringParam(p, "serviceEndpoint");
    const admin_key = try utils.getOptionalStringParam(p, "adminKey");
    const gossip_ca_certificate = try utils.getOptionalStringParam(p, "gossipCaCertificate");
    const grpc_certificate_hash = try utils.getOptionalStringParam(p, "grpcCertificateHash");
    var tx = hedera.NodeCreateTransaction.init(allocator);
    defer tx.deinit();
    const acc_id = try hedera.AccountId.fromString(allocator, account_id);
    _ = try tx.setAccountId(acc_id);
    if (description) |desc| {
        _ = try tx.setDescription(desc);
    }
    if (gossip_endpoint) |endpoint| {
        var parts = std.mem.splitScalar(u8, endpoint, ':');
        var ip_str: []const u8 = "";
        var port_str: []const u8 = "50211";
        if (parts.next()) |ip| {
            ip_str = ip;
        }
        if (parts.next()) |port| {
            port_str = port;
        }
        const port = try std.fmt.parseInt(u16, port_str, 10);
        const endpoint_obj = hedera.NodeServiceEndpoint{
            .ip_address = ip_str,
            .port = @as(u32, @intCast(port)),
            .domain_name = "",
        };
        try tx.addGossipEndpoint(endpoint_obj);
    }
    if (service_endpoint) |endpoint| {
        var parts = std.mem.splitScalar(u8, endpoint, ':');
        var ip_str: []const u8 = "";
        var port_str: []const u8 = "50211";
        if (parts.next()) |ip| {
            ip_str = ip;
        }
        if (parts.next()) |port| {
            port_str = port;
        }
        const port = try std.fmt.parseInt(u16, port_str, 10);
        const endpoint_obj = hedera.NodeServiceEndpoint{
            .ip_address = ip_str,
            .port = @as(u32, @intCast(port)),
            .domain_name = "",
        };
        try tx.addServiceEndpoint(endpoint_obj);
    }
    if (admin_key) |key_str| {
        const key = try utils.parseKey(allocator, key_str);
        _ = try tx.setAdminKey(key);
    }
    if (gossip_ca_certificate) |cert| {
        _ = try tx.setGossipCaCertificate(cert);
    }
    if (grpc_certificate_hash) |hash| {
        const decoded_size = std.base64.standard.Decoder.calcSizeForSlice(hash) catch return error.InvalidBase64;
        const decoded = try allocator.alloc(u8, decoded_size);
        defer allocator.free(decoded);
        _ = try std.base64.standard.Decoder.decode(decoded, hash);
        _ = try tx.setGrpcCertificateHash(decoded);
    }
    var response = try tx.execute(client.?);
    defer response.deinit();
    var receipt = try response.getReceipt(client.?);
    defer receipt.deinit();
    var result = std.json.ObjectMap.init(allocator);
    try result.put("nodeId", json.Value{ .integer = @intCast(receipt.node_id) });
    try result.put("status", json.Value{ .string = @tagName(receipt.status) });
    return json.Value{ .object = result };
}
pub fn updateNode(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    if (client == null) {
        return json.Value{ .object = (try utils.createErrorMap(allocator, "Client not configured")) };
    }
    const p = params orelse return json.Value{ .object = (try utils.createErrorMap(allocator, "Invalid parameters")) };
    const node_id = try utils.getNumberParam(p, "nodeId");
    const account_id = try utils.getOptionalStringParam(p, "accountId");
    const description = try utils.getOptionalStringParam(p, "description");
    const gossip_endpoint = try utils.getOptionalStringParam(p, "gossipEndpoint");
    const service_endpoint = try utils.getOptionalStringParam(p, "serviceEndpoint");
    const admin_key = try utils.getOptionalStringParam(p, "adminKey");
    const gossip_ca_certificate = try utils.getOptionalStringParam(p, "gossipCaCertificate");
    const grpc_certificate_hash = try utils.getOptionalStringParam(p, "grpcCertificateHash");
    var tx = hedera.NodeUpdateTransaction.init(allocator);
    defer tx.deinit();
    _ = try tx.setNodeId(@intCast(node_id));
    if (account_id) |acc_str| {
        const acc_id = try hedera.AccountId.fromString(allocator, acc_str);
        _ = try tx.setAccountId(acc_id);
    }
    if (description) |desc| {
        _ = try tx.setDescription(desc);
    }
    _ = gossip_endpoint;
    _ = service_endpoint;
    if (admin_key) |key_str| {
        const key = try utils.parseKey(allocator, key_str);
        _ = try tx.setAdminKey(key);
    }
    if (gossip_ca_certificate) |cert| {
        _ = try tx.setGossipCaCertificate(cert);
    }
    if (grpc_certificate_hash) |hash| {
        const decoded_size = std.base64.standard.Decoder.calcSizeForSlice(hash) catch return error.InvalidBase64;
        const decoded = try allocator.alloc(u8, decoded_size);
        defer allocator.free(decoded);
        _ = try std.base64.standard.Decoder.decode(decoded, hash);
        _ = try tx.setGrpcCertificateHash(decoded);
    }
    var response = try tx.execute(client.?);
    defer response.deinit();
    var receipt = try response.getReceipt(client.?);
    defer receipt.deinit();
    var result = std.json.ObjectMap.init(allocator);
    try result.put("status", json.Value{ .string = @tagName(receipt.status) });
    return json.Value{ .object = result };
}
pub fn deleteNode(allocator: std.mem.Allocator, client: ?*hedera.Client, params: ?json.Value) !json.Value {
    if (client == null) {
        return json.Value{ .object = (try utils.createErrorMap(allocator, "Client not configured")) };
    }
    const p = params orelse return json.Value{ .object = (try utils.createErrorMap(allocator, "Invalid parameters")) };
    const node_id = try utils.getNumberParam(p, "nodeId");
    var tx = hedera.NodeDeleteTransaction.init(allocator);
    defer tx.deinit();
    _ = try tx.setNodeId(@intCast(node_id));
    var response = try tx.execute(client.?);
    defer response.deinit();
    var receipt = try response.getReceipt(client.?);
    defer receipt.deinit();
    var result = std.json.ObjectMap.init(allocator);
    try result.put("status", json.Value{ .string = @tagName(receipt.status) });
    return json.Value{ .object = result };
}