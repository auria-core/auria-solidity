// SPDX-License-Identifier: MIT
// File: Settlement.sol - This file is part of AURIA
// Copyright (c) 2026 AURIA Developers and Contributors
// Description:
//     Handles settlement and payment for inference usage across the network.
//     Tracks usage events and receipts from nodes, maintains a merkle root
//     of all usage for the settlement period, and calculates node rewards
//     based on their contributions to the AURIA decentralized LLM.
//
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Settlement is Ownable, Pausable, ReentrancyGuard {
    struct UsageReceipt {
        bytes32 receiptId;
        bytes32[] eventIds;
        address nodeIdentity;
        uint256 timestamp;
        bytes signature;
    }

    struct UsageEvent {
        bytes32 eventId;
        uint256 timestamp;
        address nodeIdentity;
        bytes32 modelId;
        bytes32 expertId;
        bytes32[] shardIds;
        bytes32 inputHash;
        bytes32 outputHash;
        uint256 tokenCount;
    }

    mapping(bytes32 => UsageReceipt) public receipts;
    mapping(bytes32 => bool) public submittedRoots;
    mapping(address => uint256) public nodeRewards;
    mapping(address => uint256) public nodeStakes;
    mapping(bytes32 => UsageEvent) public usageEvents;
    
    bytes32 public currentRoot;
    uint256 public settlementInterval;
    uint256 public lastSettlementTime;
    uint256 public totalRewardsDistributed;
    uint256 public rewardPool;
    
    uint256 public constant MIN_STAKE = 1 ether;
    uint256 public constant REWARD_SCALE = 1e18;
    
    event ReceiptSubmitted(bytes32 indexed receiptId, bytes32 root, uint256 tokenCount);
    event SettlementCompleted(bytes32 root, uint256 timestamp, uint256 rewardsDistributed);
    event RewardDistributed(address indexed node, uint256 amount);
    event StakeAdded(address indexed node, uint256 amount);
    event StakeRemoved(address indexed node, uint256 amount);
    event RewardPoolFunded(uint256 amount);
    event RootVerified(bytes32 indexed root, bool valid);

    modifier onlyStakedNode() {
        require(nodeStakes[msg.sender] >= MIN_STAKE, "Insufficient stake");
        _;
    }

    constructor(uint256 _interval) Ownable() {
        settlementInterval = _interval;
        lastSettlementTime = block.timestamp;
    }

    function submitReceipt(UsageReceipt calldata _receipt) external whenNotPaused onlyStakedNode nonReentrant {
        require(receipts[_receipt.receiptId].receiptId == 0, "Receipt exists");
        require(_receipt.eventIds.length > 0, "Empty receipt");
        
        for (uint i = 0; i < _receipt.eventIds.length; i++) {
            require(usageEvents[_receipt.eventIds[i]].eventId != 0, "Event not found");
        }
        
        receipts[_receipt.receiptId] = _receipt;
        
        bytes32 root = computeMerkleRoot(_receipt.eventIds);
        currentRoot = root;
        
        uint256 tokenCount = _calculateTokenCount(_receipt.eventIds);
        
        emit ReceiptSubmitted(_receipt.receiptId, root, tokenCount);
    }

    function recordUsage(UsageEvent calldata _event) external whenNotPaused onlyStakedNode {
        require(usageEvents[_event.eventId].eventId == 0, "Event exists");
        
        usageEvents[_event.eventId] = _event;
    }

    function _calculateTokenCount(bytes32[] memory _eventIds) internal view returns (uint256) {
        uint256 total = 0;
        for (uint i = 0; i < _eventIds.length; i++) {
            total += usageEvents[_eventIds[i]].tokenCount;
        }
        return total;
    }

    function computeMerkleRoot(bytes32[] memory _eventIds) public pure returns (bytes32) {
        if (_eventIds.length == 0) return bytes32(0);
        
        bytes32[] memory hashes = new bytes32[](_eventIds.length);
        for (uint i = 0; i < _eventIds.length; i++) {
            hashes[i] = _eventIds[i];
        }
        
        uint256 n = hashes.length;
        while (n > 1) {
            uint256 newN = (n + 1) / 2;
            for (uint i = 0; i < n / 2; i++) {
                hashes[i] = keccak256(abi.encodePacked(hashes[i * 2], hashes[i * 2 + 1]));
            }
            if (n % 2 == 1) {
                hashes[newN - 1] = hashes[n - 1];
            }
            n = newN;
        }
        
        return hashes[0];
    }

    function verifyMerkleProof(
        bytes32[] memory _proof,
        bytes32 _root,
        bytes32 _leaf,
        uint256 _index
    ) public pure returns (bool) {
        bytes32 computedHash = _leaf;
        
        for (uint i = 0; i < _proof.length; i++) {
            if ((_index / (2 ** i)) % 2 == 0) {
                computedHash = keccak256(abi.encodePacked(computedHash, _proof[i]));
            } else {
                computedHash = keccak256(abi.encodePacked(_proof[i], computedHash));
            }
        }
        
        return computedHash == _root;
    }

    function settle(bytes32 _root) external whenNotPaused onlyOwner {
        require(!submittedRoots[_root], "Already submitted");
        require(block.timestamp >= lastSettlementTime + settlementInterval, "Too early");
        
        submittedRoots[_root] = true;
        lastSettlementTime = block.timestamp;
        
        uint256 rewards = _distributeRewards();
        totalRewardsDistributed += rewards;
        
        emit SettlementCompleted(_root, block.timestamp, rewards);
    }

    function _distributeRewards() internal returns (uint256) {
        address[] memory nodes = _getActiveNodes();
        if (nodes.length == 0) return 0;
        
        uint256 totalStake = 0;
        for (uint i = 0; i < nodes.length; i++) {
            totalStake += nodeStakes[nodes[i]];
        }
        
        uint256 distributed = 0;
        for (uint i = 0; i < nodes.length; i++) {
            uint256 share = (nodeStakes[nodes[i]] * rewardPool) / totalStake;
            nodeRewards[nodes[i]] += share;
            distributed += share;
        }
        
        rewardPool = 0;
        return distributed;
    }

    function _getActiveNodes() internal view returns (address[] memory) {
        uint256 count = 0;
        for (uint i = 0; i < 1000; i++) {
            address node = address(uint160(i));
            if (nodeStakes[node] >= MIN_STAKE) {
                count++;
            }
        }
        
        address[] memory result = new address[](count);
        uint256 idx = 0;
        for (uint i = 0; i < 1000; i++) {
            address node = address(uint160(i));
            if (nodeStakes[node] >= MIN_STAKE) {
                result[idx] = node;
                idx++;
            }
        }
        
        return result;
    }

    function fundRewardPool() external payable whenNotPaused {
        require(msg.value > 0, "No funds");
        rewardPool += msg.value;
        emit RewardPoolFunded(msg.value);
    }

    function addStake() external payable whenNotPaused {
        require(msg.value > 0, "No stake");
        nodeStakes[msg.sender] += msg.value;
        emit StakeAdded(msg.sender, msg.value);
    }

    function removeStake(uint256 _amount) external whenNotPaused {
        require(nodeStakes[msg.sender] >= _amount, "Insufficient stake");
        require(nodeStakes[msg.sender] - _amount >= MIN_STAKE, "Below minimum");
        
        nodeStakes[msg.sender] -= _amount;
        payable(msg.sender).transfer(_amount);
        emit StakeRemoved(msg.sender, _amount);
    }

    function recordNodeUsage(address _node, uint256 _amount) external onlyOwner whenNotPaused {
        nodeRewards[_node] += _amount;
        emit RewardDistributed(_node, _amount);
    }

    function getReward(address _node) external view returns (uint256) {
        return nodeRewards[_node];
    }

    function getStake(address _node) external view returns (uint256) {
        return nodeStakes[_node];
    }

    function withdraw() external nonReentrant {
        uint256 reward = nodeRewards[msg.sender];
        require(reward > 0, "No reward");
        
        nodeRewards[msg.sender] = 0;
        payable(msg.sender).transfer(reward);
        emit RewardDistributed(msg.sender, reward);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function getSettlementStatus() external view returns (
        uint256 _interval,
        uint256 _lastSettlement,
        uint256 _nextSettlement,
        uint256 _poolBalance,
        uint256 _totalDistributed
    ) {
        return (
            settlementInterval,
            lastSettlementTime,
            lastSettlementTime + settlementInterval,
            rewardPool,
            totalRewardsDistributed
        );
    }
}
