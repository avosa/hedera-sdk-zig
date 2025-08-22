const std = @import("std");

// Complete JSON parser for Mirror Node API responses
pub const JsonParser = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) JsonParser {
        return JsonParser{
            .allocator = allocator,
        };
    }
    
    // Parse value types
    pub const Value = union(enum) {
        null: void,
        bool: bool,
        integer: i64,
        float: f64,
        string: []const u8,
        array: []Value,
        object: std.StringHashMap(Value),
        
        pub fn deinit(self: *Value, allocator: std.mem.Allocator) void {
            switch (self.*) {
                .string => |s| allocator.free(s),
                .array => |arr| {
                    for (arr) |*item| {
                        item.deinit(allocator);
                    }
                    allocator.free(arr);
                },
                .object => |*obj| {
                    var iter = obj.iterator();
                    while (iter.next()) |entry| {
                        allocator.free(entry.key_ptr.*);
                        entry.value_ptr.deinit(allocator);
                    }
                    obj.deinit();
                },
                else => {},
            }
        }
        
        pub fn getString(self: Value) ?[]const u8 {
            return switch (self) {
                .string => |s| s,
                else => null,
            };
        }
        
        pub fn getInt(self: Value) ?i64 {
            return switch (self) {
                .integer => |i| i,
                else => null,
            };
        }
        
        pub fn getBool(self: Value) ?bool {
            return switch (self) {
                .bool => |b| b,
                else => null,
            };
        }
        
        pub fn getFloat(self: Value) ?f64 {
            return switch (self) {
                .float => |f| f,
                .integer => |i| @floatFromInt(i),
                else => null,
            };
        }
        
        pub fn getArray(self: Value) ?[]Value {
            return switch (self) {
                .array => |a| a,
                else => null,
            };
        }
        
        pub fn getObject(self: Value) ?std.StringHashMap(Value) {
            return switch (self) {
                .object => |o| o,
                else => null,
            };
        }
        
        pub fn get(self: Value, key: []const u8) ?Value {
            return switch (self) {
                .object => |obj| obj.get(key),
                else => null,
            };
        }
    };
    
    // Token types
    const TokenType = enum {
        left_brace,
        right_brace,
        left_bracket,
        right_bracket,
        comma,
        colon,
        string,
        number,
        true_literal,
        false_literal,
        null_literal,
        eof,
    };
    
    const Token = struct {
        type: TokenType,
        value: []const u8,
    };
    
    // Lexer
    const Lexer = struct {
        input: []const u8,
        position: usize = 0,
        allocator: std.mem.Allocator,
        
        pub fn init(allocator: std.mem.Allocator, input: []const u8) Lexer {
            return Lexer{
                .input = input,
                .allocator = allocator,
            };
        }
        
        pub fn nextToken(self: *Lexer) !Token {
            self.skipWhitespace();
            
            if (self.position >= self.input.len) {
                return Token{ .type = .eof, .value = "" };
            }
            
            const ch = self.input[self.position];
            
            switch (ch) {
                '{' => {
                    self.position += 1;
                    return Token{ .type = .left_brace, .value = "{" };
                },
                '}' => {
                    self.position += 1;
                    return Token{ .type = .right_brace, .value = "}" };
                },
                '[' => {
                    self.position += 1;
                    return Token{ .type = .left_bracket, .value = "[" };
                },
                ']' => {
                    self.position += 1;
                    return Token{ .type = .right_bracket, .value = "]" };
                },
                ',' => {
                    self.position += 1;
                    return Token{ .type = .comma, .value = "," };
                },
                ':' => {
                    self.position += 1;
                    return Token{ .type = .colon, .value = ":" };
                },
                '"' => {
                    return try self.readString();
                },
                't' => {
                    if (self.matchKeyword("true")) {
                        return Token{ .type = .true_literal, .value = "true" };
                    }
                    return error.InvalidToken;
                },
                'f' => {
                    if (self.matchKeyword("false")) {
                        return Token{ .type = .false_literal, .value = "false" };
                    }
                    return error.InvalidToken;
                },
                'n' => {
                    if (self.matchKeyword("null")) {
                        return Token{ .type = .null_literal, .value = "null" };
                    }
                    return error.InvalidToken;
                },
                '-', '0'...'9' => {
                    return try self.readNumber();
                },
                else => return error.InvalidToken,
            }
        }
        
        fn skipWhitespace(self: *Lexer) void {
            while (self.position < self.input.len) {
                switch (self.input[self.position]) {
                    ' ', '\t', '\n', '\r' => self.position += 1,
                    else => break,
                }
            }
        }
        
        fn readString(self: *Lexer) !Token {
            const start = self.position;
            self.position += 1; // Skip opening quote
            
            while (self.position < self.input.len and self.input[self.position] != '"') {
                if (self.input[self.position] == '\\') {
                    self.position += 2; // Skip escape sequence
                } else {
                    self.position += 1;
                }
            }
            
            if (self.position >= self.input.len) {
                return error.UnterminatedString;
            }
            
            self.position += 1; // Skip closing quote
            return Token{
                .type = .string,
                .value = self.input[start + 1 .. self.position - 1],
            };
        }
        
        fn readNumber(self: *Lexer) !Token {
            const start = self.position;
            
            if (self.input[self.position] == '-') {
                self.position += 1;
            }
            
            // Integer part
            if (self.position < self.input.len and self.input[self.position] == '0') {
                self.position += 1;
            } else {
                while (self.position < self.input.len and std.ascii.isDigit(self.input[self.position])) {
                    self.position += 1;
                }
            }
            
            // Fractional part
            if (self.position < self.input.len and self.input[self.position] == '.') {
                self.position += 1;
                while (self.position < self.input.len and std.ascii.isDigit(self.input[self.position])) {
                    self.position += 1;
                }
            }
            
            // Exponent part
            if (self.position < self.input.len and (self.input[self.position] == 'e' or self.input[self.position] == 'E')) {
                self.position += 1;
                if (self.position < self.input.len and (self.input[self.position] == '+' or self.input[self.position] == '-')) {
                    self.position += 1;
                }
                while (self.position < self.input.len and std.ascii.isDigit(self.input[self.position])) {
                    self.position += 1;
                }
            }
            
            return Token{
                .type = .number,
                .value = self.input[start..self.position],
            };
        }
        
        fn matchKeyword(self: *Lexer, keyword: []const u8) bool {
            if (self.position + keyword.len > self.input.len) {
                return false;
            }
            
            if (std.mem.eql(u8, self.input[self.position .. self.position + keyword.len], keyword)) {
                self.position += keyword.len;
                return true;
            }
            
            return false;
        }
    };
    
    // Parser
    pub fn parse(self: *JsonParser, input: []const u8) !Value {
        var lexer = Lexer.init(self.allocator, input);
        return try self.parseValue(&lexer);
    }
    
    fn parseValue(self: *JsonParser, lexer: *Lexer) anyerror!Value {
        const token = try lexer.nextToken();
        
        switch (token.type) {
            .left_brace => return try self.parseObject(lexer),
            .left_bracket => return try self.parseArray(lexer),
            .string => return Value{ .string = try self.parseStringLiteral(token.value) },
            .number => return try self.parseNumber(token.value),
            .true_literal => return Value{ .bool = true },
            .false_literal => return Value{ .bool = false },
            .null_literal => return Value{ .null = {} },
            else => return error.UnexpectedToken,
        }
    }
    
    fn parseObject(self: *JsonParser, lexer: *Lexer) !Value {
        var object = std.StringHashMap(Value).init(self.allocator);
        errdefer {
            var iter = object.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(self.allocator);
            }
            object.deinit();
        }
        
        var token = try lexer.nextToken();
        if (token.type == .right_brace) {
            return Value{ .object = object };
        }
        
        while (true) {
            if (token.type != .string) {
                return error.ExpectedString;
            }
            
            const key = try self.parseStringLiteral(token.value);
            errdefer self.allocator.free(key);
            
            token = try lexer.nextToken();
            if (token.type != .colon) {
                self.allocator.free(key);
                return error.ExpectedColon;
            }
            
            var value = try self.parseValue(lexer);
            errdefer value.deinit(self.allocator);
            
            try object.put(key, value);
            
            token = try lexer.nextToken();
            if (token.type == .right_brace) {
                break;
            }
            
            if (token.type != .comma) {
                return error.ExpectedCommaOrBrace;
            }
            
            token = try lexer.nextToken();
        }
        
        return Value{ .object = object };
    }
    
    fn parseArray(self: *JsonParser, lexer: *Lexer) !Value {
        var array = std.ArrayList(Value).init(self.allocator);
        errdefer {
            for (array.items) |*item| {
                item.deinit(self.allocator);
            }
            array.deinit();
        }
        
        var token = try lexer.nextToken();
        if (token.type == .right_bracket) {
            return Value{ .array = try array.toOwnedSlice() };
        }
        
        // Put back the token for parseValue
        lexer.position -= token.value.len;
        
        while (true) {
            var value = try self.parseValue(lexer);
            errdefer value.deinit(self.allocator);
            
            try array.append(value);
            
            token = try lexer.nextToken();
            if (token.type == .right_bracket) {
                break;
            }
            
            if (token.type != .comma) {
                return error.ExpectedCommaOrBracket;
            }
        }
        
        return Value{ .array = try array.toOwnedSlice() };
    }
    
    fn parseStringLiteral(self: *JsonParser, value: []const u8) ![]const u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();
        
        var i: usize = 0;
        while (i < value.len) {
            if (value[i] == '\\' and i + 1 < value.len) {
                i += 1;
                switch (value[i]) {
                    '"' => try result.append('"'),
                    '\\' => try result.append('\\'),
                    '/' => try result.append('/'),
                    'b' => try result.append('\x08'),
                    'f' => try result.append('\x0C'),
                    'n' => try result.append('\n'),
                    'r' => try result.append('\r'),
                    't' => try result.append('\t'),
                    'u' => {
                        if (i + 4 < value.len) {
                            const hex = value[i + 1 .. i + 5];
                            const code_point = try std.fmt.parseInt(u16, hex, 16);
                            
                            if (code_point <= 0x7F) {
                                try result.append(@intCast(code_point));
                            } else if (code_point <= 0x7FF) {
                                try result.append(@intCast(0xC0 | (code_point >> 6)));
                                try result.append(@intCast(0x80 | (code_point & 0x3F)));
                            } else {
                                try result.append(@intCast(0xE0 | (code_point >> 12)));
                                try result.append(@intCast(0x80 | ((code_point >> 6) & 0x3F)));
                                try result.append(@intCast(0x80 | (code_point & 0x3F)));
                            }
                            i += 4;
                        } else {
                            return error.InvalidEscapeSequence;
                        }
                    },
                    else => return error.InvalidEscapeSequence,
                }
            } else {
                try result.append(value[i]);
            }
            i += 1;
        }
        
        return result.toOwnedSlice();
    }
    
    fn parseNumber(self: *JsonParser, value: []const u8) !Value {
        _ = self;
        
        // Check if it's a float
        for (value) |ch| {
            if (ch == '.' or ch == 'e' or ch == 'E') {
                const float_val = try std.fmt.parseFloat(f64, value);
                return Value{ .float = float_val };
            }
        }
        
        // Parse as integer
        const int_val = try std.fmt.parseInt(i64, value, 10);
        return Value{ .integer = int_val };
    }
};

// Helper functions for common patterns
pub fn getString(value: JsonParser.Value, key: []const u8) ?[]const u8 {
    if (value.get(key)) |v| {
        return v.getString();
    }
    return null;
}

pub fn getInt(value: JsonParser.Value, key: []const u8) ?i64 {
    if (value.get(key)) |v| {
        return v.getInt();
    }
    return null;
}

pub fn getBool(value: JsonParser.Value, key: []const u8) ?bool {
    if (value.get(key)) |v| {
        return v.getBool();
    }
    return null;
}

pub fn getArray(value: JsonParser.Value, key: []const u8) ?[]JsonParser.Value {
    if (value.get(key)) |v| {
        return v.getArray();
    }
    return null;
}

pub fn getObject(value: JsonParser.Value, key: []const u8) ?std.StringHashMap(JsonParser.Value) {
    if (value.get(key)) |v| {
        return v.getObject();
    }
    return null;
}