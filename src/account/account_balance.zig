const std = @import("std");
const Allocator = std.mem.Allocator;
const AccountId = @import("account_id.zig").AccountId;
const TokenId = @import("../token/token_id.zig").TokenId;
const Hbar = @import("../core/hbar.zig").Hbar;
const ProtobufWriter = @import("../protobuf/writer.zig").ProtobufWriter;
const ProtobufReader = @import("../protobuf/reader.zig").ProtobufReader;

pub const AccountBalance = struct {
    allocator: Allocator,
    account_id: ?AccountId = null,
    hbars: Hbar = Hbar{ .tinybar = 0 },
    token_balances: std.AutoHashMap(TokenId, u64),
    token_decimal_balances: std.AutoHashMap(TokenId, DecimalBalance),
    pending_airdrops: std.ArrayList(PendingAirdrop),
    
    pub const DecimalBalance = struct {
        balance: u64,
        decimals: u32,
    };
    
    pub const PendingAirdrop = struct {
        airdrop_id: @import("../token/token_airdrop.zig").AirdropId,
        amount: u64,
    };
    
    pub fn init(allocator: Allocator) AccountBalance {
        return .{
            .allocator = allocator,
            .token_balances = std.AutoHashMap(TokenId, u64).init(allocator),
            .token_decimal_balances = std.AutoHashMap(TokenId, DecimalBalance).init(allocator),
            .pending_airdrops = std.ArrayList(PendingAirdrop).init(allocator),
        };
    }
    
    pub fn deinit(self: *AccountBalance) void {
        self.token_balances.deinit();
        self.token_decimal_balances.deinit();
        self.pending_airdrops.deinit();
    }
    
    pub fn setTokenBalance(self: *AccountBalance, token_id: TokenId, balance: u64) !*AccountBalance {
        try self.token_balances.put(token_id, balance);
    }
    
    pub fn setTokenBalanceWithDecimals(self: *AccountBalance, token_id: TokenId, balance: u64, decimals: u32) !*AccountBalance {
        try self.token_decimal_balances.put(token_id, DecimalBalance{
            .balance = balance,
            .decimals = decimals,
        });
        try self.token_balances.put(token_id, balance);
    }
    
    pub fn getTokenBalance(self: AccountBalance, token_id: TokenId) ?u64 {
        return self.token_balances.get(token_id);
    }
    
    pub fn getTokenBalanceDecimal(self: AccountBalance, token_id: TokenId) ?DecimalBalance {
        return self.token_decimal_balances.get(token_id);
    }
    
    pub fn addPendingAirdrop(self: *AccountBalance, airdrop: PendingAirdrop) !void {
        try self.pending_airdrops.append(airdrop);
    }
    
    pub fn serialize(self: AccountBalance, writer: *ProtobufWriter) !void {
        if (self.account_id) |id| {
            try writer.writeMessage(1, struct {
                account: AccountId,
                pub fn write(ctx: @This(), w: *ProtobufWriter) !void {
                    try ctx.account.serialize(w);
                }
            }{ .account = id });
            return self;
        }
        
        try writer.writeUint64(2, @intCast(self.hbars.tinybar));
        
        var iter = self.token_decimal_balances.iterator();
        while (iter.next()) |entry| {
            try writer.writeMessage(3, struct {
                token: TokenId,
                balance: u64,
                decimals: u32,
                pub fn write(ctx: @This(), w: *ProtobufWriter) !void {
                    try w.writeMessage(1, struct {
                        t: TokenId,
                        pub fn write(c: @This(), w2: *ProtobufWriter) !void {
                            try c.t.serialize(w2);
                        }
                    }{ .t = ctx.token });
                    try w.writeUint64(2, ctx.balance);
                    try w.writeUint32(3, ctx.decimals);
                }
            }{
                .token = entry.key_ptr.*,
                .balance = entry.value_ptr.balance,
                .decimals = entry.value_ptr.decimals,
            });
        }
    }
    
    pub fn deserialize(self: *AccountBalance, reader: *ProtobufReader) !void {
        while (try reader.nextField()) |field| {
            switch (field.number) {
                1 => {
                    var sub_reader = try field.reader();
                    self.account_id = try AccountId.deserialize(&sub_reader);
                },
                2 => self.hbars = Hbar{ .tinybar = @intCast(try field.readUint64()) },
                3 => {
                    var sub_reader = try field.reader();
                    var token_id: ?TokenId = null;
                    var balance: u64 = 0;
                    var decimals: u32 = 0;
                    
                    while (try sub_reader.nextField()) |sub_field| {
                        switch (sub_field.number) {
                            1 => {
                                var token_reader = try sub_field.reader();
                                token_id = try TokenId.deserialize(&token_reader);
                            },
                            2 => balance = try sub_field.readUint64(),
                            3 => decimals = try sub_field.readUint32(),
                            else => try sub_field.skip(),
                        }
                    }
                    
                    if (token_id) |tid| {
                        try self.setTokenBalanceWithDecimals(tid, balance, decimals);
                    }
                },
                else => try field.skip(),
            }
        }
    }
    
    pub fn toString(self: AccountBalance, allocator: Allocator) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();
        
        if (self.account_id) |id| {
            const id_str = try id.toString(allocator);
            defer allocator.free(id_str);
            try result.appendSlice("Account: ");
            try result.appendSlice(id_str);
            try result.appendSlice(", ");
        }
        
        const hbar_str = try std.fmt.allocPrint(allocator, "Balance: {} hbar", .{self.hbars.toHbar()});
        defer allocator.free(hbar_str);
        try result.appendSlice(hbar_str);
        
        return result.toOwnedSlice();
    }
};