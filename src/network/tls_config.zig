const std = @import("std");

pub const TlsConfig = struct {
    cert_path: []const u8,
    key_path: []const u8,
    ca_path: []const u8,
    verify_server: bool,
    alpn_protocols: std.ArrayList([]const u8),
    
    pub fn init(allocator: std.mem.Allocator) TlsConfig {
        _ = allocator;
        return TlsConfig{
            .cert_path = "",
            .key_path = "",
            .ca_path = "",
            .verify_server = true,
            .alpn_protocols = std.ArrayList([]const u8){},
        };
    }
    
    pub fn deinit(self: *TlsConfig) void {
        self.alpn_protocols.deinit(self.allocator);
    }
    
    pub fn addAlpnProtocol(self: *TlsConfig, protocol: []const u8) !void {
        try self.alpn_protocols.append(self.allocator, protocol);
    }
};