const std = @import("std");
const hedera = @import("hedera");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    std.log.info("Hedera SDK Cryptography Demo", .{});
    std.log.info("=============================", .{});

    // Example 1: ED25519 Key Generation
    std.log.info("", .{});
    std.log.info("1. ED25519 Key Generation:", .{});
    
    const ed25519_key = try hedera.Ed25519PrivateKey.generate();
    const ed25519_public = ed25519_key.getPublicKey();
    
    std.log.info("  ✓ ED25519 private key generated", .{});
    std.log.info("  ✓ ED25519 public key derived", .{});
    
    // Example 2: Digital Signatures
    std.log.info("", .{});
    std.log.info("2. Digital Signatures:", .{});
    
    const message = "Hello, Hedera!";
    const signature = try ed25519_key.sign(message);
    
    std.log.info("  ✓ Message signed: '{s}'", .{message});
    std.log.info("  ✓ Signature created: {} bytes", .{signature.len});
    
    // Verify signature
    const is_valid = ed25519_public.verify(message, &signature);
    std.log.info("  ✓ Signature verification: {}", .{is_valid});
    
    // Example 3: Key String Conversion
    std.log.info("", .{});
    std.log.info("3. Key String Conversion:", .{});
    
    const private_str = try ed25519_key.toString(allocator);
    defer allocator.free(private_str);
    
    const public_str = try ed25519_public.toString(allocator);
    defer allocator.free(public_str);
    
    std.log.info("  ✓ Private key (hex): {s}...", .{private_str[0..@min(32, private_str.len)]});
    std.log.info("  ✓ Public key (hex): {s}...", .{public_str[0..@min(32, public_str.len)]});
    
    // Example 4: ECDSA secp256k1 Keys
    std.log.info("", .{});
    std.log.info("4. ECDSA secp256k1 Keys:", .{});
    
    const ecdsa_key = try hedera.EcdsaSecp256k1PrivateKey.generate();
    _ = ecdsa_key.getPublicKey();
    
    std.log.info("  ✓ ECDSA private key generated", .{});
    std.log.info("  ✓ ECDSA public key derived", .{});
    
    // Sign with ECDSA
    const ecdsa_signature = try ecdsa_key.sign(message, allocator);
    defer allocator.free(ecdsa_signature);
    
    std.log.info("  ✓ ECDSA signature created: {} bytes", .{ecdsa_signature.len});
    
    // Example 5: Mnemonic Phrases
    std.log.info("", .{});
    std.log.info("5. Mnemonic Phrases:", .{});
    
    const mnemonic = try hedera.Mnemonic.generate24(allocator);
    defer allocator.free(mnemonic.words);
    
    std.log.info("  ✓ 24-word mnemonic generated", .{});
    std.log.info("  ✓ First word: '{s}'", .{mnemonic.words[0]});
    std.log.info("  ✓ Last word: '{s}'", .{mnemonic.words[23]});
    
    // Derive seed from mnemonic
    const seed = try mnemonic.toSeed(allocator, "");
    defer allocator.free(seed);
    
    std.log.info("  ✓ Seed derived: {} bytes", .{seed.len});
    
    // Example 6: Account ID Parsing
    std.log.info("", .{});
    std.log.info("6. Account ID Operations:", .{});
    
    const account_id = hedera.AccountId.init(0, 0, 100);
    const account_str = try account_id.toString(allocator);
    defer allocator.free(account_str);
    
    std.log.info("  ✓ Account ID created: {s}", .{account_str});
    
    const parsed = try hedera.AccountId.fromString(allocator, "0.0.12345");
    const parsed_str = try parsed.toString(allocator);
    defer allocator.free(parsed_str);
    
    std.log.info("  ✓ Account ID parsed: {s}", .{parsed_str});
    
    // Example 7: Hbar Units
    std.log.info("", .{});
    std.log.info("7. Hbar Currency Units:", .{});
    
    const amount = try hedera.Hbar.from(100);
    std.log.info("  ✓ 100 hbar = {} tinybar", .{amount.tinybars});
    
    const tiny_amount = try try hedera.Hbar.fromTinybars(50000000);
    std.log.info("  ✓ 50000000 tinybar = {} hbar", .{tiny_amount.toHbar()});
    
    std.log.info("", .{});
    std.log.info("✅ Cryptography demo completed successfully!", .{});
}