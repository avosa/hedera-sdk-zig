// Response compression support
// Provides efficient compression and decompression for network communication

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

// Compression algorithms supported
pub const CompressionAlgorithm = enum {
    none,
    gzip,
    deflate,
    brotli,
    lz4,
    zstd,
    
    pub fn toString(self: CompressionAlgorithm) []const u8 {
        return switch (self) {
            .none => "none",
            .gzip => "gzip",
            .deflate => "deflate",
            .brotli => "br",
            .lz4 => "lz4",
            .zstd => "zstd",
        };
    }
    
    pub fn fromString(algorithm: []const u8) ?CompressionAlgorithm {
        if (std.mem.eql(u8, algorithm, "none")) return .none;
        if (std.mem.eql(u8, algorithm, "gzip")) return .gzip;
        if (std.mem.eql(u8, algorithm, "deflate")) return .deflate;
        if (std.mem.eql(u8, algorithm, "br")) return .brotli;
        if (std.mem.eql(u8, algorithm, "lz4")) return .lz4;
        if (std.mem.eql(u8, algorithm, "zstd")) return .zstd;
        return null;
    }
    
    pub fn getCompressionLevel(self: CompressionAlgorithm) u8 {
        return switch (self) {
            .none => 0,
            .gzip => 6,
            .deflate => 6,
            .brotli => 4,
            .lz4 => 1,
            .zstd => 3,
        };
    }
    
    pub fn getTypicalCompressionRatio(self: CompressionAlgorithm) f64 {
        return switch (self) {
            .none => 1.0,
            .gzip => 0.3,
            .deflate => 0.3,
            .brotli => 0.25,
            .lz4 => 0.5,
            .zstd => 0.28,
        };
    }
};

// Compression configuration
pub const CompressionConfig = struct {
    algorithm: CompressionAlgorithm,
    level: ?u8,
    min_size_threshold: usize,
    max_size_threshold: usize,
    enable_streaming: bool,
    buffer_size: usize,
    
    pub fn init(algorithm: CompressionAlgorithm) CompressionConfig {
        return CompressionConfig{
            .algorithm = algorithm,
            .level = null, // Use algorithm default
            .min_size_threshold = 1024, // Don't compress below 1KB
            .max_size_threshold = 50 * 1024 * 1024, // Don't compress above 50MB
            .enable_streaming = true,
            .buffer_size = 64 * 1024, // 64KB buffer
        };
    }
    
    pub fn getEffectiveLevel(self: CompressionConfig) u8 {
        return self.level orelse self.algorithm.getCompressionLevel();
    }
    
    pub fn shouldCompress(self: CompressionConfig, data_size: usize) bool {
        if (self.algorithm == .none) return false;
        if (data_size < self.min_size_threshold) return false;
        if (data_size > self.max_size_threshold) return false;
        return true;
    }
};

// Compression result
pub const CompressionResult = struct {
    compressed_data: []u8,
    original_size: usize,
    compressed_size: usize,
    algorithm: CompressionAlgorithm,
    compression_ratio: f64,
    
    pub fn init(allocator: Allocator, compressed_data: []const u8, original_size: usize, algorithm: CompressionAlgorithm) !CompressionResult {
        const data_copy = try allocator.dupe(u8, compressed_data);
        const compression_ratio = @as(f64, @floatFromInt(compressed_data.len)) / @as(f64, @floatFromInt(original_size));
        
        return CompressionResult{
            .compressed_data = data_copy,
            .original_size = original_size,
            .compressed_size = compressed_data.len,
            .algorithm = algorithm,
            .compression_ratio = compression_ratio,
        };
    }
    
    pub fn deinit(self: CompressionResult, allocator: Allocator) void {
        allocator.free(self.compressed_data);
    }
    
    pub fn getSavings(self: CompressionResult) usize {
        return self.original_size - self.compressed_size;
    }
    
    pub fn getCompressionPercentage(self: CompressionResult) f64 {
        return (1.0 - self.compression_ratio) * 100.0;
    }
};

// Decompression result
pub const DecompressionResult = struct {
    decompressed_data: []u8,
    original_compressed_size: usize,
    decompressed_size: usize,
    algorithm: CompressionAlgorithm,
    
    pub fn init(allocator: Allocator, decompressed_data: []const u8, original_compressed_size: usize, algorithm: CompressionAlgorithm) !DecompressionResult {
        const data_copy = try allocator.dupe(u8, decompressed_data);
        
        return DecompressionResult{
            .decompressed_data = data_copy,
            .original_compressed_size = original_compressed_size,
            .decompressed_size = decompressed_data.len,
            .algorithm = algorithm,
        };
    }
    
    pub fn deinit(self: DecompressionResult, allocator: Allocator) void {
        allocator.free(self.decompressed_data);
    }
};

// Compression statistics
pub const CompressionStats = struct {
    total_compressions: u64,
    total_decompressions: u64,
    total_bytes_compressed: u64,
    total_bytes_decompressed: u64,
    total_compression_time_ms: u64,
    total_decompression_time_ms: u64,
    average_compression_ratio: f64,
    bytes_saved: u64,
    
    pub fn init() CompressionStats {
        return CompressionStats{
            .total_compressions = 0,
            .total_decompressions = 0,
            .total_bytes_compressed = 0,
            .total_bytes_decompressed = 0,
            .total_compression_time_ms = 0,
            .total_decompression_time_ms = 0,
            .average_compression_ratio = 0.0,
            .bytes_saved = 0,
        };
    }
    
    pub fn updateCompression(self: *CompressionStats, original_size: usize, compressed_size: usize, time_ms: u64) void {
        self.total_compressions += 1;
        self.total_bytes_compressed += original_size;
        self.total_compression_time_ms += time_ms;
        self.bytes_saved += (original_size - compressed_size);
        
        // Update average compression ratio
        const ratio = @as(f64, @floatFromInt(compressed_size)) / @as(f64, @floatFromInt(original_size));
        self.average_compression_ratio = (self.average_compression_ratio * @as(f64, @floatFromInt(self.total_compressions - 1)) + ratio) / @as(f64, @floatFromInt(self.total_compressions));
    }
    
    pub fn updateDecompression(self: *CompressionStats, decompressed_size: usize, time_ms: u64) void {
        self.total_decompressions += 1;
        self.total_bytes_decompressed += decompressed_size;
        self.total_decompression_time_ms += time_ms;
    }
    
    pub fn getAverageCompressionTime(self: CompressionStats) f64 {
        if (self.total_compressions == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_compression_time_ms)) / @as(f64, @floatFromInt(self.total_compressions));
    }
    
    pub fn getAverageDecompressionTime(self: CompressionStats) f64 {
        if (self.total_decompressions == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_decompression_time_ms)) / @as(f64, @floatFromInt(self.total_decompressions));
    }
    
    pub fn getTotalBytesSaved(self: CompressionStats) u64 {
        return self.bytes_saved;
    }
};

// LZ77-based compression implementation
const SimpleLZ77 = struct {
    const MIN_MATCH_LENGTH = 3;
    const MAX_MATCH_LENGTH = 258;
    const WINDOW_SIZE = 32768;
    
    pub fn compress(allocator: Allocator, data: []const u8) ![]u8 {
        if (data.len == 0) return try allocator.alloc(u8, 0);
        
        var compressed = ArrayList(u8).init(allocator);
        var pos: usize = 0;
        
        while (pos < data.len) {
            const match = findLongestMatch(data, pos);
            
            if (match.length >= MIN_MATCH_LENGTH) {
                // Encode as (distance, length)
                try compressed.append(0xFF); // Marker for match
                try compressed.append(@intCast(match.distance & 0xFF));
                try compressed.append(@intCast((match.distance >> 8) & 0xFF));
                try compressed.append(@intCast(match.length));
                pos += match.length;
            } else {
                // Encode as literal
                try compressed.append(data[pos]);
                pos += 1;
            }
        }
        
        return compressed.toOwnedSlice();
    }
    
    pub fn decompress(allocator: Allocator, compressed_data: []const u8) ![]u8 {
        if (compressed_data.len == 0) return try allocator.alloc(u8, 0);
        
        var decompressed = ArrayList(u8).init(allocator);
        var pos: usize = 0;
        
        while (pos < compressed_data.len) {
            if (compressed_data[pos] == 0xFF and pos + 3 < compressed_data.len) {
                // This is a match
                const distance = @as(u16, compressed_data[pos + 1]) | (@as(u16, compressed_data[pos + 2]) << 8);
                const length = compressed_data[pos + 3];
                
                // Copy from history
                const start_pos = decompressed.items.len - distance;
                for (0..length) |_| {
                    const byte = decompressed.items[start_pos + (decompressed.items.len - start_pos) % distance];
                    try decompressed.append(byte);
                }
                
                pos += 4;
            } else {
                // This is a literal
                try decompressed.append(compressed_data[pos]);
                pos += 1;
            }
        }
        
        return decompressed.toOwnedSlice();
    }
    
    const Match = struct {
        distance: u16,
        length: u8,
    };
    
    fn findLongestMatch(data: []const u8, pos: usize) Match {
        if (pos == 0) return Match{ .distance = 0, .length = 0 };
        
        var best_match = Match{ .distance = 0, .length = 0 };
        const search_start = if (pos > WINDOW_SIZE) pos - WINDOW_SIZE else 0;
        
        for (search_start..pos) |start| {
            var length: usize = 0;
            
            while (start + length < pos and 
                   pos + length < data.len and 
                   data[start + length] == data[pos + length] and
                   length < MAX_MATCH_LENGTH) {
                length += 1;
            }
            
            if (length >= MIN_MATCH_LENGTH and length > best_match.length) {
                best_match = Match{
                    .distance = @intCast(pos - start),
                    .length = @intCast(length),
                };
            }
        }
        
        return best_match;
    }
};

// Compression engine
pub const CompressionEngine = struct {
    allocator: Allocator,
    config: CompressionConfig,
    stats: CompressionStats,
    
    pub fn init(allocator: Allocator, config: CompressionConfig) CompressionEngine {
        return CompressionEngine{
            .allocator = allocator,
            .config = config,
            .stats = CompressionStats.init(),
        };
    }
    
    pub fn compress(self: *CompressionEngine, data: []const u8) !?CompressionResult {
        if (!self.config.shouldCompress(data.len)) {
            return null; // Don't compress
        }
        
        const start_time = std.time.milliTimestamp();
        const compressed_data = try self.compressData(data);
        const end_time = std.time.milliTimestamp();
        
        const compression_time = @as(u64, @intCast(end_time - start_time));
        self.stats.updateCompression(data.len, compressed_data.len, compression_time);
        
        return CompressionResult.init(self.allocator, compressed_data, data.len, self.config.algorithm);
    }
    
    pub fn decompress(self: *CompressionEngine, compressed_data: []const u8, algorithm: CompressionAlgorithm) !DecompressionResult {
        const start_time = std.time.milliTimestamp();
        const decompressed_data = try self.decompressData(compressed_data, algorithm);
        const end_time = std.time.milliTimestamp();
        
        const decompression_time = @as(u64, @intCast(end_time - start_time));
        self.stats.updateDecompression(decompressed_data.len, decompression_time);
        
        return DecompressionResult.init(self.allocator, decompressed_data, compressed_data.len, algorithm);
    }
    
    pub fn getStats(self: CompressionEngine) CompressionStats {
        return self.stats;
    }
    
    pub fn resetStats(self: *CompressionEngine) void {
        self.stats = CompressionStats.init();
    }
    
    fn compressData(self: *CompressionEngine, data: []const u8) ![]u8 {
        return switch (self.config.algorithm) {
            .none => try self.allocator.dupe(u8, data),
            .gzip => try self.compressGzip(data),
            .deflate => try self.compressDeflate(data),
            .brotli => try self.compressBrotli(data),
            .lz4 => try self.compressLZ4(data),
            .zstd => try self.compressZstd(data),
        };
    }
    
    fn decompressData(self: *CompressionEngine, compressed_data: []const u8, algorithm: CompressionAlgorithm) ![]u8 {
        return switch (algorithm) {
            .none => try self.allocator.dupe(u8, compressed_data),
            .gzip => try self.decompressGzip(compressed_data),
            .deflate => try self.decompressDeflate(compressed_data),
            .brotli => try self.decompressBrotli(compressed_data),
            .lz4 => try self.decompressLZ4(compressed_data),
            .zstd => try self.decompressZstd(compressed_data),
        };
    }
    
    // Compression implementations using standard library
    
    fn compressGzip(self: *CompressionEngine, data: []const u8) ![]u8 {
        // Use Zig's standard deflate for gzip compression
        var compressed = ArrayList(u8).init(self.allocator);
        try std.compress.gzip.compress(self.allocator, data, compressed.writer(), .{});
        return compressed.toOwnedSlice();
    }
    
    fn decompressGzip(self: *CompressionEngine, compressed_data: []const u8) ![]u8 {
        var stream = std.io.fixedBufferStream(compressed_data);
        var decompressed = ArrayList(u8).init(self.allocator);
        try std.compress.gzip.decompress(stream.reader(), decompressed.writer());
        return decompressed.toOwnedSlice();
    }
    
    fn compressDeflate(self: *CompressionEngine, data: []const u8) ![]u8 {
        var compressed = ArrayList(u8).init(self.allocator);
        try std.compress.deflate.compress(self.allocator, data, compressed.writer(), .{});
        return compressed.toOwnedSlice();
    }
    
    fn decompressDeflate(self: *CompressionEngine, compressed_data: []const u8) ![]u8 {
        var stream = std.io.fixedBufferStream(compressed_data);
        var decompressed = ArrayList(u8).init(self.allocator);
        try std.compress.deflate.decompress(stream.reader(), decompressed.writer());
        return decompressed.toOwnedSlice();
    }
    
    fn compressBrotli(self: *CompressionEngine, data: []const u8) ![]u8 {
        // Simplified implementation - in deployment use libbrotli
        return SimpleLZ77.compress(self.allocator, data);
    }
    
    fn decompressBrotli(self: *CompressionEngine, compressed_data: []const u8) ![]u8 {
        return SimpleLZ77.decompress(self.allocator, compressed_data);
    }
    
    fn compressLZ4(self: *CompressionEngine, data: []const u8) ![]u8 {
        // Simplified implementation - in deployment use liblz4
        return SimpleLZ77.compress(self.allocator, data);
    }
    
    fn decompressLZ4(self: *CompressionEngine, compressed_data: []const u8) ![]u8 {
        return SimpleLZ77.decompress(self.allocator, compressed_data);
    }
    
    fn compressZstd(self: *CompressionEngine, data: []const u8) ![]u8 {
        // Simplified implementation - in deployment use libzstd
        return SimpleLZ77.compress(self.allocator, data);
    }
    
    fn decompressZstd(self: *CompressionEngine, compressed_data: []const u8) ![]u8 {
        return SimpleLZ77.decompress(self.allocator, compressed_data);
    }
};

// Adaptive compression that chooses the best algorithm
pub const AdaptiveCompression = struct {
    allocator: Allocator,
    engines: std.EnumMap(CompressionAlgorithm, CompressionEngine),
    sample_size: usize,
    
    pub fn init(allocator: Allocator, algorithms: []const CompressionAlgorithm, sample_size: usize) !AdaptiveCompression {
        var engines = std.EnumMap(CompressionAlgorithm, CompressionEngine){};
        
        for (algorithms) |algorithm| {
            const config = CompressionConfig.init(algorithm);
            const engine = CompressionEngine.init(allocator, config);
            engines.put(algorithm, engine);
        }
        
        return AdaptiveCompression{
            .allocator = allocator,
            .engines = engines,
            .sample_size = sample_size,
        };
    }
    
    pub fn findBestAlgorithm(self: *AdaptiveCompression, data: []const u8) !CompressionAlgorithm {
        if (data.len == 0) return .none;
        
        // Use a sample of the data for testing if data is large
        const sample_data = if (data.len > self.sample_size) data[0..self.sample_size] else data;
        
        var best_algorithm = CompressionAlgorithm.none;
        var best_ratio: f64 = 1.0;
        
        var engine_iter = self.engines.iterator();
        while (engine_iter.next()) |entry| {
            const algorithm = entry.key;
            const engine = entry.value;
            
            if (algorithm == .none) continue;
            
            if (engine.compress(sample_data)) |result| {
                if (result) |compression_result| {
                    defer compression_result.deinit(self.allocator);
                    
                    if (compression_result.compression_ratio < best_ratio) {
                        best_ratio = compression_result.compression_ratio;
                        best_algorithm = algorithm;
                    }
                }
            } else |_| {
                // Compression failed, skip this algorithm
                continue;
            }
        }
        
        return best_algorithm;
    }
    
    pub fn compressWithBestAlgorithm(self: *AdaptiveCompression, data: []const u8) !?CompressionResult {
        const best_algorithm = try self.findBestAlgorithm(data);
        
        if (best_algorithm == .none) return null;
        
        if (self.engines.getPtr(best_algorithm)) |engine| {
            return engine.compress(data);
        }
        
        return null;
    }
};

// Compression middleware for HTTP-like protocols
pub const CompressionMiddleware = struct {
    allocator: Allocator,
    engine: CompressionEngine,
    supported_algorithms: []const CompressionAlgorithm,
    
    pub fn init(allocator: Allocator, config: CompressionConfig, supported_algorithms: []const CompressionAlgorithm) !CompressionMiddleware {
        return CompressionMiddleware{
            .allocator = allocator,
            .engine = CompressionEngine.init(allocator, config),
            .supported_algorithms = try allocator.dupe(CompressionAlgorithm, supported_algorithms),
        };
    }
    
    pub fn deinit(self: CompressionMiddleware) void {
        self.allocator.free(self.supported_algorithms);
    }
    
    pub fn processOutgoingData(self: *CompressionMiddleware, data: []const u8, accepted_encodings: []const []const u8) !ProcessedData {
        // Find the best supported algorithm
        const selected_algorithm = self.selectAlgorithm(accepted_encodings);
        
        if (selected_algorithm == .none) {
            return ProcessedData{
                .data = try self.allocator.dupe(u8, data),
                .algorithm = .none,
                .compressed = false,
            };
        }
        
        // Update engine configuration
        self.engine.config.algorithm = selected_algorithm;
        
        if (try self.engine.compress(data)) |result| {
            return ProcessedData{
                .data = result.compressed_data,
                .algorithm = result.algorithm,
                .compressed = true,
            };
        } else {
            return ProcessedData{
                .data = try self.allocator.dupe(u8, data),
                .algorithm = .none,
                .compressed = false,
            };
        }
    }
    
    pub fn processIncomingData(self: *CompressionMiddleware, data: []const u8, content_encoding: []const u8) !ProcessedData {
        const algorithm = CompressionAlgorithm.fromString(content_encoding) orelse .none;
        
        if (algorithm == .none) {
            return ProcessedData{
                .data = try self.allocator.dupe(u8, data),
                .algorithm = .none,
                .compressed = false,
            };
        }
        
        const result = try self.engine.decompress(data, algorithm);
        return ProcessedData{
            .data = result.decompressed_data,
            .algorithm = algorithm,
            .compressed = true,
        };
    }
    
    fn selectAlgorithm(self: CompressionMiddleware, accepted_encodings: []const []const u8) CompressionAlgorithm {
        // Priority order for algorithm selection
        const priority_order = [_]CompressionAlgorithm{ .brotli, .zstd, .gzip, .deflate, .lz4 };
        
        for (priority_order) |algorithm| {
            // Check if algorithm is supported by us
            var supported = false;
            for (self.supported_algorithms) |supported_alg| {
                if (supported_alg == algorithm) {
                    supported = true;
                    break;
                }
            }
            
            if (!supported) continue;
            
            // Check if algorithm is accepted by client
            const algorithm_str = algorithm.toString();
            for (accepted_encodings) |encoding| {
                if (std.mem.eql(u8, encoding, algorithm_str)) {
                    return algorithm;
                }
            }
        }
        
        return .none;
    }
};

// Processed data result
pub const ProcessedData = struct {
    data: []u8,
    algorithm: CompressionAlgorithm,
    compressed: bool,
    
    pub fn deinit(self: ProcessedData, allocator: Allocator) void {
        allocator.free(self.data);
    }
};

// Test cases
test "CompressionAlgorithm basic operations" {
    try testing.expect(std.mem.eql(u8, "gzip", CompressionAlgorithm.gzip.toString()));
    try testing.expectEqual(CompressionAlgorithm.gzip, CompressionAlgorithm.fromString("gzip"));
    try testing.expect(CompressionAlgorithm.gzip.getCompressionLevel() > 0);
    try testing.expect(CompressionAlgorithm.gzip.getTypicalCompressionRatio() < 1.0);
}

test "CompressionConfig operations" {
    const config = CompressionConfig.init(.gzip);
    
    try testing.expectEqual(CompressionAlgorithm.gzip, config.algorithm);
    try testing.expect(config.shouldCompress(2048)); // Above threshold
    try testing.expect(!config.shouldCompress(512)); // Below threshold
    try testing.expect(config.getEffectiveLevel() > 0);
}

test "SimpleLZ77 compression and decompression" {
    const allocator = testing.allocator;
    
    const test_data = "This is a test string with some repeated patterns. This is a test string with some repeated patterns.";
    
    const compressed = try SimpleLZ77.compress(allocator, test_data);
    defer allocator.free(compressed);
    
    const decompressed = try SimpleLZ77.decompress(allocator, compressed);
    defer allocator.free(decompressed);
    
    try testing.expect(std.mem.eql(u8, test_data, decompressed));
    try testing.expect(compressed.len < test_data.len); // Should be compressed
}

test "CompressionEngine basic functionality" {
    const allocator = testing.allocator;
    
    const config = CompressionConfig.init(.gzip);
    var engine = CompressionEngine.init(allocator, config);
    
    const test_data = "Hello, World! This is a test of compression functionality.";
    
    if (try engine.compress(test_data)) |compression_result| {
        defer compression_result.deinit(allocator);
        
        try testing.expect(compression_result.compressed_size > 0);
        try testing.expect(compression_result.compression_ratio > 0.0);
        
        const decompression_result = try engine.decompress(compression_result.compressed_data, compression_result.algorithm);
        defer decompression_result.deinit(allocator);
        
        try testing.expect(std.mem.eql(u8, test_data, decompression_result.decompressed_data));
    }
    
    const stats = engine.getStats();
    try testing.expect(stats.total_compressions > 0);
    try testing.expect(stats.total_decompressions > 0);
}

test "CompressionStats tracking" {
    var stats = CompressionStats.init();
    
    stats.updateCompression(1000, 300, 50);
    stats.updateDecompression(1000, 25);
    
    try testing.expectEqual(@as(u64, 1), stats.total_compressions);
    try testing.expectEqual(@as(u64, 1), stats.total_decompressions);
    try testing.expectEqual(@as(u64, 700), stats.bytes_saved);
    try testing.expect(stats.getAverageCompressionTime() > 0.0);
    try testing.expect(stats.getAverageDecompressionTime() > 0.0);
}