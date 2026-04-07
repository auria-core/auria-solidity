// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/ShardRegistry.sol";

contract ShardRegistryTest is Test {
    ShardRegistry public registry;
    
    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    
    bytes32 public testShardId = keccak256("test-shard-1");
    bytes32 public testContentHash = keccak256("content-hash");
    bytes32 public testExpertId = keccak256("test-expert-1");
    
    function setUp() public {
        vm.prank(owner);
        registry = new ShardRegistry();
    }
    
    function testRegisterShard() public {
        vm.prank(user1);
        
        registry.registerShard(
            testShardId,
            testContentHash,
            1024,
            "ipfs://QmTest",
            ShardRegistry.ShardMetadata({
                name: "Test Shard",
                description: "A test shard",
                fileSize: 1024,
                compressionType: "none",
                tensorShape: new uint256[](0)
            })
        );
        
        (address owner_, bytes32 contentHash, uint256 createdAt, uint256 storageSize, bool frozen, string memory uri) = 
            registry.getShard(testShardId);
        
        assertEq(owner_, user1);
        assertEq(contentHash, testContentHash);
        assertEq(storageSize, 1024);
        assertFalse(frozen);
    }
    
    function testRegisterMultipleShards() public {
        bytes32[] memory shardIds = new bytes32[](3);
        bytes32[] memory contentHashes = new bytes32[](3);
        uint256[] memory sizes = new uint256[](3);
        
        for (uint i = 0; i < 3; i++) {
            shardIds[i] = keccak256(abi.encodePacked("shard", i));
            contentHashes[i] = keccak256(abi.encodePacked("hash", i));
            sizes[i] = 1024 * (i + 1);
        }
        
        vm.prank(user1);
        registry.registerMultipleShards(shardIds, contentHashes, sizes);
        
        assertTrue(shards(shardIds[0]).exists);
        assertTrue(shards(shardIds[1]).exists);
        assertTrue(shards(shardIds[2]).exists);
    }
    
    function shards(bytes32 shardId) internal view returns (ShardRegistry.Shard memory) {
        (,,,,,) = registry.getShard(shardId);
    }
    
    function testCreateExpert() public {
        bytes32[] memory shardIds = new bytes32[](2);
        shardIds[0] = testShardId;
        shardIds[1] = keccak256("shard-2");
        
        vm.prank(user1);
        registry.registerShard(
            shardIds[0],
            testContentHash,
            1024,
            "",
            ShardRegistry.ShardMetadata({
                name: "Shard 1",
                description: "",
                fileSize: 1024,
                compressionType: "",
                tensorShape: new uint256[](0)
            })
        );
        
        vm.prank(user1);
        registry.registerShard(
            shardIds[1],
            testContentHash,
            2048,
            "",
            ShardRegistry.ShardMetadata({
                name: "Shard 2",
                description: "",
                fileSize: 2048,
                compressionType: "",
                tensorShape: new uint256[](0)
            })
        );
        
        vm.prank(user1);
        registry.createExpert(testExpertId, shardIds, "ipfs://expert");
        
        (address expertOwner, bytes32[] memory expertShards, uint256 createdAt, uint256 version, bool active,) = 
            registry.getExpert(testExpertId);
        
        assertEq(expertOwner, user1);
        assertEq(expertShards.length, 2);
        assertTrue(active);
    }
    
    function testTransferOwnership() public {
        vm.prank(user1);
        registry.registerShard(
            testShardId,
            testContentHash,
            1024,
            "",
            ShardRegistry.ShardMetadata({
                name: "Test",
                description: "",
                fileSize: 1024,
                compressionType: "",
                tensorShape: new uint256[](0)
            })
        );
        
        vm.prank(user1);
        registry.transferShardOwnership(testShardId, user2);
        
        (address newOwner,,,,,) = registry.getShard(testShardId);
        
        assertEq(newOwner, user2);
    }
    
    function testFreezeShard() public {
        vm.prank(user1);
        registry.registerShard(
            testShardId,
            testContentHash,
            1024,
            "",
            ShardRegistry.ShardMetadata({
                name: "Test",
                description: "",
                fileSize: 1024,
                compressionType: "",
                tensorShape: new uint256[](0)
            })
        );
        
        vm.prank(user1);
        registry.freezeShard(testShardId);
        
        assertTrue(registry.isShardFrozen(testShardId));
    }
    
    function testFailTransferFrozenShard() public {
        vm.prank(user1);
        registry.registerShard(
            testShardId,
            testContentHash,
            1024,
            "",
            ShardRegistry.ShardMetadata({
                name: "Test",
                description: "",
                fileSize: 1024,
                compressionType: "",
                tensorShape: new uint256[](0)
            })
        );
        
        vm.prank(user1);
        registry.freezeShard(testShardId);
        
        vm.prank(user1);
        registry.transferShardOwnership(testShardId, user2);
    }
    
    function testGetStats() public {
        vm.prank(user1);
        registry.registerShard(
            testShardId,
            testContentHash,
            1024,
            "",
            ShardRegistry.ShardMetadata({
                name: "Test",
                description: "",
                fileSize: 1024,
                compressionType: "",
                tensorShape: new uint256[](0)
            })
        );
        
        (uint256 shardCount, uint256 expertCount) = registry.getStats();
        
        assertEq(shardCount, 1);
        assertEq(expertCount, 0);
    }
    
    function testUpdateShardMetadata() public {
        vm.prank(user1);
        registry.registerShard(
            testShardId,
            testContentHash,
            1024,
            "",
            ShardRegistry.ShardMetadata({
                name: "Original",
                description: "Original desc",
                fileSize: 1024,
                compressionType: "",
                tensorShape: new uint256[](0)
            })
        );
        
        vm.prank(user1);
        registry.updateShardMetadata(
            testShardId,
            ShardRegistry.ShardMetadata({
                name: "Updated",
                description: "Updated desc",
                fileSize: 2048,
                compressionType: "gzip",
                tensorShape: new uint256[](0)
            })
        );
        
        (, , , , , string memory uri) = registry.getShard(testShardId);
        assertTrue(bytes(uri).length == 0);
    }
    
    function testExpertVersioning() public {
        bytes32[] memory shardIds = new bytes32[](1);
        shardIds[0] = testShardId;
        
        vm.prank(user1);
        registry.registerShard(
            testShardId,
            testContentHash,
            1024,
            "ipfs://QmTest",
            ShardRegistry.ShardMetadata({
                name: "Test",
                description: "",
                fileSize: 1024,
                compressionType: "",
                tensorShape: new uint256[](0)
            })
        );
        
        vm.prank(user1);
        registry.createExpert(testExpertId, shardIds, "ipfs://v1");
        
        vm.prank(user1);
        registry.updateExpertVersion(testExpertId, "ipfs://v2");
        
        (address expertOwner, , , uint256 version, , ) = registry.getExpert(testExpertId);
        
        assertEq(version, 2);
        assertEq(expertOwner, user1);
    }
    
    function testShardExists() public {
        assertFalse(registry.shardExists(testShardId));
        
        vm.prank(user1);
        registry.registerShard(
            testShardId,
            testContentHash,
            1024,
            "",
            ShardRegistry.ShardMetadata({
                name: "Test",
                description: "",
                fileSize: 1024,
                compressionType: "",
                tensorShape: new uint256[](0)
            })
        );
        
        assertTrue(registry.shardExists(testShardId));
    }
    
    function testDeactivateExpert() public {
        bytes32[] memory shardIds = new bytes32[](1);
        shardIds[0] = testShardId;
        
        vm.prank(user1);
        registry.registerShard(
            testShardId,
            testContentHash,
            1024,
            "",
            ShardRegistry.ShardMetadata({
                name: "Test",
                description: "",
                fileSize: 1024,
                compressionType: "",
                tensorShape: new uint256[](0)
            })
        );
        
        vm.prank(user1);
        registry.createExpert(testExpertId, shardIds, "ipfs://expert");
        
        vm.prank(user1);
        registry.deactivateExpert(testExpertId);
        
        ( , , , , bool active, ) = registry.getExpert(testExpertId);
        
        assertFalse(active);
    }
}
