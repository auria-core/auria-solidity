// SPDX-License-Identifier: MIT
// File: ShardRegistry.sol - This file is part of AURIA
// Copyright (c) 2026 AURIA Developers and Contributors
// Description:
//     Manages shard and expert registration on the blockchain.
//     Shards represent partitioned model weights or expertise units,
//     while Experts are composed of multiple shards. Tracks ownership,
//     content hashing, and contributor management for distributed
//     model execution across the AURIA network.
//
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ShardRegistry is Ownable, Pausable, ReentrancyGuard {
    struct Shard {
        bytes32 shardId;
        address owner;
        bytes32 contentHash;
        uint256 createdAt;
        uint256 storageSize;
        bool exists;
        bool frozen;
        string metadataURI;
    }

    struct Expert {
        bytes32 expertId;
        bytes32[] shardIds;
        address owner;
        uint256 createdAt;
        uint256 version;
        bool active;
        string metadataURI;
    }

    struct ShardMetadata {
        string name;
        string description;
        uint256 fileSize;
        string compressionType;
        uint256[] tensorShape;
    }

    mapping(bytes32 => Shard) public shards;
    mapping(bytes32 => Expert) public experts;
    mapping(address => bytes32[]) public ownerShards;
    mapping(address => bytes32[]) public ownerExperts;
    mapping(bytes32 => address[]) public expertContributors;
    mapping(bytes32 => ShardMetadata) public shardMetadata;
    
    uint256 public shardCount;
    uint256 public expertCount;
    uint256 public constant MAX_SHARDS_PER_EXPERT = 256;
    uint256 public constant MAX_SHARDS_PER_OWNER = 10000;

    event ShardRegistered(bytes32 indexed shardId, address indexed owner, bytes32 contentHash, uint256 size);
    event ShardUpdated(bytes32 indexed shardId, bytes32 newContentHash);
    event ShardFrozen(bytes32 indexed shardId);
    event ShardUnfrozen(bytes32 indexed shardId);
    event ExpertCreated(bytes32 indexed expertId, address indexed owner, uint256 shardCount);
    event ExpertUpdated(bytes32 indexed expertId, uint256 newVersion);
    event ExpertActivated(bytes32 indexed expertId);
    event ExpertDeactivated(bytes32 indexed expertId);
    event ShardAddedToExpert(bytes32 indexed expertId, bytes32 indexed shardId);
    event ShardRemovedFromExpert(bytes32 indexed expertId, bytes32 indexed shardId);
    event OwnershipTransferred(bytes32 indexed shardId, address indexed from, address indexed to);
    event MetadataUpdated(bytes32 indexed shardId, string metadataURI);
    event BulkShardRegistered(address indexed owner, uint256 count);

    modifier onlyShardOwner(bytes32 _shardId) {
        require(shards[_shardId].owner == msg.sender, "Not owner");
        require(!shards[_shardId].frozen, "Shard frozen");
        _;
    }

    modifier onlyExpertOwner(bytes32 _expertId) {
        require(experts[_expertId].owner == msg.sender, "Not owner");
        _;
    }

    constructor() Ownable() {}

    function registerShard(
        bytes32 _shardId,
        bytes32 _contentHash,
        uint256 _storageSize,
        string calldata _metadataURI,
        ShardMetadata calldata _metadata
    ) external whenNotPaused nonReentrant {
        require(!shards[_shardId].exists, "Shard exists");
        require(_contentHash != bytes32(0), "Invalid hash");
        require(ownerShards[msg.sender].length < MAX_SHARDS_PER_OWNER, "Too many shards");
        
        shards[_shardId] = Shard({
            shardId: _shardId,
            owner: msg.sender,
            contentHash: _contentHash,
            createdAt: block.timestamp,
            storageSize: _storageSize,
            exists: true,
            frozen: false,
            metadataURI: _metadataURI
        });
        
        shardMetadata[_shardId] = _metadata;
        ownerShards[msg.sender].push(_shardId);
        shardCount++;
        
        emit ShardRegistered(_shardId, msg.sender, _contentHash, _storageSize);
    }

    function registerMultipleShards(
        bytes32[] calldata _shardIds,
        bytes32[] calldata _contentHashes,
        uint256[] calldata _storageSizes
    ) external whenNotPaused nonReentrant {
        require(_shardIds.length == _contentHashes.length, "Length mismatch");
        require(_shardIds.length == _storageSizes.length, "Length mismatch");
        
        for (uint i = 0; i < _shardIds.length; i++) {
            require(!shards[_shardIds[i]].exists, "Shard exists");
            require(_contentHashes[i] != bytes32(0), "Invalid hash");
            
            shards[_shardIds[i]] = Shard({
                shardId: _shardIds[i],
                owner: msg.sender,
                contentHash: _contentHashes[i],
                createdAt: block.timestamp,
                storageSize: _storageSizes[i],
                exists: true,
                frozen: false,
                metadataURI: ""
            });
            
            ownerShards[msg.sender].push(_shardIds[i]);
            shardCount++;
        }
        
        emit BulkShardRegistered(msg.sender, _shardIds.length);
    }

    function updateShardContent(bytes32 _shardId, bytes32 _newContentHash) 
        external 
        onlyShardOwner(_shardId) 
        whenNotPaused 
    {
        require(_newContentHash != bytes32(0), "Invalid hash");
        shards[_shardId].contentHash = _newContentHash;
        emit ShardUpdated(_shardId, _newContentHash);
    }

    function updateShardMetadata(bytes32 _shardId, string calldata _metadataURI) 
        external 
        onlyShardOwner(_shardId) 
        whenNotPaused 
    {
        shards[_shardId].metadataURI = _metadataURI;
        emit MetadataUpdated(_shardId, _metadataURI);
    }

    function freezeShard(bytes32 _shardId) external onlyShardOwner(_shardId) whenNotPaused {
        shards[_shardId].frozen = true;
        emit ShardFrozen(_shardId);
    }

    function unfreezeShard(bytes32 _shardId) external onlyOwner {
        require(shards[_shardId].exists, "Shard not found");
        shards[_shardId].frozen = false;
        emit ShardUnfrozen(_shardId);
    }

    function createExpert(
        bytes32 _expertId,
        bytes32[] calldata _shardIds,
        string calldata _metadataURI
    ) external whenNotPaused nonReentrant {
        require(experts[_expertId].createdAt == 0, "Expert exists");
        require(_shardIds.length > 0, "No shards");
        require(_shardIds.length <= MAX_SHARDS_PER_EXPERT, "Too many shards");
        
        for (uint i = 0; i < _shardIds.length; i++) {
            require(shards[_shardIds[i]].exists, "Shard not found");
            require(shards[_shardIds[i]].owner == msg.sender, "Not shard owner");
            require(!shards[_shardIds[i]].frozen, "Shard frozen");
        }
        
        experts[_expertId] = Expert({
            expertId: _expertId,
            shardIds: _shardIds,
            owner: msg.sender,
            createdAt: block.timestamp,
            version: 1,
            active: true,
            metadataURI: _metadataURI
        });
        
        for (uint i = 0; i < _shardIds.length; i++) {
            expertContributors[_expertId].push(shards[_shardIds[i]].owner);
            emit ShardAddedToExpert(_expertId, _shardIds[i]);
        }
        
        ownerExperts[msg.sender].push(_expertId);
        expertCount++;
        
        emit ExpertCreated(_expertId, msg.sender, _shardIds.length);
    }

    function addShardToExpert(bytes32 _expertId, bytes32 _shardId) 
        external 
        onlyExpertOwner(_expertId) 
        whenNotPaused 
    {
        Expert storage expert = experts[_expertId];
        require(expert.active, "Expert inactive");
        require(expert.shardIds.length < MAX_SHARDS_PER_EXPERT, "Expert full");
        
        require(shards[_shardId].exists, "Shard not found");
        require(shards[_shardId].owner == msg.sender, "Not shard owner");
        
        expert.shardIds.push(_shardId);
        expert.version++;
        expertContributors[_expertId].push(shards[_shardId].owner);
        
        emit ShardAddedToExpert(_expertId, _shardId);
        emit ExpertUpdated(_expertId, expert.version);
    }

    function removeShardFromExpert(bytes32 _expertId, uint256 _index) 
        external 
        onlyExpertOwner(_expertId) 
        whenNotPaused 
    {
        Expert storage expert = experts[_expertId];
        require(_index < expert.shardIds.length, "Invalid index");
        require(expert.active, "Expert inactive");
        
        bytes32 removedShard = expert.shardIds[_index];
        
        expert.shardIds[_index] = expert.shardIds[expert.shardIds.length - 1];
        expert.shardIds.pop();
        expert.version++;
        
        emit ShardRemovedFromExpert(_expertId, removedShard);
        emit ExpertUpdated(_expertId, expert.version);
    }

    function activateExpert(bytes32 _expertId) external onlyExpertOwner(_expertId) whenNotPaused {
        require(experts[_expertId].createdAt > 0, "Expert not found");
        experts[_expertId].active = true;
        emit ExpertActivated(_expertId);
    }

    function deactivateExpert(bytes32 _expertId) external onlyExpertOwner(_expertId) whenNotPaused {
        require(experts[_expertId].createdAt > 0, "Expert not found");
        experts[_expertId].active = false;
        emit ExpertDeactivated(_expertId);
    }

    function getShard(bytes32 _shardId) external view returns (
        address owner, 
        bytes32 contentHash, 
        uint256 createdAt,
        uint256 storageSize,
        bool frozen,
        string memory metadataURI
    ) {
        Shard memory s = shards[_shardId];
        return (s.owner, s.contentHash, s.createdAt, s.storageSize, s.frozen, s.metadataURI);
    }

    function getExpert(bytes32 _expertId) external view returns (
        address owner, 
        bytes32[] memory shardIds, 
        uint256 createdAt,
        uint256 version,
        bool active,
        string memory metadataURI
    ) {
        Expert memory e = experts[_expertId];
        return (e.owner, e.shardIds, e.createdAt, e.version, e.active, e.metadataURI);
    }

    function getExpertShardCount(bytes32 _expertId) external view returns (uint256) {
        return experts[_expertId].expertId == bytes32(0) ? 0 : experts[_expertId].shardIds.length;
    }

    function getOwnerShards(address _owner) external view returns (bytes32[] memory) {
        return ownerShards[_owner];
    }

    function getOwnerExperts(address _owner) external view returns (bytes32[] memory) {
        return ownerExperts[_owner];
    }

    function getExpertContributors(bytes32 _expertId) external view returns (address[] memory) {
        return expertContributors[_expertId];
    }

    function getShardMetadata(bytes32 _shardId) external view returns (ShardMetadata memory) {
        return shardMetadata[_shardId];
    }

    function transferShardOwnership(bytes32 _shardId, address _to) 
        external 
        onlyShardOwner(_shardId) 
        whenNotPaused 
    {
        require(_to != address(0), "Invalid recipient");
        
        address from = shards[_shardId].owner;
        
        _removeShardFromOwner(from, _shardId);
        ownerShards[_to].push(_shardId);
        
        shards[_shardId].owner = _to;
        
        emit OwnershipTransferred(_shardId, from, _to);
    }

    function _removeShardFromOwner(address _owner, bytes32 _shardId) internal {
        bytes32[] storage ownerShardList = ownerShards[_owner];
        for (uint i = 0; i < ownerShardList.length; i++) {
            if (ownerShardList[i] == _shardId) {
                ownerShardList[i] = ownerShardList[ownerShardList.length - 1];
                ownerShardList.pop();
                break;
            }
        }
    }

    function verifyShardOwnership(bytes32 _shardId, address _owner) external view returns (bool) {
        return shards[_shardId].owner == _owner && shards[_shardId].exists;
    }

    function verifyExpertOwnership(bytes32 _expertId, address _owner) external view returns (bool) {
        return experts[_expertId].owner == _owner && experts[_expertId].createdAt > 0;
    }

    function isShardFrozen(bytes32 _shardId) external view returns (bool) {
        return shards[_shardId].frozen;
    }

    function isExpertActive(bytes32 _expertId) external view returns (bool) {
        return experts[_expertId].active;
    }

    function getStats() external view returns (uint256 _shards, uint256 _experts) {
        return (shardCount, expertCount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
