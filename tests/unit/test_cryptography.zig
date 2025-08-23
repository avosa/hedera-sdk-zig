const std = @import("std");
const testing = std.testing;
const hedera = @import("hedera");

test "ED25519 key generation and operations" {
    const allocator = testing.allocator;
    
    // Test key generation
    var private_key = try hedera.PrivateKey.generateEd25519(allocator);
    defer private_key.deinit();
    
    // Test key properties
    try testing.expectEqual(@as(usize, 32), private_key.getBytes().len);
    
    const public_key = private_key.getPublicKey();
    try testing.expectEqual(@as(usize, 32), public_key.getBytes().len);
    
    // Test string conversion
    const private_str = try private_key.toString(allocator);
    defer allocator.free(private_str);
    
    const public_str = try public_key.toString(allocator);
    defer allocator.free(public_str);
    
    try testing.expect(private_str.len > 0);
    try testing.expect(public_str.len > 0);
    
    // Test reconstruction from string
    var reconstructed_private = try hedera.PrivateKey.fromString(private_str, allocator);
    defer reconstructed_private.deinit();
    
    var reconstructed_public = try hedera.PublicKey.fromString(public_str, allocator);
    defer reconstructed_public.deinit();
    
    // Verify reconstructed keys match original
    try testing.expectEqualSlices(u8, private_key.getBytes(), reconstructed_private.getBytes());
    try testing.expectEqualSlices(u8, public_key.getBytes(), reconstructed_public.getBytes());
}

test "ECDSA secp256k1 key generation and operations" {
    const allocator = testing.allocator;
    
    // Test key generation
    var private_key = try hedera.PrivateKey.generateEcdsa(allocator);
    defer private_key.deinit();
    
    // Test key properties
    try testing.expectEqual(@as(usize, 32), private_key.getBytes().len);
    
    const public_key = private_key.getPublicKey();
    try testing.expectEqual(@as(usize, 33), public_key.getBytes().len); // Compressed format
    
    // Test string conversion
    const private_str = try private_key.toString(allocator);
    defer allocator.free(private_str);
    
    const public_str = try public_key.toString(allocator);
    defer allocator.free(public_str);
    
    try testing.expect(private_str.len > 0);
    try testing.expect(public_str.len > 0);
    
    // Test reconstruction from string
    var reconstructed_private = try hedera.PrivateKey.fromString(private_str, allocator);
    defer reconstructed_private.deinit();
    
    var reconstructed_public = try hedera.PublicKey.fromString(public_str, allocator);
    defer reconstructed_public.deinit();
    
    // Verify reconstructed keys match original
    try testing.expectEqualSlices(u8, private_key.getBytes(), reconstructed_private.getBytes());
    try testing.expectEqualSlices(u8, public_key.getBytes(), reconstructed_public.getBytes());
}

test "Digital signatures and verification" {
    const allocator = testing.allocator;
    const message = "Hello, Hedera Hashgraph! This is a test message for digital signatures.";
    
    // Test ED25519 signatures
    var ed25519_key = try hedera.PrivateKey.generateEd25519(allocator);
    defer ed25519_key.deinit();
    
    const ed25519_signature = try ed25519_key.sign(message);
    defer allocator.free(ed25519_signature);
    
    try testing.expectEqual(@as(usize, 64), ed25519_signature.len);
    
    const ed25519_public = ed25519_key.getPublicKey();
    const ed25519_valid = try ed25519_public.verify(message, ed25519_signature);
    try testing.expect(ed25519_valid);
    
    // Test ECDSA signatures
    var ecdsa_key = try hedera.PrivateKey.generateEcdsa(allocator);
    defer ecdsa_key.deinit();
    
    const ecdsa_signature = try ecdsa_key.sign(message);
    defer allocator.free(ecdsa_signature);
    
    // ECDSA signatures are variable length but typically 64-72 bytes
    try testing.expect(ecdsa_signature.len >= 64 and ecdsa_signature.len <= 72);
    
    const ecdsa_public = ecdsa_key.getPublicKey();
    const ecdsa_valid = try ecdsa_public.verify(message, ecdsa_signature);
    try testing.expect(ecdsa_valid);
    
    // Test signature verification with wrong message
    const wrong_message = "This is a different message";
    const ed25519_invalid = try ed25519_public.verify(wrong_message, ed25519_signature);
    try testing.expect(!ed25519_invalid);
    
    const ecdsa_invalid = try ecdsa_public.verify(wrong_message, ecdsa_signature);
    try testing.expect(!ecdsa_invalid);
    
    // Test signature verification with wrong key
    var other_ed25519_key = try hedera.PrivateKey.generateEd25519(allocator);
    defer other_ed25519_key.deinit();
    
    const other_ed25519_public = other_ed25519_key.getPublicKey();
    const cross_verification = try other_ed25519_public.verify(message, ed25519_signature);
    try testing.expect(!cross_verification);
}

test "Key serialization formats" {
    const allocator = testing.allocator;
    
    var private_key = try hedera.PrivateKey.generateEd25519(allocator);
    defer private_key.deinit();
    
    // Test DER encoding
    const der_bytes = try private_key.toDer(allocator);
    defer allocator.free(der_bytes);
    
    try testing.expect(der_bytes.len > 32); // DER encoding adds structure
    
    // Test PEM encoding
    const pem_string = try private_key.toPem(allocator);
    defer allocator.free(pem_string);
    
    try testing.expect(std.mem.startsWith(u8, pem_string, "-----BEGIN PRIVATE KEY-----"));
    try testing.expect(std.mem.endsWith(u8, pem_string, "-----END PRIVATE KEY-----\n"));
    
    // Test reconstruction from DER
    var from_der = try hedera.PrivateKey.fromDer(der_bytes, allocator);
    defer from_der.deinit();
    
    try testing.expectEqualSlices(u8, private_key.getBytes(), from_der.getBytes());
    
    // Test reconstruction from PEM
    var from_pem = try hedera.PrivateKey.fromPem(pem_string, allocator);
    defer from_pem.deinit();
    
    try testing.expectEqualSlices(u8, private_key.getBytes(), from_pem.getBytes());
    
    // Test public key serialization
    const public_key = private_key.getPublicKey();
    
    const public_der = try public_key.toDer(allocator);
    defer allocator.free(public_der);
    
    const public_pem = try public_key.toPem(allocator);
    defer allocator.free(public_pem);
    
    try testing.expect(public_der.len > 32);
    try testing.expect(std.mem.startsWith(u8, public_pem, "-----BEGIN PUBLIC KEY-----"));
    try testing.expect(std.mem.endsWith(u8, public_pem, "-----END PUBLIC KEY-----\n"));
}

test "Mnemonic generation and key derivation" {
    const allocator = testing.allocator;
    
    // Test 12-word mnemonic
    var mnemonic12 = try hedera.Mnemonic.generate12(allocator);
    defer mnemonic12.deinit();
    
    const words12 = try mnemonic12.toString(allocator);
    defer allocator.free(words12);
    
    const word_count12 = std.mem.count(u8, words12, " ") + 1;
    try testing.expectEqual(@as(usize, 12), word_count12);
    
    // Test 24-word mnemonic
    var mnemonic24 = try hedera.Mnemonic.generate24(allocator);
    defer mnemonic24.deinit();
    
    const words24 = try mnemonic24.toString(allocator);
    defer allocator.free(words24);
    
    const word_count24 = std.mem.count(u8, words24, " ") + 1;
    try testing.expectEqual(@as(usize, 24), word_count24);
    
    // Test key derivation from mnemonic
    var derived_key = try mnemonic24.toPrivateKey("", allocator);
    defer derived_key.deinit();
    
    try testing.expectEqual(@as(usize, 32), derived_key.getBytes().len);
    
    // Test key derivation with passphrase
    var derived_key_with_passphrase = try mnemonic24.toPrivateKey("test_passphrase", allocator);
    defer derived_key_with_passphrase.deinit();
    
    // Keys should be different with different passphrases
    try testing.expect(!std.mem.eql(u8, derived_key.getBytes(), derived_key_with_passphrase.getBytes()));
    
    // Test mnemonic reconstruction
    var reconstructed_mnemonic = try hedera.Mnemonic.fromString(words24, allocator);
    defer reconstructed_mnemonic.deinit();
    
    var reconstructed_key = try reconstructed_mnemonic.toPrivateKey("", allocator);
    defer reconstructed_key.deinit();
    
    try testing.expectEqualSlices(u8, derived_key.getBytes(), reconstructed_key.getBytes());
    
    // Test hierarchical deterministic key derivation
    var account_key = try derived_key.derive("m/44'/3030'/0'/0'/0'", allocator);
    defer account_key.deinit();
    
    var account_key2 = try derived_key.derive("m/44'/3030'/0'/0'/1'", allocator);
    defer account_key2.deinit();
    
    // Different derivation paths should produce different keys
    try testing.expect(!std.mem.eql(u8, account_key.getBytes(), account_key2.getBytes()));
}

test "Key validation and error handling" {
    const allocator = testing.allocator;
    
    // Test invalid key strings
    const invalid_keys = [_][]const u8{
        "",
        "invalid_hex",
        "302e020100300506032b657004220420", // Too short
        "not_a_key_at_all",
        "12345", // Too short hex
    };
    
    for (invalid_keys) |invalid_key| {
        try testing.expectError(error.InvalidPrivateKey, hedera.PrivateKey.fromString(invalid_key, allocator));
    }
    
    // Test invalid public key strings
    const invalid_public_keys = [_][]const u8{
        "",
        "invalid_hex",
        "302a300506032b6570032100", // Too short
        "not_a_public_key",
    };
    
    for (invalid_public_keys) |invalid_key| {
        try testing.expectError(error.InvalidPublicKey, hedera.PublicKey.fromString(invalid_key, allocator));
    }
    
    // Test invalid mnemonic phrases
    const invalid_mnemonics = [_][]const u8{
        "",
        "invalid mnemonic phrase",
        "one two three", // Too short
        "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about invalid", // Invalid checksum
    };
    
    for (invalid_mnemonics) |invalid_mnemonic| {
        try testing.expectError(error.InvalidMnemonic, hedera.Mnemonic.fromString(invalid_mnemonic, allocator));
    }
}

test "Key type detection and compatibility" {
    const allocator = testing.allocator;
    
    // Generate both key types
    var ed25519_key = try hedera.PrivateKey.generateEd25519(allocator);
    defer ed25519_key.deinit();
    
    var ecdsa_key = try hedera.PrivateKey.generateEcdsa(allocator);
    defer ecdsa_key.deinit();
    
    // Test key type detection
    try testing.expect(ed25519_key.isEd25519());
    try testing.expect(!ed25519_key.isEcdsa());
    
    try testing.expect(ecdsa_key.isEcdsa());
    try testing.expect(!ecdsa_key.isEd25519());
    
    // Test public key type detection
    const ed25519_public = ed25519_key.getPublicKey();
    const ecdsa_public = ecdsa_key.getPublicKey();
    
    try testing.expect(ed25519_public.isEd25519());
    try testing.expect(!ed25519_public.isEcdsa());
    
    try testing.expect(ecdsa_public.isEcdsa());
    try testing.expect(!ecdsa_public.isEd25519());
    
    // Test cross-type operations should fail
    const message = "test message";
    const ed25519_signature = try ed25519_key.sign(message);
    defer allocator.free(ed25519_signature);
    
    // ECDSA public key should not verify ED25519 signature
    const cross_verify = try ecdsa_public.verify(message, ed25519_signature);
    try testing.expect(!cross_verify);
}

test "Composite key structures" {
    const allocator = testing.allocator;
    
    // Create individual keys
    var key1 = try hedera.PrivateKey.generateEd25519(allocator);
    defer key1.deinit();
    
    var key2 = try hedera.PrivateKey.generateEcdsa(allocator);
    defer key2.deinit();
    
    var key3 = try hedera.PrivateKey.generateEd25519(allocator);
    defer key3.deinit();
    
    // Test KeyList
    var key_list = hedera.KeyList.init(allocator);
    defer key_list.deinit();
    
    _ = try key_list.addKey(hedera.Key.fromPublicKey(key1.getPublicKey()));
    _ = try key_list.addKey(hedera.Key.fromPublicKey(key2.getPublicKey()));
    _ = try key_list.addKey(hedera.Key.fromPublicKey(key3.getPublicKey()));
    
    try testing.expectEqual(@as(usize, 3), key_list.keys.items.len);
    
    // Test ThresholdKey
    var threshold_key = hedera.ThresholdKey.init(allocator, 2);
    defer threshold_key.deinit();
    
    _ = try threshold_key.addKey(hedera.Key.fromPublicKey(key1.getPublicKey()));
    _ = try threshold_key.addKey(hedera.Key.fromPublicKey(key2.getPublicKey()));
    _ = try threshold_key.addKey(hedera.Key.fromPublicKey(key3.getPublicKey()));
    
    try testing.expectEqual(@as(u32, 2), threshold_key.threshold);
    try testing.expectEqual(@as(usize, 3), threshold_key.keys.items.len);
    
    // Test protobuf serialization
    const key_list_bytes = try key_list.toProtobuf(allocator);
    defer allocator.free(key_list_bytes);
    
    const threshold_bytes = try threshold_key.toProtobuf(allocator);
    defer allocator.free(threshold_bytes);
    
    try testing.expect(key_list_bytes.len > 0);
    try testing.expect(threshold_bytes.len > 0);
    
    // Threshold key serialization should be different from key list
    try testing.expect(!std.mem.eql(u8, key_list_bytes, threshold_bytes));
}

test "Performance and edge cases" {
    const allocator = testing.allocator;
    
    // Test empty message signing
    var key = try hedera.PrivateKey.generateEd25519(allocator);
    defer key.deinit();
    
    const empty_signature = try key.sign("");
    defer allocator.free(empty_signature);
    
    const public_key = key.getPublicKey();
    const empty_valid = try public_key.verify("", empty_signature);
    try testing.expect(empty_valid);
    
    // Test very long message signing
    var long_message = try allocator.alloc(u8, 10000);
    defer allocator.free(long_message);
    
    for (long_message, 0..) |_, i| {
        long_message[i] = @intCast(i % 256);
    }
    
    const long_signature = try key.sign(long_message);
    defer allocator.free(long_signature);
    
    const long_valid = try public_key.verify(long_message, long_signature);
    try testing.expect(long_valid);
    
    // Test signature with binary data
    const binary_data = [_]u8{ 0x00, 0x01, 0x02, 0xFF, 0xFE, 0xFD };
    const binary_signature = try key.sign(&binary_data);
    defer allocator.free(binary_signature);
    
    const binary_valid = try public_key.verify(&binary_data, binary_signature);
    try testing.expect(binary_valid);
}

test "Known test vectors validation" {
    const allocator = testing.allocator;
    
    // Known ED25519 test vector
    const test_private_hex = "302e020100300506032b657004220420db484b828e64b2d8f12ce3c0a0e93a0b8cce7af1bb8f39c97732394482538e10";
    const test_message = "test message";
    
    var test_key = try hedera.PrivateKey.fromString(test_private_hex, allocator);
    defer test_key.deinit();
    
    // Verify key properties
    try testing.expect(test_key.isEd25519());
    try testing.expectEqual(@as(usize, 32), test_key.getBytes().len);
    
    // Test signing and verification
    const test_signature = try test_key.sign(test_message);
    defer allocator.free(test_signature);
    
    const test_public = test_key.getPublicKey();
    const signature_valid = try test_public.verify(test_message, test_signature);
    try testing.expect(signature_valid);
    
    // Test deterministic signature (ED25519 should be deterministic)
    const test_signature2 = try test_key.sign(test_message);
    defer allocator.free(test_signature2);
    
    try testing.expectEqualSlices(u8, test_signature, test_signature2);
}
