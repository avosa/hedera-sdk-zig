# Zig SDK TCK Server

This is a server that implements the [SDK TCK specification](https://github.com/hiero-ledger/hiero-sdk-tck/) for the Hedera SDK Zig implementation.

## TARGET: Overview

The Technology Compatibility Kit (TCK) ensures that the Zig SDK implements the Hedera protocol correctly and consistently with other official SDKs. It provides a JSON-RPC 2.0 server that exposes all SDK functionality for automated testing and validation.

## LAUNCH Quick Start

### Prerequisites

- **Zig**: Version 0.14.1 or higher
- **Docker**: Latest version (optional)
- **Docker Compose**: Latest version (optional)

### Local Development

```bash
# Build and run the TCK server
cd tck
zig build run

# The server will start on port 8544 by default
```

### Environment Variables

- `TCK_PORT`: Port to run the server on (default: 8544)
- `NETWORK`: Network to connect to (testnet, mainnet, previewnet, local-node)
- `OPERATOR_ACCOUNT_ID`: Default operator account ID
- `OPERATOR_ACCOUNT_PRIVATE_KEY`: Default operator private key
- `MIRROR_NODE_REST_URL`: Mirror node REST endpoint
- `MIRROR_NODE_REST_JAVA_URL`: Mirror node Java REST endpoint

##  Docker Usage

### Build and Run with Docker Compose

```bash
# Start the TCK server
docker-compose up --build

# Run in background
docker-compose up -d --build

# Stop the server
docker-compose down
```

### Build Docker Image Manually

```bash
# Build the image
docker build -t hedera-sdk-zig-tck -f tck/Dockerfile .

# Run the container
docker run -p 8544:8544 hedera-sdk-zig-tck
```

## SETUP Configuration

The TCK server can be configured in several ways:

### 1. Environment Variables

```bash
export TCK_PORT=8544
export NETWORK=testnet
export OPERATOR_ACCOUNT_ID=0.0.1001
export OPERATOR_ACCOUNT_PRIVATE_KEY=302e020100300506032b657004220420...
```

### 2. Docker Environment File

Create a `.env` file in the tck directory:

```env
TCK_PORT=8544
NETWORK=testnet
OPERATOR_ACCOUNT_ID=0.0.1001
OPERATOR_ACCOUNT_PRIVATE_KEY=302e020100300506032b657004220420...
```

### 3. Runtime Configuration

Use the `setup` JSON-RPC method to configure the client at runtime:

```json
{
  "jsonrpc": "2.0",
  "method": "setup",
  "params": {
    "network": "testnet",
    "operatorAccountId": "0.0.1001",
    "operatorPrivateKey": "302e020100300506032b657004220420..."
  },
  "id": 1
}
```

##  API Reference

The TCK server implements JSON-RPC 2.0 and supports the following methods:

### SDK Management

- `setup` - Configure the SDK client
- `reset` - Reset the SDK client

### Account Operations

- `createAccount` - Create a new account
- `updateAccount` - Update an existing account
- `deleteAccount` - Delete an account
- `approveAllowance` - Approve crypto/token allowances
- `deleteAllowance` - Delete allowances
- `transferCrypto` - Transfer HBAR, tokens, or NFTs

### Token Operations

- `createToken` - Create a new token
- `updateToken` - Update token properties
- `deleteToken` - Delete a token
- `associateToken` - Associate token with account
- `dissociateToken` - Dissociate token from account
- `pauseToken` / `unpauseToken` - Pause/unpause token
- `freezeToken` / `unfreezeToken` - Freeze/unfreeze token
- `grantTokenKyc` / `revokeTokenKyc` - Manage KYC status
- `mintToken` / `burnToken` - Mint/burn tokens
- `wipeToken` - Wipe tokens from account

### File Operations

- `createFile` - Create a file
- `updateFile` - Update file contents
- `deleteFile` - Delete a file
- `appendFile` - Append to file

### Topic Operations

- `createTopic` - Create a consensus topic
- `updateTopic` - Update topic properties
- `deleteTopic` - Delete a topic
- `submitTopicMessage` - Submit message to topic

### Contract Operations

- `createContract` - Deploy a smart contract
- `updateContract` - Update contract
- `deleteContract` - Delete contract
- `executeContract` - Execute contract function

### Key Operations

- `generateKey` - Generate Ed25519 key pair

## TEST: Testing

### Test the Server

```bash
# Test basic connectivity
curl -X POST http://localhost:8544 \\
  -H "Content-Type: application/json" \\
  -d '{
    "jsonrpc": "2.0",
    "method": "generateKey",
    "id": 1
  }'
```

### Run TCK Tests

The server is designed to work with the official Hedera TCK test suite:

```bash
# Using Task (if available)
task run-specific-test TEST=AccountCreate

# Using Docker
docker run --rm \\
  --network host \\
  -e TCK_SERVER_URL=http://localhost:8544 \\
  hiero-ledger/hiero-sdk-tck:latest \\
  AccountCreate
```

## BUILD: Architecture

```
     JSON-RPC            SDK Calls      
                   >                     >                    
  TCK Test Suite                        TCK Server                           Hedera SDK     
                   <    (Zig HTTP)       <     (Zig Library)  
     JSON Response        Results        
```

### Components

- **`server.zig`**: Main HTTP server and request router
- **`json_rpc.zig`**: JSON-RPC 2.0 protocol implementation
- **`methods/`**: Service implementations for each operation type
- **`utils/`**: Utility functions for parsing and validation
- **`build.zig`**: Build configuration for the TCK server

## SEARCH: Debugging

### Enable Debug Logging

```bash
# Set log level
export ZIG_LOG_LEVEL=debug
zig build run
```

### View Server Logs

```bash
# Docker logs
docker-compose logs -f

# Follow logs in real-time
docker-compose logs -f hedera-sdk-zig-tck
```

### Common Issues

1. **Port Already in Use**: Change `TCK_PORT` environment variable
2. **Network Connection**: Verify network configuration in setup call
3. **Missing Operator**: Set operator credentials via setup or environment

##  Contributing

This TCK implementation ensures compatibility with the official Hedera SDK standards. When adding new methods:

1. Implement the method in the appropriate service file
2. Add method routing in `server.zig`
3. Add method name to `json_rpc.zig` Method enum
4. Test with official TCK test suite
5. Update this README

## NOTE: License

This project is licensed under the Apache License 2.0 - see the [LICENSE](../LICENSE) file for details.

##  Support

- **Issues**: Report bugs or request features in the main repository
- **Documentation**: See the main [Hedera SDK Zig documentation](../README.md)
- **Community**: Join the Hedera developer community

---

**SUCCESS Congratulations!** You now have a fully functional TCK server for the Hedera SDK Zig implementation, ensuring compatibility with the official Hedera ecosystem!