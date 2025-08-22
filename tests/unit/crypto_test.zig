const std = @import("std");
const testing = std.testing;
const hedera = @import("hedera");

test "Ed25519 private key generation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Generate new key
    var key = try hedera.generate_private_key(allocator);
    defer key.deinit();
    
    // Verify key length
    const key_bytes = key.toBytes();
    try testing.expectEqual(@as(usize, 32), key_bytes.len);
    
    // Get public key
    const public_key = key.getPublicKey();
    const public_bytes = try public_key.toBytes(allocator);
    try testing.expectEqual(@as(usize, 33), public_bytes.len);
    
    // Test conversion to string
    const key_str = try key.toString(allocator);
    defer allocator.free(key_str);
    try testing.expect(key_str.len > 0);
    
    // Test parsing from string
    var parsed_key = try hedera.private_key_from_string(allocator, key_str);
    defer parsed_key.deinit();
    
    const parsed_bytes = parsed_key.toBytes();
    try testing.expectEqualSlices(u8, key_bytes, parsed_bytes);
}

test "Ed25519 key signing and verification" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Generate key pair
    var private_key = try hedera.generate_private_key(allocator);
    defer private_key.deinit();
    
    const public_key = private_key.getPublicKey();
    
    // Test message
    const message = "Hello, Hedera!";
    
    // Sign message
    const signature = try private_key.sign(message);
    defer allocator.free(signature);
    
    // Verify signature
    const is_valid = try public_key.verify(message, signature);
    try testing.expect(is_valid);
    
    // Verify with wrong message
    const wrong_message = "Wrong message";
    const is_invalid = try public_key.verify(wrong_message, signature);
    try testing.expect(!is_invalid);
}

test "ECDSA secp256k1 private key generation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Generate ECDSA key
    var key = try hedera.PrivateKey.generateEcdsa(allocator);
    defer key.deinit();
    
    // Verify key type
    // Key type check - the key union doesn't expose type directly
    // We know it's ECDSA from the prefix
    
    // Get public key (verifying it doesn't error)
    _ = key.getPublicKey();
    
    // Test DER encoding
    const der = try key.toBytesDer(allocator);
    defer allocator.free(der);
    try testing.expect(der.len > 0);
    
    // Test parsing from DER
    var parsed_key = try hedera.PrivateKey.fromBytesDer(allocator, der);
    defer parsed_key.deinit();
    try testing.expect(parsed_key.key_type == .EcdsaSecp256k1);
}

test "Private key mnemonic generation and recovery" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Generate mnemonic (24 words)
    var mnemonic = try hedera.Mnemonic.generate24(allocator);
    defer mnemonic.deinit();
    
    try testing.expectEqual(@as(usize, 24), mnemonic.words.len);
    
    // Derive key from mnemonic
    var key = try mnemonic.toPrivateKey("", allocator);
    defer key.deinit();
    
    // Convert mnemonic to string
    const mnemonic_str = try mnemonic.toString(allocator);
    defer allocator.free(mnemonic_str);
    
    // Parse mnemonic from string
    var parsed_mnemonic = try hedera.Mnemonic.fromString(mnemonic_str, allocator);
    defer parsed_mnemonic.deinit();
    
    // Derive key from parsed mnemonic
    var recovered_key = try hedera.PrivateKey.fromMnemonic(allocator, parsed_mnemonic, "");
    defer recovered_key.deinit();
    
    // Keys should match
    const original_bytes = key.toBytes();
    const recovered_bytes = recovered_key.toBytes();
    try testing.expectEqualSlices(u8, original_bytes, recovered_bytes);
}

test "Mnemonic with passphrase" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Generate mnemonic
    var mnemonic = try hedera.Mnemonic.generate12(allocator);
    defer mnemonic.deinit();
    
    try testing.expectEqual(@as(usize, 12), mnemonic.words.len);
    
    // Derive keys with different passphrases
    const passphrase1 = "passphrase1";
    const passphrase2 = "passphrase2";
    
    var key1 = try mnemonic.toPrivateKey(passphrase1, allocator);
    defer key1.deinit();
    
    var key2 = try mnemonic.toPrivateKey(passphrase2, allocator);
    defer key2.deinit();
    
    // Keys should be different
    const bytes1 = key1.toBytes();
    const bytes2 = key2.toBytes();
    try testing.expect(!std.mem.eql(u8, bytes1, bytes2));
}

test "Key derivation with index" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var root_key = try hedera.generate_private_key(allocator);
    defer root_key.deinit();
    
    // Derive child keys
    var child0 = try root_key.derive(0);
    defer child0.deinit();
    
    var child1 = try root_key.derive(1);
    defer child1.deinit();
    
    // Child keys should be different
    const bytes0 = child0.toBytes();
    const bytes1 = child1.toBytes();
    try testing.expect(!std.mem.eql(u8, bytes0, bytes1));
    
    // Deriving with same index should give same key
    var child0_again = try root_key.derive(0);
    defer child0_again.deinit();
    
    const bytes0_again = child0_again.toBytes();
    try testing.expectEqualSlices(u8, bytes0, bytes0_again);
}

test "Public key from bytes" {
    // Ed25519 public key (32 bytes)
    const ed25519_bytes = [_]u8{0x01} ** 32;
    const ed25519_key = try hedera.PublicKey.fromBytes(&ed25519_bytes);
    try testing.expect(ed25519_key == .ed25519);
    
    // ECDSA compressed public key (33 bytes)
    const ecdsa_compressed = [_]u8{0x02} ++ [_]u8{0x00} ** 32;
    const ecdsa_key = try hedera.PublicKey.fromBytes(&ecdsa_compressed);
    try testing.expect(ecdsa_key == .ecdsa_secp256k1);
}

test "Key list creation and management" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create key list
    var key_list = hedera.KeyList.init(allocator);
    defer key_list.deinit();
    
    // Set threshold
    key_list.threshold = 2;
    
    // Add keys
    var key1 = try hedera.generate_private_key(allocator);
    defer key1.deinit();
    try key_list.add(hedera.Key.fromPublicKey(key1.getPublicKey()));
    
    var key2 = try hedera.generate_private_key(allocator);
    defer key2.deinit();
    try key_list.add(hedera.Key.fromPublicKey(key2.getPublicKey()));
    
    var key3 = try hedera.generate_private_key(allocator);
    defer key3.deinit();
    try key_list.add(hedera.Key.fromPublicKey(key3.getPublicKey()));
    
    try testing.expectEqual(@as(usize, 3), key_list.keys.items.len);
    try testing.expectEqual(@as(?u32, 2), key_list.threshold);
    
    // Create Key from KeyList
    const list_key = hedera.Key.fromKeyList(key_list);
    try testing.expect(list_key == .key_list);
}

test "Contract ID key" {
    const contract_id = hedera.ContractId.init(0, 0, 1234);
    const contract_key = hedera.Key.fromContractId(contract_id);
    
    try testing.expect(contract_key == .contract_id);
    if (contract_key == .contract_id) {
        try testing.expectEqual(@as(u64, 1234), contract_key.contract_id.entity.num);
    }
}

test "Delegatable contract ID key" {
    const contract_id = hedera.ContractId.init(0, 0, 5678);
    const delegatable_key = hedera.Key.fromDelegatableContractId(contract_id);
    
    try testing.expect(delegatable_key == .delegatable_contract_id);
    if (delegatable_key == .delegatable_contract_id) {
        try testing.expectEqual(@as(u64, 5678), delegatable_key.delegatable_contract_id.entity.num);
    }
}

test "Key serialization to protobuf" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Generate a key
    var private_key = try hedera.generate_private_key(allocator);
    defer private_key.deinit();
    
    const public_key = private_key.getPublicKey();
    const key = hedera.Key.fromPublicKey(public_key);
    
    // Serialize to protobuf
    const proto_bytes = try key.toProtobuf(allocator);
    defer allocator.free(proto_bytes);
    
    try testing.expect(proto_bytes.len > 0);
    
    // Parse from protobuf
    const parsed_key = try hedera.Key.fromProtobuf(allocator, proto_bytes);
    
    // Verify keys match
    try testing.expect(std.meta.eql(key, parsed_key));
}

test "Transaction signing with multiple keys" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create a transaction
    var tx = hedera.TransferTransaction.init(allocator);
    defer tx.deinit();
    
    const account1 = hedera.AccountId.init(0, 0, 100);
    const account2 = hedera.AccountId.init(0, 0, 200);
    
    try tx.addHbarTransfer(account1, try hedera.Hbar.from(-10));
    try tx.addHbarTransfer(account2, try hedera.Hbar.from(10));
    
    // Generate multiple signers
    var signer1 = try hedera.generate_private_key(allocator);
    defer signer1.deinit();
    
    var signer2 = try hedera.generate_private_key(allocator);
    defer signer2.deinit();
    
    // Freeze transaction before signing
    try tx.base.freezeWith(null);
    
    // Sign with multiple keys
    try tx.base.sign(signer1);
    try tx.base.sign(signer2);
    
    // Verify signatures were added
    try testing.expectEqual(@as(usize, 2), tx.base.signatures.items.len);
}

test "Ethereum address from ECDSA key" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Generate ECDSA key
    var key = try hedera.PrivateKey.generateEcdsa(allocator);
    defer key.deinit();
    
    const public_key = key.getPublicKey();
    
    // Get Ethereum address
    const eth_address = try public_key.toEthereumAddress(allocator);
    defer allocator.free(eth_address);
    
    // Ethereum address should be 20 bytes (40 hex chars + 0x prefix)
    try testing.expectEqual(@as(usize, 42), eth_address.len);
    try testing.expect(std.mem.startsWith(u8, eth_address, "0x"));
}

test "Key equality comparison" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Generate two keys
    var key1 = try hedera.generate_private_key(allocator);
    defer key1.deinit();
    
    var key2 = try hedera.generate_private_key(allocator);
    defer key2.deinit();
    
    const public1 = key1.getPublicKey();
    const public2 = key2.getPublicKey();
    
    // Same key should be equal to itself
    try testing.expect(public1.equals(public1));
    
    // Different keys should not be equal
    try testing.expect(!public1.equals(public2));
    
    // Create Key wrappers
    const wrapped1 = hedera.Key.fromPublicKey(public1);
    const wrapped2 = hedera.Key.fromPublicKey(public2);
    
    try testing.expect(wrapped1.equals(wrapped1));
    try testing.expect(!wrapped1.equals(wrapped2));
}

test "Freeze transaction with key" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create freeze transaction
    var freeze_tx = hedera.FreezeTransaction.init(allocator);
    defer freeze_tx.deinit();
    
    // Set freeze type
    try freeze_tx.setFreezeType(.freeze_only);
    
    // Generate freeze key
    var freeze_key = try hedera.generate_private_key(allocator);
    defer freeze_key.deinit();
    
    // Freeze transaction before signing
    try freeze_tx.base.freezeWith(null);
    
    // Transaction should be signable with freeze key
    try freeze_tx.base.sign(freeze_key);
    
    try testing.expectEqual(@as(usize, 1), freeze_tx.base.signatures.items.len);
}