const std = @import("std");
const NodeAddress = @import("managed_node.zig").NodeAddress;

pub const AddressBook = struct {
    node_addresses: std.ArrayList(NodeAddress),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) AddressBook {
        return AddressBook{
            .node_addresses = std.ArrayList(NodeAddress).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *AddressBook) void {
        for (self.node_addresses.items) |*node| {
            node.deinit(self.allocator);
        }
        self.node_addresses.deinit();
    }
    
    pub fn addNode(self: *AddressBook, node: NodeAddress) !void {
        try self.node_addresses.append(node);
    }
    
    pub fn getNodeCount(self: *const AddressBook) usize {
        return self.node_addresses.items.len;
    }
};