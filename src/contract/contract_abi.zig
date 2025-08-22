const std = @import("std");

// ContractAbi represents the Application Binary Interface of a smart contract
pub const ContractAbi = struct {
    functions: std.ArrayList(Function),
    events: std.ArrayList(Event),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) ContractAbi {
        return ContractAbi{
            .functions = std.ArrayList(Function).init(allocator),
            .events = std.ArrayList(Event).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *ContractAbi) void {
        for (self.functions.items) |*func| {
            func.deinit();
        }
        self.functions.deinit();
        
        for (self.events.items) |*event| {
            event.deinit();
        }
        self.events.deinit();
    }
    
    pub fn getFunction(self: *const ContractAbi, name: []const u8) ?*const Function {
        for (self.functions.items) |*func| {
            if (std.mem.eql(u8, func.name, name)) {
                return func;
            }
        }
        return null;
    }
    
    pub const Function = struct {
        name: []const u8,
        inputs: []Parameter,
        outputs: []Parameter,
        state_mutability: StateMutability,
        type: FunctionType,
        allocator: std.mem.Allocator,
        
        pub fn deinit(self: *Function) void {
            self.allocator.free(self.name);
            
            for (self.inputs) |*param| {
                param.deinit();
            }
            self.allocator.free(self.inputs);
            
            for (self.outputs) |*param| {
                param.deinit();
            }
            self.allocator.free(self.outputs);
        }
    };
    
    pub const Event = struct {
        name: []const u8,
        inputs: []EventParameter,
        anonymous: bool,
        allocator: std.mem.Allocator,
        
        pub fn deinit(self: *Event) void {
            self.allocator.free(self.name);
            
            for (self.inputs) |*param| {
                param.deinit();
            }
            self.allocator.free(self.inputs);
        }
    };
    
    pub const Parameter = struct {
        name: []const u8,
        type: []const u8,
        components: ?[]Parameter,
        allocator: std.mem.Allocator,
        
        pub fn deinit(self: *Parameter) void {
            self.allocator.free(self.name);
            self.allocator.free(self.type);
            
            if (self.components) |comps| {
                for (comps) |*comp| {
                    comp.deinit();
                }
                self.allocator.free(comps);
            }
        }
    };
    
    pub const EventParameter = struct {
        name: []const u8,
        type: []const u8,
        indexed: bool,
        components: ?[]Parameter,
        allocator: std.mem.Allocator,
        
        pub fn deinit(self: *EventParameter) void {
            self.allocator.free(self.name);
            self.allocator.free(self.type);
            
            if (self.components) |comps| {
                for (comps) |*comp| {
                    comp.deinit();
                }
                self.allocator.free(comps);
            }
        }
    };
    
    pub const StateMutability = enum {
        pure,
        view,
        nonpayable,
        payable,
    };
    
    pub const FunctionType = enum {
        function,
        constructor,
        receive,
        fallback,
    };
};