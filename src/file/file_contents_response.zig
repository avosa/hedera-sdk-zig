const std = @import("std");
const FileId = @import("../core/id.zig").FileId;

// FileContentsResponse contains the response from a file contents query
pub const FileContentsResponse = struct {
    file_id: FileId,
    contents: []const u8,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) FileContentsResponse {
        return FileContentsResponse{
            .file_id = FileId.init(0, 0, 0),
            .contents = &[_]u8{},
            .allocator = allocator,
        };
    }
    
    pub fn initWithData(allocator: std.mem.Allocator, file_id: FileId, contents: []const u8) !FileContentsResponse {
        const contents_copy = try allocator.dupe(u8, contents);
        return FileContentsResponse{
            .file_id = file_id,
            .contents = contents_copy,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *FileContentsResponse) void {
        if (self.contents.len > 0) {
            self.allocator.free(self.contents);
        }
    }
};