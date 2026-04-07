# AURIA Solidity Contracts

Solidity smart contracts for the Auria decentralized AI network.

## Overview

This repository contains the blockchain smart contracts that handle:
- **Shard Registry**: Register and manage shard ownership
- **License Registry**: Issue and verify shard licenses
- **Settlement**: Usage accounting and royalty distribution

## Contracts

### ShardRegistry.sol

Manages shard and expert ownership on-chain.

- `registerShard(bytes32 shardId, bytes32 contentHash)` - Register a new shard
- `createExpert(bytes32 expertId, bytes32[] shardIds)` - Create an expert from shards
- `transferShardOwnership(bytes32 shardId, address to)` - Transfer shard ownership
- `verifyShardOwnership(bytes32 shardId, address owner)` - Verify ownership

### LicenseRegistry.sol

Handles license issuance and verification.

- `issueLicense(bytes32 shardId, address nodePublicKey, uint256 expiresAt, bytes signature)` - Issue a license
- `verifyLicense(bytes32 licenseId)` - Verify license validity
- `revokeLicense(bytes32 licenseId)` - Revoke a license
- `addTrustedIssuer(address issuer)` - Add a trusted issuer

### Settlement.sol

Handles usage accounting and reward distribution.

- `submitReceipt(UsageReceipt receipt)` - Submit usage receipt
- `settle(bytes32 root)` - Execute settlement
- `recordUsage(address node, uint256 amount)` - Record node usage
- `withdraw()` - Withdraw earned rewards

## Prerequisites

- Foundry (Forge)
- Solidity 0.8.20+

## Building

```bash
# Install dependencies
forge install

# Build contracts
forge build

# Run tests
forge test
```

## Deployment

```bash
# Deploy to Sepolia testnet
forge create --rpc-url sepolia --private-key $PRIVATE_KEY src/ShardRegistry.sol:ShardRegistry

# Deploy to mainnet
forge create --rpc-url mainnet --private-key $PRIVATE_KEY src/ShardRegistry.sol:ShardRegistry
```

## Usage

### Registering a Shard

```solidity
bytes32 shardId = keccak256(abi.encodePacked("expert-001", "shard-001"));
bytes32 contentHash = keccak256(abi.encodePacked(shardData));

shardRegistry.registerShard(shardId, contentHash);
```

### Issuing a License

```solidity
licenseRegistry.issueLicense(
    shardId,
    nodeAddress,
    block.timestamp + 365 days,
    signature
);
```

### Submitting Usage Receipt

```solidity
bytes32[] memory eventIds = new bytes32[](1);
eventIds[0] = keccak256(abi.encodePacked(node, expert, block.timestamp));

UsageReceipt memory receipt = UsageReceipt({
    receiptId: keccak256(abi.encodePacked(block.timestamp)),
    eventIds: eventIds,
    nodeIdentity: nodeAddress,
    timestamp: block.timestamp,
    signature: signature
});

settlement.submitReceipt(receipt);
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Auria Blockchain Layer                   │
├─────────────────┬─────────────────┬─────────────────────────┤
│  ShardRegistry │ LicenseRegistry │      Settlement         │
│                 │                 │                         │
│ - Shard ownership│ - License issue │ - Usage recording       │
│ - Expert creation│ - Verification  │ - Merkle aggregation   │
│ - Transfers     │ - Revocation    │ - Reward distribution   │
└─────────────────┴─────────────────┴─────────────────────────┘
```

## Security

- All critical functions use access control
- Licenses are cryptographically signed
- Usage receipts are verified on-chain
- Double-spend prevention via receipt IDs

## License

MIT License - see [LICENSE](LICENSE) for details.
