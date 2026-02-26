// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract ShardRegistry {
    struct Shard {
        bytes32 shardId;
        address owner;
        bytes32 contentHash;
        uint256 createdAt;
        bool exists;
    }

    struct Expert {
        bytes32 expertId;
        bytes32[] shardIds;
        address owner;
        uint256 createdAt;
    }

    mapping(bytes32 => Shard) public shards;
    mapping(bytes32 => Expert) public experts;
    mapping(address => bytes32[]) public ownerShards;
    mapping(bytes32 => address[]) public expertContributors;

    event ShardRegistered(bytes32 indexed shardId, address indexed owner, bytes32 contentHash);
    event ExpertCreated(bytes32 indexed expertId, address indexed owner);
    event ShardAddedToExpert(bytes32 indexed expertId, bytes32 indexed shardId);
    event OwnershipTransferred(bytes32 indexed shardId, address indexed from, address indexed to);

    function registerShard(bytes32 _shardId, bytes32 _contentHash) external {
        require(!shards[_shardId].exists, "Shard exists");
        
        shards[_shardId] = Shard({
            shardId: _shardId,
            owner: msg.sender,
            contentHash: _contentHash,
            createdAt: block.timestamp,
            exists: true
        });
        
        ownerShards[msg.sender].push(_shardId);
        
        emit ShardRegistered(_shardId, msg.sender, _contentHash);
    }

    function createExpert(bytes32 _expertId, bytes32[] calldata _shardIds) external {
        require(experts[_expertId].createdAt == 0, "Expert exists");
        
        for (uint i = 0; i < _shardIds.length; i++) {
            require(shards[_shardIds[i]].exists, "Shard not found");
            require(shards[_shardIds[i]].owner == msg.sender, "Not shard owner");
        }
        
        experts[_expertId] = Expert({
            expertId: _expertId,
            shardIds: _shardIds,
            owner: msg.sender,
            createdAt: block.timestamp
        });
        
        emit ExpertCreated(_expertId, msg.sender);
        
        for (uint i = 0; i < _shardIds.length; i++) {
            emit ShardAddedToExpert(_expertId, _shardIds[i]);
        }
    }

    function getShard(bytes32 _shardId) external view returns (
        address owner, bytes32 contentHash, uint256 createdAt
    ) {
        Shard memory s = shards[_shardId];
        return (s.owner, s.contentHash, s.createdAt);
    }

    function getExpert(bytes32 _expertId) external view returns (
        address owner, bytes32[] memory shardIds, uint256 createdAt
    ) {
        Expert memory e = experts[_expertId];
        return (e.owner, e.shardIds, e.createdAt);
    }

    function getOwnerShards(address _owner) external view returns (bytes32[] memory) {
        return ownerShards[_owner];
    }

    function transferShardOwnership(bytes32 _shardId, address _to) external {
        require(shards[_shardId].owner == msg.sender, "Not owner");
        
        address from = shards[_shardId].owner;
        shards[_shardId].owner = _to;
        
        emit OwnershipTransferred(_shardId, from, _to);
    }

    function verifyShardOwnership(bytes32 _shardId, address _owner) external view returns (bool) {
        return shards[_shardId].owner == _owner && shards[_shardId].exists;
    }
}
