const std = @import("std");

// Export complete protobuf implementation
pub const ProtobufReader = @import("reader.zig").ProtoReader;
pub const ProtobufWriter = @import("writer.zig").ProtobufWriter;
pub const WireType = @import("writer.zig").WireType;
pub const MessageBuilder = @import("writer.zig").MessageBuilder;

// Re-export all functions
pub const computeVarintSize = @import("writer.zig").computeVarintSize;
pub const computeZigzagSize = @import("writer.zig").computeZigzagSize;
pub const computeFixed32Size = @import("writer.zig").computeFixed32Size;
pub const computeFixed64Size = @import("writer.zig").computeFixed64Size;
pub const computeBytesSize = @import("writer.zig").computeBytesSize;
pub const computeStringSize = @import("writer.zig").computeStringSize;
pub const computeMessageSize = @import("writer.zig").computeMessageSize;
pub const computeTagSize = @import("writer.zig").computeTagSize;
pub const computeFieldSize = @import("writer.zig").computeFieldSize;
pub const isValidFieldNumber = @import("writer.zig").isValidFieldNumber;
pub const validateMessage = @import("reader.zig").validateMessage;
pub const getDefaultValue = @import("reader.zig").getDefaultValue;