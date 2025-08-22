const std = @import("std");

pub const GrpcChannel = struct {
    address: []const u8,
    secure: bool,
    max_inbound_message_size: u32,
    max_inbound_metadata_size: u32,
    owns_address: bool,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) GrpcChannel {
        return GrpcChannel{
            .address = "",
            .secure = false,
            .max_inbound_message_size = 4 * 1024 * 1024, // 4MB default
            .max_inbound_metadata_size = 8 * 1024, // 8KB default
            .owns_address = false,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *GrpcChannel) void {
        if (self.owns_address and self.address.len > 0) {
            self.allocator.free(self.address);
        }
    }
    
    pub fn setAddress(self: *GrpcChannel, address: []const u8) !void {
        if (self.owns_address and self.address.len > 0) {
            self.allocator.free(self.address);
        }
        self.address = try self.allocator.dupe(u8, address);
        self.owns_address = true;
    }
};