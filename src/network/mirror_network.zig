const std = @import("std");

pub const MirrorNetwork = struct {
    nodes: std.ArrayList([]const u8),
    network_name: []const u8,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) MirrorNetwork {
        return MirrorNetwork{
            .nodes = std.ArrayList([]const u8).init(allocator),
            .network_name = "",
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *MirrorNetwork) void {
        for (self.nodes.items) |node| {
            self.allocator.free(node);
        }
        self.nodes.deinit();
    }
    
    pub fn addNode(self: *MirrorNetwork, node_url: []const u8) !void {
        const owned_url = try self.allocator.dupe(u8, node_url);
        try self.nodes.append(owned_url);
    }
    
    pub fn getNodes(self: *const MirrorNetwork) []const []const u8 {
        return self.nodes.items;
    }
};