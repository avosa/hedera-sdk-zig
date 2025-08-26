// Enhanced logging capabilities
// Provides structured, contextual, and configurable logging

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const Thread = std.Thread;
const Mutex = Thread.Mutex;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;

// Log levels with numerical values for comparison
pub const LogLevel = enum(u8) {
    trace = 0,
    debug = 1,
    info = 2,
    warn = 3,
    @"error" = 4,
    fatal = 5,
    
    pub fn toString(self: LogLevel) []const u8 {
        return switch (self) {
            .trace => "TRACE",
            .debug => "DEBUG",
            .info => "INFO",
            .warn => "WARN",
            .@"error" => "ERROR",
            .fatal => "FATAL",
        };
    }
    
    pub fn fromString(level_str: []const u8) ?LogLevel {
        if (std.mem.eql(u8, level_str, "TRACE")) return .trace;
        if (std.mem.eql(u8, level_str, "DEBUG")) return .debug;
        if (std.mem.eql(u8, level_str, "INFO")) return .info;
        if (std.mem.eql(u8, level_str, "WARN")) return .warn;
        if (std.mem.eql(u8, level_str, "ERROR")) return .@"error";
        if (std.mem.eql(u8, level_str, "FATAL")) return .fatal;
        return null;
    }
};

// Log context for structured logging
pub const LogContext = struct {
    transaction_id: ?[]const u8,
    account_id: ?[]const u8,
    operation_type: ?[]const u8,
    node_endpoint: ?[]const u8,
    request_id: ?[]const u8,
    session_id: ?[]const u8,
    custom_fields: HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    
    pub fn init(allocator: Allocator) LogContext {
        return LogContext{
            .transaction_id = null,
            .account_id = null,
            .operation_type = null,
            .node_endpoint = null,
            .request_id = null,
            .session_id = null,
            .custom_fields = HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }
    
    pub fn deinit(self: *LogContext, allocator: Allocator) void {
        var iter = self.custom_fields.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.custom_fields.deinit();
    }
    
    pub fn setField(self: *LogContext, allocator: Allocator, key: []const u8, value: []const u8) !void {
        const key_copy = try allocator.dupe(u8, key);
        const value_copy = try allocator.dupe(u8, value);
        try self.custom_fields.put(key_copy, value_copy);
    }
    
    pub fn clone(self: LogContext, allocator: Allocator) !LogContext {
        var new_context = LogContext.init(allocator);
        
        if (self.transaction_id) |tx_id| {
            new_context.transaction_id = try allocator.dupe(u8, tx_id);
        }
        if (self.account_id) |acc_id| {
            new_context.account_id = try allocator.dupe(u8, acc_id);
        }
        if (self.operation_type) |op_type| {
            new_context.operation_type = try allocator.dupe(u8, op_type);
        }
        if (self.node_endpoint) |endpoint| {
            new_context.node_endpoint = try allocator.dupe(u8, endpoint);
        }
        if (self.request_id) |req_id| {
            new_context.request_id = try allocator.dupe(u8, req_id);
        }
        if (self.session_id) |sess_id| {
            new_context.session_id = try allocator.dupe(u8, sess_id);
        }
        
        var iter = self.custom_fields.iterator();
        while (iter.next()) |entry| {
            try new_context.setField(allocator, entry.key_ptr.*, entry.value_ptr.*);
        }
        
        return new_context;
    }
};

// Log entry structure
pub const LogEntry = struct {
    timestamp: i64,
    level: LogLevel,
    message: []const u8,
    logger_name: []const u8,
    thread_id: u32,
    source_location: SourceLocation,
    context: LogContext,
    
    pub const SourceLocation = struct {
        file: []const u8,
        function: []const u8,
        line: u32,
        
        pub fn init(file: []const u8, function: []const u8, line: u32) SourceLocation {
            return SourceLocation{
                .file = file,
                .function = function,
                .line = line,
            };
        }
    };
    
    pub fn init(
        allocator: Allocator,
        level: LogLevel,
        message: []const u8,
        logger_name: []const u8,
        source_location: SourceLocation,
        context: LogContext,
    ) !LogEntry {
        return LogEntry{
            .timestamp = std.time.milliTimestamp(),
            .level = level,
            .message = try allocator.dupe(u8, message),
            .logger_name = try allocator.dupe(u8, logger_name),
            .thread_id = @intCast(Thread.getCurrentId()),
            .source_location = source_location,
            .context = try context.clone(allocator),
        };
    }
    
    pub fn deinit(self: LogEntry, allocator: Allocator) void {
        allocator.free(self.message);
        allocator.free(self.logger_name);
        self.context.deinit(allocator);
    }
};

// Log formatter interface
pub const LogFormatter = struct {
    formatFn: *const fn (allocator: Allocator, entry: LogEntry) anyerror![]u8,
    
    pub fn format(self: LogFormatter, allocator: Allocator, entry: LogEntry) ![]u8 {
        return self.formatFn(allocator, entry);
    }
};

// JSON log formatter
pub const JsonFormatter = struct {
    include_source_location: bool,
    include_thread_id: bool,
    pretty_print: bool,
    
    pub fn init(include_source_location: bool, include_thread_id: bool, pretty_print: bool) JsonFormatter {
        return JsonFormatter{
            .include_source_location = include_source_location,
            .include_thread_id = include_thread_id,
            .pretty_print = pretty_print,
        };
    }
    
    pub fn formatter(self: JsonFormatter) LogFormatter {
        return LogFormatter{
            .formatFn = struct {
                fn format(allocator: Allocator, entry: LogEntry) ![]u8 {
                    var json_obj = ArrayList(u8).init(allocator);
                    const writer = json_obj.writer();
                    
                    if (self.pretty_print) {
                        try writer.writeAll("{\n");
                        try writer.print("  \"timestamp\": {},\n", .{entry.timestamp});
                        try writer.print("  \"level\": \"{s}\",\n", .{entry.level.toString()});
                        try writer.print("  \"logger\": \"{s}\",\n", .{entry.logger_name});
                        try writer.print("  \"message\": \"{s}\"", .{entry.message});
                        
                        if (self.include_thread_id) {
                            try writer.print(",\n  \"thread_id\": {}", .{entry.thread_id});
                        }
                        
                        if (self.include_source_location) {
                            try writer.print(",\n  \"source\": {{\n");
                            try writer.print("    \"file\": \"{s}\",\n", .{entry.source_location.file});
                            try writer.print("    \"function\": \"{s}\",\n", .{entry.source_location.function});
                            try writer.print("    \"line\": {}\n", .{entry.source_location.line});
                            try writer.writeAll("  }");
                        }
                        
                        // Add context fields
                        if (entry.context.transaction_id) |tx_id| {
                            try writer.print(",\n  \"transaction_id\": \"{s}\"", .{tx_id});
                        }
                        if (entry.context.account_id) |acc_id| {
                            try writer.print(",\n  \"account_id\": \"{s}\"", .{acc_id});
                        }
                        if (entry.context.operation_type) |op_type| {
                            try writer.print(",\n  \"operation_type\": \"{s}\"", .{op_type});
                        }
                        if (entry.context.node_endpoint) |endpoint| {
                            try writer.print(",\n  \"node_endpoint\": \"{s}\"", .{endpoint});
                        }
                        
                        // Add custom fields
                        var iter = entry.context.custom_fields.iterator();
                        while (iter.next()) |field| {
                            try writer.print(",\n  \"{s}\": \"{s}\"", .{ field.key_ptr.*, field.value_ptr.* });
                        }
                        
                        try writer.writeAll("\n}");
                    } else {
                        try writer.writeAll("{");
                        try writer.print("\"timestamp\":{},", .{entry.timestamp});
                        try writer.print("\"level\":\"{s}\",", .{entry.level.toString()});
                        try writer.print("\"logger\":\"{s}\",", .{entry.logger_name});
                        try writer.print("\"message\":\"{s}\"", .{entry.message});
                        
                        if (self.include_thread_id) {
                            try writer.print(",\"thread_id\":{}", .{entry.thread_id});
                        }
                        
                        if (self.include_source_location) {
                            try writer.print(",\"source\":{{\"file\":\"{s}\",\"function\":\"{s}\",\"line\":{}}}", .{
                                entry.source_location.file,
                                entry.source_location.function,
                                entry.source_location.line,
                            });
                        }
                        
                        // Add context fields (compact)
                        if (entry.context.transaction_id) |tx_id| {
                            try writer.print(",\"transaction_id\":\"{s}\"", .{tx_id});
                        }
                        if (entry.context.account_id) |acc_id| {
                            try writer.print(",\"account_id\":\"{s}\"", .{acc_id});
                        }
                        if (entry.context.operation_type) |op_type| {
                            try writer.print(",\"operation_type\":\"{s}\"", .{op_type});
                        }
                        if (entry.context.node_endpoint) |endpoint| {
                            try writer.print(",\"node_endpoint\":\"{s}\"", .{endpoint});
                        }
                        
                        // Add custom fields
                        var iter = entry.context.custom_fields.iterator();
                        while (iter.next()) |field| {
                            try writer.print(",\"{s}\":\"{s}\"", .{ field.key_ptr.*, field.value_ptr.* });
                        }
                        
                        try writer.writeAll("}");
                    }
                    
                    return json_obj.toOwnedSlice();
                }
            }.format,
        };
    }
};

// Text log formatter
pub const TextFormatter = struct {
    include_timestamp: bool,
    include_level: bool,
    include_logger_name: bool,
    include_source_location: bool,
    include_thread_id: bool,
    timestamp_format: TimestampFormat,
    
    pub const TimestampFormat = enum {
        iso8601,
        rfc3339,
        unix_ms,
        human_readable,
    };
    
    pub fn init() TextFormatter {
        return TextFormatter{
            .include_timestamp = true,
            .include_level = true,
            .include_logger_name = true,
            .include_source_location = false,
            .include_thread_id = false,
            .timestamp_format = .human_readable,
        };
    }
    
    pub fn formatter(self: TextFormatter) LogFormatter {
        return LogFormatter{
            .formatFn = struct {
                fn format(allocator: Allocator, entry: LogEntry) ![]u8 {
                    var output = ArrayList(u8).init(allocator);
                    const writer = output.writer();
                    
                    if (self.include_timestamp) {
                        switch (self.timestamp_format) {
                            .unix_ms => try writer.print("[{}] ", .{entry.timestamp}),
                            .human_readable => {
                                const seconds = @divFloor(entry.timestamp, 1000);
                                const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(seconds) };
                                const day_seconds = epoch_seconds.getDaySeconds();
                                const year_day = epoch_seconds.getEpochDay().calculateYearDay();
                                const month_day = year_day.calculateMonthDay();
                                
                                try writer.print("[{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}] ", .{
                                    year_day.year,
                                    month_day.month.numeric(),
                                    month_day.day_index + 1,
                                    day_seconds.getHoursIntoDay(),
                                    day_seconds.getMinutesIntoHour(),
                                    day_seconds.getSecondsIntoMinute(),
                                });
                            },
                            else => try writer.print("[{}] ", .{entry.timestamp}),
                        }
                    }
                    
                    if (self.include_level) {
                        try writer.print("[{s}] ", .{entry.level.toString()});
                    }
                    
                    if (self.include_logger_name) {
                        try writer.print("[{s}] ", .{entry.logger_name});
                    }
                    
                    if (self.include_thread_id) {
                        try writer.print("[Thread:{}] ", .{entry.thread_id});
                    }
                    
                    if (self.include_source_location) {
                        try writer.print("[{s}:{}:{}] ", .{
                            entry.source_location.function,
                            entry.source_location.file,
                            entry.source_location.line,
                        });
                    }
                    
                    try writer.print("{s}", .{entry.message});
                    
                    // Add context information if available
                    if (entry.context.transaction_id) |tx_id| {
                        try writer.print(" [tx_id:{s}]", .{tx_id});
                    }
                    if (entry.context.account_id) |acc_id| {
                        try writer.print(" [account:{s}]", .{acc_id});
                    }
                    if (entry.context.operation_type) |op_type| {
                        try writer.print(" [op:{s}]", .{op_type});
                    }
                    if (entry.context.node_endpoint) |endpoint| {
                        try writer.print(" [node:{s}]", .{endpoint});
                    }
                    
                    // Add custom fields
                    var iter = entry.context.custom_fields.iterator();
                    while (iter.next()) |field| {
                        try writer.print(" [{}:{}]", .{ field.key_ptr.*, field.value_ptr.* });
                    }
                    
                    return output.toOwnedSlice();
                }
            }.format,
        };
    }
};

// Log appender interface
pub const LogAppender = struct {
    appendFn: *const fn (formatted_message: []const u8) anyerror!void,
    
    pub fn append(self: LogAppender, formatted_message: []const u8) !void {
        return self.appendFn(formatted_message);
    }
};

// Console appender
pub const ConsoleAppender = struct {
    writer: std.fs.File.Writer,
    use_colors: bool,
    
    pub fn init(writer: std.fs.File.Writer, use_colors: bool) ConsoleAppender {
        return ConsoleAppender{
            .writer = writer,
            .use_colors = use_colors,
        };
    }
    
    pub fn appender(self: ConsoleAppender) LogAppender {
        return LogAppender{
            .appendFn = struct {
                fn append(formatted_message: []const u8) !void {
                    try self.writer.print("{s}\n", .{formatted_message});
                }
            }.append,
        };
    }
};

// File appender
pub const FileAppender = struct {
    file: std.fs.File,
    mutex: Mutex,
    max_file_size: ?usize,
    rotation_count: ?u32,
    
    pub fn init(file: std.fs.File, max_file_size: ?usize, rotation_count: ?u32) FileAppender {
        return FileAppender{
            .file = file,
            .mutex = Mutex{},
            .max_file_size = max_file_size,
            .rotation_count = rotation_count,
        };
    }
    
    pub fn deinit(self: *FileAppender) void {
        self.file.close();
    }
    
    pub fn appender(self: *FileAppender) LogAppender {
        return LogAppender{
            .appendFn = struct {
                fn append(formatted_message: []const u8) !void {
                    self.mutex.lock();
                    defer self.mutex.unlock();
                    
                    try self.file.writer().print("{s}\n", .{formatted_message});
                    try self.file.sync();
                    
                    // Check for rotation if max_file_size is set
                    if (self.max_file_size) |max_size| {
                        const stat = try self.file.stat();
                        if (stat.size >= max_size) {
                            // Implement file rotation logic here
                            // Now, just truncate the file
                            try self.file.seekTo(0);
                            try self.file.setEndPos(0);
                        }
                    }
                }
            }.append,
        };
    }
};

// Enhanced logger
pub const Logger = struct {
    allocator: Allocator,
    name: []const u8,
    level: LogLevel,
    formatter: LogFormatter,
    appenders: ArrayList(LogAppender),
    context: LogContext,
    mutex: Mutex,
    
    pub fn init(
        allocator: Allocator,
        name: []const u8,
        level: LogLevel,
        formatter: LogFormatter,
    ) !Logger {
        return Logger{
            .allocator = allocator,
            .name = try allocator.dupe(u8, name),
            .level = level,
            .formatter = formatter,
            .appenders = ArrayList(LogAppender).init(allocator),
            .context = LogContext.init(allocator),
            .mutex = Mutex{},
        };
    }
    
    pub fn deinit(self: *Logger) void {
        self.allocator.free(self.name);
        self.appenders.deinit();
        self.context.deinit(self.allocator);
    }
    
    pub fn addAppender(self: *Logger, appender: LogAppender) !void {
        try self.appenders.append(appender);
    }
    
    pub fn setLevel(self: *Logger, level: LogLevel) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.level = level;
    }
    
    pub fn setContext(self: *Logger, context: LogContext) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        self.context.deinit(self.allocator);
        self.context = try context.clone(self.allocator);
    }
    
    pub fn withContext(self: *Logger, context: LogContext) !Logger {
        var new_logger = try Logger.init(self.allocator, self.name, self.level, self.formatter);
        new_logger.context = try context.clone(self.allocator);
        
        for (self.appenders.items) |appender| {
            try new_logger.addAppender(appender);
        }
        
        return new_logger;
    }
    
    pub fn isEnabled(self: *Logger, level: LogLevel) bool {
        return @intFromEnum(level) >= @intFromEnum(self.level);
    }
    
    fn log(
        self: *Logger,
        level: LogLevel,
        comptime format: []const u8,
        args: anytype,
        source_location: LogEntry.SourceLocation,
    ) void {
        if (!self.isEnabled(level)) return;
        
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const message = std.fmt.allocPrint(self.allocator, format, args) catch return;
        defer self.allocator.free(message);
        
        const entry = LogEntry.init(
            self.allocator,
            level,
            message,
            self.name,
            source_location,
            self.context,
        ) catch return;
        defer entry.deinit(self.allocator);
        
        const formatted = self.formatter.format(self.allocator, entry) catch return;
        defer self.allocator.free(formatted);
        
        for (self.appenders.items) |appender| {
            appender.append(formatted) catch {};
        }
    }
    
    pub fn trace(self: *Logger, comptime format: []const u8, args: anytype) void {
        self.log(.trace, format, args, LogEntry.SourceLocation.init(@src().file, @src().fn_name, @src().line));
    }
    
    pub fn debug(self: *Logger, comptime format: []const u8, args: anytype) void {
        self.log(.debug, format, args, LogEntry.SourceLocation.init(@src().file, @src().fn_name, @src().line));
    }
    
    pub fn info(self: *Logger, comptime format: []const u8, args: anytype) void {
        self.log(.info, format, args, LogEntry.SourceLocation.init(@src().file, @src().fn_name, @src().line));
    }
    
    pub fn warn(self: *Logger, comptime format: []const u8, args: anytype) void {
        self.log(.warn, format, args, LogEntry.SourceLocation.init(@src().file, @src().fn_name, @src().line));
    }
    
    pub fn err(self: *Logger, comptime format: []const u8, args: anytype) void {
        self.log(.@"error", format, args, LogEntry.SourceLocation.init(@src().file, @src().fn_name, @src().line));
    }
    
    pub fn fatal(self: *Logger, comptime format: []const u8, args: anytype) void {
        self.log(.fatal, format, args, LogEntry.SourceLocation.init(@src().file, @src().fn_name, @src().line));
    }
};

// Logger factory and registry
pub const LoggerRegistry = struct {
    allocator: Allocator,
    loggers: HashMap([]const u8, *Logger, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    mutex: Mutex,
    
    pub fn init(allocator: Allocator) LoggerRegistry {
        return LoggerRegistry{
            .allocator = allocator,
            .loggers = HashMap([]const u8, *Logger, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .mutex = Mutex{},
        };
    }
    
    pub fn deinit(self: *LoggerRegistry) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        var iter = self.loggers.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.loggers.deinit();
    }
    
    pub fn getLogger(self: *LoggerRegistry, name: []const u8, level: LogLevel, formatter: LogFormatter) !*Logger {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.loggers.get(name)) |logger| {
            return logger;
        }
        
        const logger = try self.allocator.create(Logger);
        logger.* = try Logger.init(self.allocator, name, level, formatter);
        
        const name_copy = try self.allocator.dupe(u8, name);
        try self.loggers.put(name_copy, logger);
        
        return logger;
    }
};

// Global logger registry
var global_registry: ?*LoggerRegistry = null;
var global_registry_mutex: Mutex = Mutex{};

// Initialize global logger registry
pub fn initGlobalRegistry(allocator: Allocator) !void {
    global_registry_mutex.lock();
    defer global_registry_mutex.unlock();
    
    if (global_registry != null) return;
    
    global_registry = try allocator.create(LoggerRegistry);
    global_registry.?.* = LoggerRegistry.init(allocator);
}

// Get global logger
pub fn getGlobalLogger(name: []const u8, level: LogLevel, formatter: LogFormatter) !*Logger {
    global_registry_mutex.lock();
    defer global_registry_mutex.unlock();
    
    if (global_registry) |registry| {
        return registry.getLogger(name, level, formatter);
    }
    return error.RegistryNotInitialized;
}

// Cleanup global registry
pub fn deinitGlobalRegistry(allocator: Allocator) void {
    global_registry_mutex.lock();
    defer global_registry_mutex.unlock();
    
    if (global_registry) |registry| {
        registry.deinit();
        allocator.destroy(registry);
        global_registry = null;
    }
}

// Test cases
test "LogLevel operations" {
    try testing.expectEqual(LogLevel.info, LogLevel.fromString("INFO"));
    try testing.expect(std.mem.eql(u8, "ERROR", LogLevel.@"error".toString()));
    try testing.expect(@intFromEnum(LogLevel.@"error") > @intFromEnum(LogLevel.warn));
}

test "LogContext operations" {
    const allocator = testing.allocator;
    
    var context = LogContext.init(allocator);
    defer context.deinit(allocator);
    
    try context.setField(allocator, "key1", "value1");
    try context.setField(allocator, "key2", "value2");
    
    try testing.expect(context.custom_fields.contains("key1"));
    try testing.expect(context.custom_fields.contains("key2"));
}

test "TextFormatter basic formatting" {
    const allocator = testing.allocator;
    
    var context = LogContext.init(allocator);
    defer context.deinit(allocator);
    
    const entry = try LogEntry.init(
        allocator,
        .info,
        "Test message",
        "test_logger",
        LogEntry.SourceLocation.init("test.zig", "test_function", 42),
        context,
    );
    defer entry.deinit(allocator);
    
    var formatter = TextFormatter.init();
    const log_formatter = formatter.formatter();
    
    const formatted = try log_formatter.format(allocator, entry);
    defer allocator.free(formatted);
    
    try testing.expect(std.mem.indexOf(u8, formatted, "INFO") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "Test message") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "test_logger") != null);
}

test "Logger basic operations" {
    const allocator = testing.allocator;
    
    var formatter = TextFormatter.init();
    const log_formatter = formatter.formatter();
    
    var logger = try Logger.init(allocator, "test", .info, log_formatter);
    defer logger.deinit();
    
    try testing.expect(logger.isEnabled(.info));
    try testing.expect(logger.isEnabled(.@"error"));
    try testing.expect(!logger.isEnabled(.debug));
}