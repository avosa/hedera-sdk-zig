const std = @import("std");
const hedera = @import("hedera");
const json = std.json;
const utils = @import("../utils/utils.zig");

const log = std.log.scoped(.key_service);

// Generate key method
pub fn generateKey(allocator: std.mem.Allocator, params: ?json.Value) !json.Value {
    _ = params; // Key generation doesn't need parameters for now
    
    // Generate a new Ed25519 private key
    var private_key = hedera.generatePrivateKey(allocator) catch |err| {
        log.err("Failed to generate private key: {}", .{err});
        return error.KeyGenerationFailed;
    };
    defer private_key.deinit();
    
    const public_key = private_key.getPublicKey();
    
    // Convert keys to strings
    const private_key_str = try private_key.toString(allocator);
    defer allocator.free(private_key_str);
    const public_key_str = try public_key.toString(allocator);
    defer allocator.free(public_key_str);
    
    // Build response
    var response_fields = json.ObjectMap.init(allocator);
    defer response_fields.deinit();
    
    try response_fields.put("privateKey", json.Value{ .string = try allocator.dupe(u8, private_key_str) });
    try response_fields.put("publicKey", json.Value{ .string = try allocator.dupe(u8, public_key_str) });
    
    return try utils.createResponse(allocator, "SUCCESS", response_fields);
}