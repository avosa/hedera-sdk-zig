const std = @import("std");
const hedera = @import("hedera");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Match Go SDK pattern: ClientForName
    var client = try hedera.client_for_name(std.posix.getenv("HEDERA_NETWORK") orelse "testnet");
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
    
    const operator_id = try hedera.account_id_from_string(allocator, operator_id_str);
    var operator_key = try hedera.private_key_from_string(allocator, operator_key_str);
    defer operator_key.deinit();
    
    // Match Go SDK pattern: SetOperator
    try client.set_operator(operator_id, operator_key);
    
    std.log.info("Submit Message Example", .{});
    std.log.info("=====================", .{});
    
    // Create topic
    var topic_create = hedera.TopicCreateTransaction.init(allocator);
    defer topic_create.deinit();
    
    try topic_create.setTopicMemo("Zig SDK Topic");
    try topic_create.setAdminKey(hedera.Key.fromPublicKey(operator_key.getPublicKey()));
    try topic_create.setSubmitKey(hedera.Key.fromPublicKey(operator_key.getPublicKey()));
    
    const create_response = try topic_create.execute(&client);
    const create_receipt = try create_response.get_receipt(&client);
    
    const topic_id = create_receipt.topic_id orelse {
        std.log.err("Failed to get topic ID", .{});
        return;
    };
    
    std.log.info("Created topic: {s}", .{try topic_id.toString(allocator)});
    
    // Submit message to topic
    var message_submit = hedera.TopicMessageSubmitTransaction.init(allocator);
    defer message_submit.deinit();
    
    try message_submit.setTopicId(topic_id);
    try message_submit.setMessage("Hello from Hedera Zig SDK!");
    
    const message_response = try message_submit.execute(&client);
    const message_receipt = try message_response.get_receipt(&client);
    
    std.log.info("Message submitted with status: {}", .{message_receipt.status});
    std.log.info("Message sequence number: {}", .{message_receipt.topic_sequence_number orelse 0});
    
    // Submit another message with timestamp
    var second_message = hedera.TopicMessageSubmitTransaction.init(allocator);
    defer second_message.deinit();
    
    const timestamp = std.time.timestamp();
    const message = try std.fmt.allocPrint(allocator, "Message at timestamp: {}", .{timestamp});
    defer allocator.free(message);
    
    try second_message.setTopicId(topic_id);
    try second_message.setMessage(message);
    
    const second_response = try second_message.execute(&client);
    const second_receipt = try second_response.get_receipt(&client);
    
    std.log.info("Second message status: {}", .{second_receipt.status});
    std.log.info("Second message sequence: {}", .{second_receipt.topic_sequence_number orelse 0});
    
    // Get topic info
    var topic_info_query = hedera.TopicInfoQuery.init(allocator);
    defer topic_info_query.deinit();
    
    try topic_info_query.setTopicId(topic_id);
    const topic_info = try topic_info_query.execute(&client);
    
    std.log.info("Topic memo: {s}", .{topic_info.memo});
    std.log.info("Topic sequence number: {}", .{topic_info.sequence_number});
    std.log.info("Topic running hash: {}", .{std.fmt.fmtSliceHexLower(topic_info.running_hash)});
}