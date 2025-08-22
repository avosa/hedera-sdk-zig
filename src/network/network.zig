const std = @import("std");
const AccountId = @import("../core/id.zig").AccountId;
const Node = @import("node.zig").Node;

// Network manages the collection of nodes
pub const Network = struct {
    nodes: std.AutoHashMap(AccountId, *Node),
    current_node_index: usize,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) Network {
        return Network{
            .nodes = std.AutoHashMap(AccountId, *Node).init(allocator),
            .current_node_index = 0,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Network) void {
        var iter = self.nodes.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.nodes.deinit();
    }
    
    // Registers a node with the network
    pub fn addNode(self: *Network, address: []const u8, account_id: AccountId) !void {
        const node = try self.allocator.create(Node);
        node.* = try Node.init(self.allocator, address, account_id);
        try self.nodes.put(account_id, node);
    }
    
    // Get a specific node by account ID
    pub fn getNode(self: *Network, account_id: AccountId) ?*Node {
        return self.nodes.get(account_id);
    }
    
    // Get all healthy nodes
    pub fn getHealthyNodes(self: *Network, allocator: std.mem.Allocator) ![]Node {
        var healthy_list = std.ArrayList(Node).init(allocator);
        defer healthy_list.deinit();
        
        var iter = self.nodes.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.*.isHealthy()) {
                try healthy_list.append(entry.value_ptr.*.*);
            }
        }
        
        return healthy_list.toOwnedSlice();
    }
    
    // Select a node using round-robin
    pub fn selectNode(self: *Network) !*Node {
        const node_count = self.nodes.count();
        if (node_count == 0) {
            return error.NoNodesAvailable;
        }
        
        // Try to find a healthy node
        var attempts: usize = 0;
        while (attempts < node_count) : (attempts += 1) {
            var iter = self.nodes.iterator();
            var current_index: usize = 0;
            
            while (iter.next()) |entry| {
                if (current_index == self.current_node_index % node_count) {
                    self.current_node_index = (self.current_node_index + 1) % node_count;
                    
                    if (entry.value_ptr.*.isHealthy()) {
                        return entry.value_ptr.*;
                    }
                    break;
                }
                current_index += 1;
            }
        }
        
        return error.NoHealthyNodes;
    }
    
    // Create network for testnet
    pub fn forTestnet(allocator: std.mem.Allocator) !Network {
        var network = Network.init(allocator);
        
        // Testnet nodes
        try network.addNode("35.237.200.180:50211", AccountId.init(0, 0, 3));
        try network.addNode("35.186.191.247:50211", AccountId.init(0, 0, 4));
        try network.addNode("35.192.2.25:50211", AccountId.init(0, 0, 5));
        try network.addNode("35.199.161.108:50211", AccountId.init(0, 0, 6));
        try network.addNode("35.203.82.240:50211", AccountId.init(0, 0, 7));
        try network.addNode("35.236.5.219:50211", AccountId.init(0, 0, 8));
        try network.addNode("35.197.192.225:50211", AccountId.init(0, 0, 9));
        
        return network;
    }
    
    // Create network for mainnet
    pub fn forMainnet(allocator: std.mem.Allocator) !Network {
        var network = Network.init(allocator);
        
        // Mainnet nodes
        try network.addNode("35.237.200.180:50211", AccountId.init(0, 0, 3));
        try network.addNode("35.186.191.247:50211", AccountId.init(0, 0, 4));
        try network.addNode("35.192.2.25:50211", AccountId.init(0, 0, 5));
        try network.addNode("35.199.161.108:50211", AccountId.init(0, 0, 6));
        try network.addNode("35.203.82.240:50211", AccountId.init(0, 0, 7));
        try network.addNode("35.236.5.219:50211", AccountId.init(0, 0, 8));
        try network.addNode("35.197.192.225:50211", AccountId.init(0, 0, 9));
        try network.addNode("35.204.86.32:50211", AccountId.init(0, 0, 10));
        try network.addNode("35.234.132.107:50211", AccountId.init(0, 0, 11));
        try network.addNode("35.236.2.27:50211", AccountId.init(0, 0, 12));
        try network.addNode("35.228.11.53:50211", AccountId.init(0, 0, 13));
        try network.addNode("34.91.181.183:50211", AccountId.init(0, 0, 14));
        try network.addNode("34.86.212.247:50211", AccountId.init(0, 0, 15));
        try network.addNode("35.245.27.193:50211", AccountId.init(0, 0, 16));
        try network.addNode("34.89.87.138:50211", AccountId.init(0, 0, 17));
        try network.addNode("34.93.112.7:50211", AccountId.init(0, 0, 18));
        try network.addNode("34.87.150.174:50211", AccountId.init(0, 0, 19));
        try network.addNode("34.125.203.175:50211", AccountId.init(0, 0, 20));
        try network.addNode("34.83.112.116:50211", AccountId.init(0, 0, 21));
        try network.addNode("34.94.106.61:50211", AccountId.init(0, 0, 22));
        try network.addNode("34.133.197.230:50211", AccountId.init(0, 0, 23));
        try network.addNode("34.204.88.77:50211", AccountId.init(0, 0, 24));
        try network.addNode("35.177.162.180:50211", AccountId.init(0, 0, 25));
        try network.addNode("3.121.238.26:50211", AccountId.init(0, 0, 26));
        try network.addNode("34.107.192.202:50211", AccountId.init(0, 0, 27));
        try network.addNode("34.160.80.38:50211", AccountId.init(0, 0, 28));
        
        return network;
    }
    
    // Create network for previewnet
    pub fn forPreviewnet(allocator: std.mem.Allocator) !Network {
        var network = Network.init(allocator);
        
        // Previewnet nodes
        try network.addNode("35.231.208.148:50211", AccountId.init(0, 0, 3));
        try network.addNode("35.231.239.243:50211", AccountId.init(0, 0, 4));
        try network.addNode("35.237.78.15:50211", AccountId.init(0, 0, 5));
        try network.addNode("35.237.221.37:50211", AccountId.init(0, 0, 6));
        try network.addNode("35.231.146.69:50211", AccountId.init(0, 0, 7));
        
        return network;
    }
};