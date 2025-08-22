const std = @import("std");
const AccountId = @import("../core/id.zig").AccountId;

pub const LoadBalancingStrategy = enum {
    round_robin,
    random,
};

pub const LoadBalancer = struct {
    strategy: LoadBalancingStrategy,
    current_index: usize,
    nodes: std.ArrayList(AccountId),
    
    pub fn init(allocator: std.mem.Allocator, strategy: LoadBalancingStrategy) LoadBalancer {
        return LoadBalancer{
            .strategy = strategy,
            .current_index = 0,
            .nodes = std.ArrayList(AccountId).init(allocator),
        };
    }
    
    pub fn deinit(self: *LoadBalancer) void {
        self.nodes.deinit();
    }
    
    pub fn addNode(self: *LoadBalancer, node_id: AccountId) !void {
        try self.nodes.append(node_id);
    }
    
    pub fn getNextNode(self: *LoadBalancer) ?AccountId {
        if (self.nodes.items.len == 0) return null;
        
        switch (self.strategy) {
            .round_robin => {
                const node = self.nodes.items[self.current_index];
                self.current_index = (self.current_index + 1) % self.nodes.items.len;
                return node;
            },
            .random => {
                var prng = std.rand.DefaultPrng.init(blk: {
                    var seed: u64 = undefined;
                    std.posix.getrandom(std.mem.asBytes(&seed)) catch {
                        seed = @intCast(std.time.timestamp());
                    };
                    break :blk seed;
                });
                const index = prng.random().intRangeAtMost(usize, 0, self.nodes.items.len - 1);
                return self.nodes.items[index];
            },
        }
    }
};