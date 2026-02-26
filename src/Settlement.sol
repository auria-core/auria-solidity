// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Settlement {
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
    }

    mapping(bytes32 => UsageReceipt) public receipts;
    mapping(bytes32 => bool) public submittedRoots;
    mapping(address => uint256) public nodeRewards;
    
    bytes32 public currentRoot;
    uint256 public settlementInterval;
    uint256 public lastSettlementTime;

    event ReceiptSubmitted(bytes32 indexed receiptId, bytes32 root);
    event SettlementCompleted(bytes32 root, uint256 timestamp);
    event RewardDistributed(address indexed node, uint256 amount);

    constructor(uint256 _interval) {
        settlementInterval = _interval;
        lastSettlementTime = block.timestamp;
    }

    function submitReceipt(UsageReceipt calldata _receipt) external {
        require(receipts[_receipt.receiptId].receiptId == 0, "Receipt exists");
        
        receipts[_receipt.receiptId] = _receipt;
        
        bytes32 root = computeMerkleRoot(_receipt.eventIds);
        currentRoot = root;
        
        emit ReceiptSubmitted(_receipt.receiptId, root);
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

    function settle(bytes32 _root) external {
        require(!submittedRoots[_root], "Already submitted");
        require(block.timestamp >= lastSettlementTime + settlementInterval, "Too early");
        
        submittedRoots[_root] = true;
        lastSettlementTime = block.timestamp;
        
        emit SettlementCompleted(_root, block.timestamp);
    }

    function recordUsage(address _node, uint256 _amount) external {
        nodeRewards[_node] += _amount;
        emit RewardDistributed(_node, _amount);
    }

    function getReward(address _node) external view returns (uint256) {
        return nodeRewards[_node];
    }

    function withdraw() external {
        uint256 reward = nodeRewards[msg.sender];
        require(reward > 0, "No reward");
        
        nodeRewards[msg.sender] = 0;
        payable(msg.sender).transfer(reward);
    }
}
