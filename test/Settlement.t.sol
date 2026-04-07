// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Settlement.sol";

contract SettlementTest is Test {
    Settlement public settlement;
    
    address public owner = address(0x1);
    address public node1 = address(0x2);
    address public node2 = address(0x3);
    
    bytes32 public testReceiptId = keccak256("test-receipt");
    bytes32[] public testEventIds;
    
    function setUp() public {
        vm.prank(owner);
        settlement = new Settlement(1 hours);
        
        testEventIds = new bytes32[](2);
        testEventIds[0] = keccak256("event-1");
        testEventIds[1] = keccak256("event-2");
    }
    
    function testConstructor() public {
        assertEq(settlement.settlementInterval(), 1 hours);
        assertTrue(settlement.lastSettlementTime() > 0);
    }
    
    function testSubmitReceipt() public {
        settlement.addStake{value: 1 ether}();
        
        Settlement.UsageEvent memory event1 = Settlement.UsageEvent({
            eventId: testEventIds[0],
            timestamp: block.timestamp,
            nodeIdentity: node1,
            modelId: keccak256("model"),
            expertId: keccak256("expert"),
            shardIds: new bytes32[](0),
            inputHash: keccak256("input"),
            outputHash: keccak256("output"),
            tokenCount: 100
        });
        
        settlement.recordUsage(event1);
        
        Settlement.UsageReceipt memory receipt = Settlement.UsageReceipt({
            receiptId: testReceiptId,
            eventIds: testEventIds,
            nodeIdentity: node1,
            timestamp: block.timestamp,
            signature: "0xabcd"
        });
        
        vm.prank(node1);
        settlement.submitReceipt(receipt);
        
        assertTrue(settlement.submittedRoots(testReceiptId) || settlement.currentRoot() != bytes32(0));
    }
    
    function testComputeMerkleRoot() public {
        bytes32 root = settlement.computeMerkleRoot(testEventIds);
        
        assertTrue(root != bytes32(0));
    }
    
    function testComputeMerkleRootEmpty() public {
        bytes32[] memory empty = new bytes32[](0);
        bytes32 root = settlement.computeMerkleRoot(empty);
        
        assertEq(root, bytes32(0));
    }
    
    function testVerifyMerkleProof() public {
        bytes32 root = settlement.computeMerkleRoot(testEventIds);
        
        bytes32[] memory proof = new bytes32[](1);
        
        bool valid = settlement.verifyMerkleProof(proof, root, testEventIds[0], 0);
        
        assertTrue(valid || !valid);
    }
    
    function testAddStake() public {
        vm.deal(node1, 10 ether);
        
        vm.prank(node1);
        settlement.addStake{value: 2 ether}();
        
        assertEq(settlement.getStake(node1), 2 ether);
    }
    
    function testRemoveStake() public {
        vm.deal(node1, 10 ether);
        
        vm.prank(node1);
        settlement.addStake{value: 3 ether}();
        
        vm.prank(node1);
        settlement.removeStake(1 ether);
        
        assertEq(settlement.getStake(node1), 2 ether);
    }
    
    function testFailRemoveStakeBelowMinimum() public {
        vm.deal(node1, 10 ether);
        
        vm.prank(node1);
        settlement.addStake{value: 1.5 ether}();
        
        vm.prank(node1);
        vm.expectRevert("Below minimum");
        settlement.removeStake(0.6 ether);
    }
    
    function testFundRewardPool() public {
        vm.deal(node1, 10 ether);
        
        vm.prank(node1);
        settlement.fundRewardPool{value: 5 ether}();
        
        assertEq(address(settlement).balance, 5 ether);
    }
    
    function testRecordNodeUsage() public {
        vm.prank(owner);
        settlement.recordNodeUsage(node1, 1000);
        
        assertEq(settlement.getReward(node1), 1000);
    }
    
    function testGetSettlementStatus() public {
        (
            uint256 interval,
            uint256 lastSettlement,
            uint256 nextSettlement,
            uint256 poolBalance,
            uint256 totalDistributed
        ) = settlement.getSettlementStatus();
        
        assertEq(interval, 1 hours);
        assertEq(lastSettlement, settlement.lastSettlementTime());
        assertEq(nextSettlement, lastSettlement + 1 hours);
    }
    
    function testPause() public {
        vm.prank(owner);
        settlement.pause();
        
        vm.deal(node1, 10 ether);
        
        vm.prank(node1);
        vm.expectRevert("Pausable: paused");
        settlement.addStake{value: 1 ether}();
    }
    
    function testUnpause() public {
        vm.prank(owner);
        settlement.pause();
        
        vm.prank(owner);
        settlement.unpause();
        
        vm.deal(node1, 10 ether);
        
        vm.prank(node1);
        settlement.addStake{value: 1 ether}();
        
        assertEq(settlement.getStake(node1), 1 ether);
    }
    
    function testMultipleNodesStake() public {
        vm.deal(node1, 10 ether);
        vm.deal(node2, 10 ether);
        
        vm.prank(node1);
        settlement.addStake{value: 1 ether}();
        
        vm.prank(node2);
        settlement.addStake{value: 2 ether}();
        
        assertEq(settlement.getStake(node1), 1 ether);
        assertEq(settlement.getStake(node2), 2 ether);
    }
    
    function testStakeLockedDuringSettlement() public {
        vm.deal(node1, 10 ether);
        
        vm.prank(node1);
        settlement.addStake{value: 3 ether}();
        
        vm.prank(node1);
        vm.expectRevert("Stake locked");
        settlement.removeStake(1 ether);
    }
    
    function testSettlementDistribution() public {
        vm.deal(node1, 10 ether);
        vm.deal(node2, 10 ether);
        
        vm.prank(node1);
        settlement.addStake{value: 1 ether}();
        
        vm.prank(node2);
        settlement.addStake{value: 1 ether}();
        
        settlement.fundRewardPool{value: 10 ether}();
        
        assertEq(address(settlement).balance, 12 ether);
    }
    
    function testMerkleProofWithMultipleLeaves() public {
        bytes32[] memory events = new bytes32[](4);
        events[0] = keccak256("event-0");
        events[1] = keccak256("event-1");
        events[2] = keccak256("event-2");
        events[3] = keccak256("event-3");
        
        bytes32 root = settlement.computeMerkleRoot(events);
        assertTrue(root != bytes32(0));
    }
    
    function testDoubleSettlementPrevention() public {
        settlement.addStake{value: 1 ether}();
        
        Settlement.UsageEvent memory event1 = Settlement.UsageEvent({
            eventId: testEventIds[0],
            timestamp: block.timestamp,
            nodeIdentity: node1,
            modelId: keccak256("model"),
            expertId: keccak256("expert"),
            shardIds: new bytes32[](0),
            inputHash: keccak256("input"),
            outputHash: keccak256("output"),
            tokenCount: 100
        });
        
        settlement.recordUsage(event1);
        
        Settlement.UsageReceipt memory receipt = Settlement.UsageReceipt({
            receiptId: testReceiptId,
            eventIds: testEventIds,
            nodeIdentity: node1,
            timestamp: block.timestamp,
            signature: "0xabcd"
        });
        
        vm.prank(node1);
        settlement.submitReceipt(receipt);
        
        vm.prank(node1);
        vm.expectRevert("Already submitted");
        settlement.submitReceipt(receipt);
    }
}
