const std = @import("std");
const hedera = @import("hedera");
const json_rpc = @import("json_rpc.zig");
const sdk_service = @import("methods/sdk_service.zig");
const account_service = @import("methods/account_service.zig");
const token_service = @import("methods/token_service.zig");
const file_service = @import("methods/file_service.zig");
const topic_service = @import("methods/topic_service.zig");
const contract_service = @import("methods/contract_service.zig");
const key_service = @import("methods/key_service.zig");

const log = std.log.scoped(.tck_server);

pub const TCKServer = struct {
    allocator: std.mem.Allocator,
    client: ?*hedera.Client,
    port: u16,
    
    pub fn init(allocator: std.mem.Allocator, port: u16) TCKServer {
        return .{
            .allocator = allocator,
            .client = null,
            .port = port,
        };
    }
    
    pub fn deinit(self: *TCKServer) void {
        if (self.client) |client| {
            client.deinit();
        }
    }
    
    pub fn start(self: *TCKServer) !void {
        const address = try std.net.Address.parseIp("0.0.0.0", self.port);
        
        var listener = address.listen(.{}) catch |err| switch (err) {
            error.AddressInUse => {
                log.err("❌ Port {d} is already in use!", .{self.port});
                log.err("💡 Another TCK server or application might already be running on this port.", .{});
                log.err("💡 Try stopping the other service or using a different port with:", .{});
                log.err("   TCK_PORT=8545 zig build run", .{});
                return error.PortAlreadyInUse;
            },
            error.PermissionDenied => {
                log.err("❌ Permission denied when trying to bind to port {d}!", .{self.port});
                log.err("💡 Ports below 1024 require administrator privileges.", .{});
                log.err("💡 Try using a port above 1024 or run with appropriate permissions.", .{});
                return error.InsufficientPermissions;
            },
            error.AddressNotAvailable => {
                log.err("❌ The address 0.0.0.0:{d} is not available!", .{self.port});
                log.err("💡 This might be a network configuration issue.", .{});
                return error.AddressUnavailable;
            },
            else => {
                log.err("❌ Failed to start TCK server on port {d}: {}", .{ self.port, err });
                log.err("💡 Please check your network configuration and try again.", .{});
                return err;
            },
        };
        defer listener.deinit();
        
        log.info("✅ TCK Server listening on port {d}", .{self.port});
        log.info("🚀 Ready to receive JSON-RPC requests", .{});
        log.info("💡 Send JSON-RPC requests to http://localhost:{d}", .{self.port});
        
        while (true) {
            const connection = try listener.accept();
            defer connection.stream.close();
            
            try self.handleConnection(connection);
        }
    }
    
    fn handleConnection(self: *TCKServer, connection: std.net.Server.Connection) !void {
        // Read the HTTP request properly
        var buffer: [10 * 1024 * 1024]u8 = undefined; // 10MB buffer
        var total_read: usize = 0;
        var headers_end: ?usize = null;
        var content_length: ?usize = null;
        
        // Read until we find the headers end
        while (headers_end == null and total_read < buffer.len) {
            const bytes_read = try connection.stream.read(buffer[total_read..]);
            if (bytes_read == 0) break;
            total_read += bytes_read;
            
            // Look for the end of headers
            if (std.mem.indexOf(u8, buffer[0..total_read], "\r\n\r\n")) |end_pos| {
                headers_end = end_pos;
                
                // Parse Content-Length from headers
                const headers = buffer[0..end_pos];
                var lines = std.mem.splitSequence(u8, headers, "\r\n");
                while (lines.next()) |line| {
                    if (std.ascii.startsWithIgnoreCase(line, "content-length:")) {
                        const length_str = std.mem.trim(u8, line[15..], " \t");
                        content_length = std.fmt.parseInt(usize, length_str, 10) catch null;
                        break;
                    }
                }
                break;
            }
        }
        
        if (headers_end == null) {
            try self.sendError(connection, "Invalid HTTP request - no headers end found");
            return;
        }
        
        const headers_len = headers_end.? + 4;
        var body_len: usize = 0;
        
        // Calculate how much body we already have
        if (total_read > headers_len) {
            body_len = total_read - headers_len;
        }
        
        // Read remaining body if needed
        if (content_length) |expected_len| {
            while (body_len < expected_len and (headers_len + body_len) < buffer.len) {
                const bytes_read = try connection.stream.read(buffer[headers_len + body_len..]);
                if (bytes_read == 0) break;
                body_len += bytes_read;
            }
        }
        
        if (body_len == 0) {
            try self.sendError(connection, "No request body found");
            return;
        }
        
        const body = buffer[headers_len..headers_len + body_len];
        log.debug("Received raw request ({d} bytes total, {d} body bytes)", .{total_read, body_len});
        log.debug("Request body: {s}", .{body});
        
        // Parse JSON-RPC request
        var rpc_request = json_rpc.Request.parse(self.allocator, body) catch |err| {
            log.err("Failed to parse JSON-RPC request: {}", .{err});
            try self.sendJsonResponse(connection, json_rpc.Response.err(
                json_rpc.ErrorCode.PARSE_ERROR,
                "Parse error",
                null,
                null,
            ));
            return;
        };
        defer rpc_request.deinit(self.allocator);
        
        // Process the request
        const rpc_response = try self.processRequest(&rpc_request);
        defer {
            var resp = rpc_response;
            resp.deinit(self.allocator);
        }
        
        // Send response
        try self.sendJsonResponse(connection, rpc_response);
    }
    
    fn processRequest(self: *TCKServer, request: *json_rpc.Request) !json_rpc.Response {
        const method = json_rpc.Method.fromString(request.method) orelse {
            log.warn("Method not found: {s}", .{request.method});
            return json_rpc.Response.err(
                json_rpc.ErrorCode.METHOD_NOT_FOUND,
                "Method not found",
                null,
                request.id,
            );
        };
        
        log.info("Processing method: {s}", .{request.method});
        
        // Route to appropriate service
        const result = switch (method) {
            // SDK Service methods
            .setup => try sdk_service.setup(self.allocator, &self.client, request.params),
            .reset => try sdk_service.reset(self.allocator, &self.client, request.params),
            
            // Account Service methods
            .createAccount => try account_service.createAccount(self.allocator, self.client, request.params),
            .updateAccount => try account_service.updateAccount(self.allocator, self.client, request.params),
            .deleteAccount => try account_service.deleteAccount(self.allocator, self.client, request.params),
            .approveAllowance => try account_service.approveAllowance(self.allocator, self.client, request.params),
            .deleteAllowance => try account_service.deleteAllowance(self.allocator, self.client, request.params),
            .transferCrypto => try account_service.transferCrypto(self.allocator, self.client, request.params),
            
            // Token Service methods
            .createToken => try token_service.createToken(self.allocator, self.client, request.params),
            .updateToken => try token_service.updateToken(self.allocator, self.client, request.params),
            .deleteToken => try token_service.deleteToken(self.allocator, self.client, request.params),
            .updateTokenFeeSchedule => try token_service.updateTokenFeeSchedule(self.allocator, self.client, request.params),
            .associateToken => try token_service.associateToken(self.allocator, self.client, request.params),
            .dissociateToken => try token_service.dissociateToken(self.allocator, self.client, request.params),
            .pauseToken => try token_service.pauseToken(self.allocator, self.client, request.params),
            .unpauseToken => try token_service.unpauseToken(self.allocator, self.client, request.params),
            .freezeToken => try token_service.freezeToken(self.allocator, self.client, request.params),
            .unfreezeToken => try token_service.unfreezeToken(self.allocator, self.client, request.params),
            .grantTokenKyc => try token_service.grantTokenKyc(self.allocator, self.client, request.params),
            .revokeTokenKyc => try token_service.revokeTokenKyc(self.allocator, self.client, request.params),
            .mintToken => try token_service.mintToken(self.allocator, self.client, request.params),
            .burnToken => try token_service.burnToken(self.allocator, self.client, request.params),
            .wipeToken => try token_service.wipeToken(self.allocator, self.client, request.params),
            .claimToken => try token_service.claimToken(self.allocator, self.client, request.params),
            .airdropToken => try token_service.airdropToken(self.allocator, self.client, request.params),
            .cancelAirdrop => try token_service.cancelAirdrop(self.allocator, self.client, request.params),
            .rejectToken => try token_service.rejectToken(self.allocator, self.client, request.params),
            
            // File Service methods
            .createFile => try file_service.createFile(self.allocator, self.client, request.params),
            .updateFile => try file_service.updateFile(self.allocator, self.client, request.params),
            .deleteFile => try file_service.deleteFile(self.allocator, self.client, request.params),
            .appendFile => try file_service.appendFile(self.allocator, self.client, request.params),
            
            // Topic Service methods
            .createTopic => try topic_service.createTopic(self.allocator, self.client, request.params),
            .updateTopic => try topic_service.updateTopic(self.allocator, self.client, request.params),
            .deleteTopic => try topic_service.deleteTopic(self.allocator, self.client, request.params),
            .submitTopicMessage => try topic_service.submitTopicMessage(self.allocator, self.client, request.params),
            
            // Contract Service methods
            .createContract => try contract_service.createContract(self.allocator, self.client, request.params),
            .updateContract => try contract_service.updateContract(self.allocator, self.client, request.params),
            .deleteContract => try contract_service.deleteContract(self.allocator, self.client, request.params),
            .executeContract => try contract_service.executeContract(self.allocator, self.client, request.params),
            
            // Key Service methods
            .generateKey => try key_service.generateKey(self.allocator, request.params),
        };
        
        return json_rpc.Response.success(self.allocator, result, request.id);
    }
    
    fn sendJsonResponse(self: *TCKServer, connection: std.net.Server.Connection, rpc_response: json_rpc.Response) !void {
        const json_str = try rpc_response.stringify(self.allocator);
        defer self.allocator.free(json_str);
        
        // Create HTTP response
        const http_response = try std.fmt.allocPrint(self.allocator,
            "HTTP/1.1 200 OK\r\n" ++
            "Content-Type: application/json\r\n" ++
            "Content-Length: {d}\r\n" ++
            "Connection: close\r\n" ++
            "Access-Control-Allow-Origin: *\r\n" ++
            "Access-Control-Allow-Methods: POST, OPTIONS\r\n" ++
            "Access-Control-Allow-Headers: Content-Type\r\n" ++
            "\r\n" ++
            "{s}",
            .{ json_str.len, json_str }
        );
        defer self.allocator.free(http_response);
        
        _ = try connection.stream.writeAll(http_response);
        
        log.debug("Sent response: {s}", .{json_str});
    }
    
    fn sendError(self: *TCKServer, connection: std.net.Server.Connection, message: []const u8) !void {
        const http_response = try std.fmt.allocPrint(self.allocator,
            "HTTP/1.1 400 Bad Request\r\n" ++
            "Content-Type: text/plain\r\n" ++
            "Content-Length: {d}\r\n" ++
            "Connection: close\r\n" ++
            "\r\n" ++
            "{s}",
            .{ message.len, message }
        );
        defer self.allocator.free(http_response);
        
        _ = try connection.stream.writeAll(http_response);
        
        log.debug("Sent error: {s}", .{message});
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Get port from environment or use default
    const port_str = std.process.getEnvVarOwned(allocator, "TCK_PORT") catch "8544";
    defer if (!std.mem.eql(u8, port_str, "8544")) allocator.free(port_str);
    const port = try std.fmt.parseInt(u16, port_str, 10);
    
    log.info("Starting Hedera SDK Zig TCK Server", .{});
    log.info("Version: 1.0.0", .{});
    
    var server = TCKServer.init(allocator, port);
    defer server.deinit();
    
    server.start() catch |err| switch (err) {
        error.PortAlreadyInUse => {
            log.err("⛔ Cannot start TCK server - port {d} is already in use.", .{port});
            std.process.exit(1);
        },
        error.InsufficientPermissions => {
            log.err("⛔ Cannot start TCK server - insufficient permissions for port {d}.", .{port});
            std.process.exit(1);
        },
        error.AddressUnavailable => {
            log.err("⛔ Cannot start TCK server - address not available.", .{});
            std.process.exit(1);
        },
        else => {
            log.err("⛔ Failed to start TCK server: {}", .{err});
            std.process.exit(1);
        },
    };
}