const std = @import("std");
const hedera = @import("hedera");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    std.log.info("Hedera Cryptography Demo", .{});
    std.log.info("========================", .{});

    // Example 1: ED25519 Key Generation and Operations
    std.log.info("\n1. ED25519 Key Operations...", .{});
    
    var ed25519_key = try hedera.PrivateKey.generateEd25519(allocator);
    defer ed25519_key.deinit();
    
    const ed25519_public = ed25519_key.getPublicKey();
    
    std.log.info("✓ ED25519 private key generated", .{});
    std.log.info("✓ Private key length: {} bytes", .{ed25519_key.getBytes().len});
    std.log.info("✓ Public key length: {} bytes", .{ed25519_public.getBytes().len});
    
    // Convert to strings and back
    const ed25519_private_str = try ed25519_key.toString(allocator);
    defer allocator.free(ed25519_private_str);
    
    const ed25519_public_str = try ed25519_public.toString(allocator);
    defer allocator.free(ed25519_public_str);
    
    std.log.info("✓ Private key string: {s}", .{ed25519_private_str[0..@min(50, ed25519_private_str.len)]});
    std.log.info("✓ Public key string: {s}", .{ed25519_public_str[0..@min(50, ed25519_public_str.len)]});
    
    // Reconstruct from strings
    var reconstructed_private = try hedera.PrivateKey.fromString(allocator, ed25519_private_str);
    defer reconstructed_private.deinit();
    
    var reconstructed_public = try hedera.PublicKey.fromString(allocator, ed25519_public_str);
    defer reconstructed_public.deinit(allocator);
    
    std.log.info("✓ Keys successfully reconstructed from strings", .{});

    // Example 2: ECDSA secp256k1 Key Generation and Operations
    std.log.info("\n2. ECDSA secp256k1 Key Operations...", .{});
    
    var ecdsa_key = try hedera.PrivateKey.generateEcdsa(allocator);
    defer ecdsa_key.deinit();
    
    const ecdsa_public = ecdsa_key.getPublicKey();
    
    std.log.info("✓ ECDSA secp256k1 private key generated", .{});
    std.log.info("✓ Private key length: {} bytes", .{ecdsa_key.getBytes().len});
    std.log.info("✓ Public key length: {} bytes", .{ecdsa_public.getBytes().len});
    
    const ecdsa_private_str = try ecdsa_key.toString(allocator);
    defer allocator.free(ecdsa_private_str);
    
    const ecdsa_public_str = try ecdsa_public.toString(allocator);
    defer allocator.free(ecdsa_public_str);
    
    std.log.info("✓ ECDSA private key string: {s}", .{ecdsa_private_str[0..@min(50, ecdsa_private_str.len)]});
    std.log.info("✓ ECDSA public key string: {s}", .{ecdsa_public_str[0..@min(50, ecdsa_public_str.len)]});

    // Example 3: Digital Signatures
    std.log.info("\n3. Digital Signature Operations...", .{});
    
    const message_to_sign = "Hello, Hedera! This is a test message for digital signatures.";
    
    // ED25519 signing
    const ed25519_signature = try ed25519_key.sign(message_to_sign);
    defer allocator.free(ed25519_signature);
    
    std.log.info("✓ ED25519 signature created: {} bytes", .{ed25519_signature.len});
    
    // ED25519 verification
    const ed25519_valid = try ed25519_public.verify(message_to_sign, ed25519_signature);
    std.log.info("✓ ED25519 signature valid: {}", .{ed25519_valid});
    
    // ECDSA signing
    const ecdsa_signature = try ecdsa_key.sign(message_to_sign);
    defer allocator.free(ecdsa_signature);
    
    std.log.info("✓ ECDSA signature created: {} bytes", .{ecdsa_signature.len});
    
    // ECDSA verification
    const ecdsa_valid = try ecdsa_public.verify(message_to_sign, ecdsa_signature);
    std.log.info("✓ ECDSA signature valid: {}", .{ecdsa_valid});

    // Example 4: Mnemonic Generation and Key Derivation
    std.log.info("\n4. Mnemonic and Key Derivation...", .{});
    
    var mnemonic = try hedera.Mnemonic.generate24(allocator);
    defer mnemonic.deinit();
    
    const mnemonic_words = try mnemonic.toString(allocator);
    defer allocator.free(mnemonic_words);
    
    std.log.info("✓ 24-word mnemonic generated", .{});
    std.log.info("✓ First few words: {s}", .{mnemonic_words[0..@min(50, mnemonic_words.len)]});
    
    // Derive key from mnemonic
    var derived_key = try mnemonic.toPrivateKey("", allocator);
    defer derived_key.deinit();
    
    std.log.info("✓ Private key derived from mnemonic", .{});
    
    // Derive specific account key (using derivation path)
    var account_key = try derived_key.derive("m/44'/3030'/0'/0'/0'", allocator);
    defer account_key.deinit();
    
    std.log.info("✓ Account-specific key derived", .{});

    // Example 5: Key Validation and Error Handling
    std.log.info("\n5. Key Validation and Error Handling...", .{});
    
    // Test invalid key strings
    const invalid_keys = [_][]const u8{
        "invalid_key_string",
        "302e020100300506032b657004220420", // Too short
        "not_hex_at_all",
        "", // Empty
    };
    
    for (invalid_keys, 0..) |invalid_key, i| {
        if (hedera.PrivateKey.fromString(allocator, invalid_key)) |_| {
            std.log.warn("Unexpected: invalid key {} was accepted", .{i + 1});
        } else |err| {
            std.log.info("✓ Invalid key {} correctly rejected: {}", .{ i + 1, err });
        }
    }

    // Example 6: Key Serialization Formats
    std.log.info("\n6. Key Serialization Formats...", .{});
    
    // DER encoding
    const der_bytes = try ed25519_key.toDer(allocator);
    defer allocator.free(der_bytes);
    
    std.log.info("✓ DER encoded key: {} bytes", .{der_bytes.len});
    
    // PEM encoding
    const pem_string = try ed25519_key.toPem(allocator);
    defer allocator.free(pem_string);
    
    std.log.info("✓ PEM encoded key: {} characters", .{pem_string.len});
    std.log.info("✓ PEM header: {s}", .{pem_string[0..@min(30, pem_string.len)]});
    
    // Raw bytes
    const raw_bytes = ed25519_key.getBytes();
    std.log.info("✓ Raw key bytes: {} bytes", .{raw_bytes.len});

    // Example 7: Key List and Threshold Keys
    std.log.info("\n7. Composite Key Structures...", .{});
    
    // Create key list
    var key_list = hedera.KeyList.init(allocator);
    defer key_list.deinit();
    
    try key_list.addKey(hedera.Key.fromPublicKey(ed25519_public));
    try key_list.addKey(hedera.Key.fromPublicKey(ecdsa_public));
    
    std.log.info("✓ Key list created with {} keys", .{key_list.keys.items.len});
    
    // Create threshold key
    var threshold_key = hedera.ThresholdKey.init(allocator, 2);
    defer threshold_key.deinit();
    
    try threshold_key.addKey(hedera.Key.fromPublicKey(ed25519_public));
    try threshold_key.addKey(hedera.Key.fromPublicKey(ecdsa_public));
    
    var additional_key = try hedera.PrivateKey.generateEd25519(allocator);
    defer additional_key.deinit();
    
    try threshold_key.addKey(hedera.Key.fromPublicKey(additional_key.getPublicKey()));
    
    std.log.info("✓ Threshold key created: {}/{} required", .{ threshold_key.threshold, threshold_key.keys.items.len });

    // Example 8: Performance Benchmarking
    std.log.info("\n8. Performance Benchmarking...", .{});
    
    const benchmark_iterations = 100;
    
    // ED25519 key generation benchmark
    const ed25519_start = std.time.milliTimestamp();
    var i: u32 = 0;
    while (i < benchmark_iterations) : (i += 1) {
        var bench_key = try hedera.PrivateKey.generateEd25519(allocator);
        bench_key.deinit();
    }
    const ed25519_end = std.time.milliTimestamp();
    
    std.log.info("✓ ED25519 key generation: {} keys/sec", .{(benchmark_iterations * 1000) / @as(u32, @intCast(ed25519_end - ed25519_start))});
    
    // Signature benchmark
    const sign_iterations = 50;
    const sign_start = std.time.milliTimestamp();
    var j: u32 = 0;
    while (j < sign_iterations) : (j += 1) {
        const bench_sig = try ed25519_key.sign(message_to_sign);
        allocator.free(bench_sig);
    }
    const sign_end = std.time.milliTimestamp();
    
    std.log.info("✓ ED25519 signing: {} signatures/sec", .{(sign_iterations * 1000) / @as(u32, @intCast(sign_end - sign_start))});
    
    // Verification benchmark
    const verify_signature = try ed25519_key.sign(message_to_sign);
    defer allocator.free(verify_signature);
    
    const verify_start = std.time.milliTimestamp();
    var k: u32 = 0;
    while (k < sign_iterations) : (k += 1) {
        _ = try ed25519_public.verify(message_to_sign, verify_signature);
    }
    const verify_end = std.time.milliTimestamp();
    
    std.log.info("✓ ED25519 verification: {} verifications/sec", .{(sign_iterations * 1000) / @as(u32, @intCast(verify_end - verify_start))});

    // Example 9: Cross-validation with Known Test Vectors
    std.log.info("\n9. Cross-validation with Test Vectors...", .{});
    
    // Known ED25519 test vector
    const test_private_hex = "302e020100300506032b657004220420db484b828e64b2d8f12ce3c0a0e93a0b8cce7af1bb8f39c97732394482538e10";
    const test_message = "test message";
    
    if (hedera.PrivateKey.fromString(allocator, test_private_hex)) |test_key| {
        defer test_key.deinit();
        
        const test_signature = try test_key.sign(test_message);
        defer allocator.free(test_signature);
        
        const test_public = test_key.getPublicKey();
        const signature_valid = try test_public.verify(test_message, test_signature);
        
        std.log.info("✓ Test vector validation: {}", .{signature_valid});
        
    } else |err| {
        std.log.warn("Test vector validation failed: {}", .{err});
    }

    std.log.info("\nCryptography demo completed successfully!", .{});
}