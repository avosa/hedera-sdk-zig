const std = @import("std");

// Thread-safe singleton pattern for environment loading
const EnvState = struct {
    map: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,
    loaded: bool = false,
    mutex: std.Thread.Mutex = .{},
};

var env_state: ?*EnvState = null;
var env_mutex: std.Thread.Mutex = .{};

// Initialize the environment loader (thread-safe)
fn ensureInitialized(allocator: std.mem.Allocator) !void {
    env_mutex.lock();
    defer env_mutex.unlock();
    
    if (env_state != null) return;
    
    const state = try allocator.create(EnvState);
    state.* = .{
        .map = std.StringHashMap([]const u8).init(allocator),
        .allocator = allocator,
        .loaded = false,
    };
    env_state = state;
}

// Load environment variables from .env file (thread-safe, idempotent)
fn loadEnvFile() !void {
    const state = env_state orelse return;
    
    state.mutex.lock();
    defer state.mutex.unlock();
    
    // Already loaded, skip
    if (state.loaded) return;
    state.loaded = true;
    
    // Try to find .env file in current directory or parent directories
    const paths_to_try = [_][]const u8{
        ".env",
        "../.env",
        "../../.env",
        "../../../.env",
    };
    
    var env_content: []u8 = undefined;
    var found = false;
    
    for (paths_to_try) |path| {
        const file = std.fs.cwd().openFile(path, .{}) catch continue;
        defer file.close();
        
        const file_size = try file.getEndPos();
        env_content = try state.allocator.alloc(u8, file_size);
        _ = try file.read(env_content);
        found = true;
        break;
    }
    
    if (!found) {
        // No .env file found, that's okay - use system env vars
        return;
    }
    
    defer state.allocator.free(env_content);
    
    // Parse the .env file
    var lines = std.mem.tokenizeAny(u8, env_content, "\n\r");
    while (lines.next()) |line| {
        // Skip empty lines and comments
        if (line.len == 0 or line[0] == '#') continue;
        
        // Remove 'export ' prefix if present
        var actual_line = line;
        if (std.mem.startsWith(u8, line, "export ")) {
            actual_line = line[7..];
        }
        
        // Find the = sign
        const eq_index = std.mem.indexOf(u8, actual_line, "=") orelse continue;
        
        const key = std.mem.trim(u8, actual_line[0..eq_index], " \t");
        var value = std.mem.trim(u8, actual_line[eq_index + 1..], " \t");
        
        // Remove quotes if present
        if (value.len >= 2) {
            if ((value[0] == '"' and value[value.len - 1] == '"') or
                (value[0] == '\'' and value[value.len - 1] == '\'')) {
                value = value[1..value.len - 1];
            }
        }
        
        // Check if key already exists to avoid leaks
        const result = try state.map.getOrPut(key);
        if (result.found_existing) {
            // Free old values before replacing
            state.allocator.free(result.key_ptr.*);
            state.allocator.free(result.value_ptr.*);
        }
        
        // Store new copies
        result.key_ptr.* = try state.allocator.dupe(u8, key);
        result.value_ptr.* = try state.allocator.dupe(u8, value);
    }
}

// Get environment variable with .env file support
pub fn getEnvVarOwned(allocator: std.mem.Allocator, key: []const u8) ![]u8 {
    // Ensure initialized
    try ensureInitialized(allocator);
    
    // Load .env file if not already loaded
    try loadEnvFile();
    
    // Check our loaded env vars first
    if (env_state) |state| {
        state.mutex.lock();
        defer state.mutex.unlock();
        
        if (state.map.get(key)) |value| {
            return allocator.dupe(u8, value);
        }
    }
    
    // Fall back to system environment variable
    return std.process.getEnvVarOwned(allocator, key);
}

// Clean up all allocated memory (call at program exit)
pub fn deinit() void {
    env_mutex.lock();
    defer env_mutex.unlock();
    
    if (env_state) |state| {
        // Lock the state mutex before cleanup
        state.mutex.lock();
        
        // Free all stored key-value pairs
        var it = state.map.iterator();
        while (it.next()) |entry| {
            state.allocator.free(entry.key_ptr.*);
            state.allocator.free(entry.value_ptr.*);
        }
        state.map.deinit();
        
        // Unlock before destroying
        state.mutex.unlock();
        
        // Free the state itself
        const alloc = state.allocator;
        alloc.destroy(state);
        env_state = null;
    }
}