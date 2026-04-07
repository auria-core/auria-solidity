// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/LicenseRegistry.sol";

contract LicenseRegistryTest is Test {
    LicenseRegistry public registry;
    
    address public owner = address(0x1);
    address public issuer = address(0x2);
    address public node = address(0x3);
    
    bytes32 public testShardId = keccak256("test-shard");
    bytes32 public testLicenseId;
    bytes public testSignature = "0xabcd";
    
    function setUp() public {
        vm.prank(owner);
        registry = new LicenseRegistry();
        
        vm.prank(owner);
        registry.addTrustedIssuer(issuer);
        
        testLicenseId = keccak256(abi.encodePacked(testShardId, node, uint256(1)));
    }
    
    function testIssueLicense() public {
        vm.prank(issuer);
        bytes32 licenseId = registry.issueLicense(
            testShardId,
            node,
            block.timestamp + 30 days,
            1000000,
            LicenseRegistry.LicenseType.Subscription,
            testSignature
        );
        
        assertTrue(licenseId != bytes32(0));
        assertTrue(registry.verifyLicense(licenseId));
    }
    
    function testVerifyLicense() public {
        vm.prank(issuer);
        registry.issueLicense(
            testShardId,
            node,
            block.timestamp + 30 days,
            1000000,
            LicenseRegistry.LicenseType.Subscription,
            testSignature
        );
        
        assertTrue(registry.verifyLicense(testLicenseId));
    }
    
    function testVerifyExpiredLicense() public {
        vm.prank(issuer);
        registry.issueLicense(
            testShardId,
            node,
            block.timestamp + 1 days,
            1000000,
            LicenseRegistry.LicenseType.Subscription,
            testSignature
        );
        
        vm.warp(block.timestamp + 2 days);
        
        assertFalse(registry.verifyLicense(testLicenseId));
    }
    
    function testUseLicense() public {
        vm.prank(issuer);
        registry.issueLicense(
            testShardId,
            node,
            block.timestamp + 30 days,
            1000000,
            LicenseRegistry.LicenseType.Subscription,
            testSignature
        );
        
        vm.prank(node);
        registry.useLicense(testLicenseId, 500);
        
        uint256 remaining = registry.getRemainingTokens(testLicenseId);
        
        assertEq(remaining, 999500);
    }
    
    function testFailUseExhaustedLicense() public {
        vm.prank(issuer);
        registry.issueLicense(
            testShardId,
            node,
            block.timestamp + 30 days,
            100,
            LicenseRegistry.LicenseType.Subscription,
            testSignature
        );
        
        vm.prank(node);
        registry.useLicense(testLicenseId, 100);
        
        vm.prank(node);
        registry.useLicense(testLicenseId, 1);
    }
    
    function testRevokeLicense() public {
        vm.prank(issuer);
        registry.issueLicense(
            testShardId,
            node,
            block.timestamp + 30 days,
            1000000,
            LicenseRegistry.LicenseType.Subscription,
            testSignature
        );
        
        vm.prank(issuer);
        registry.revokeLicense(testLicenseId);
        
        assertFalse(registry.verifyLicense(testLicenseId));
    }
    
    function testRenewLicense() public {
        uint256 initialExpiry = block.timestamp + 30 days;
        
        vm.prank(issuer);
        registry.issueLicense(
            testShardId,
            node,
            initialExpiry,
            1000000,
            LicenseRegistry.LicenseType.Subscription,
            testSignature
        );
        
        uint256 newExpiry = block.timestamp + 60 days;
        
        vm.prank(node);
        registry.renewLicense(testLicenseId, newExpiry);
        
        (,,,,,,, uint256 expiresAt,) = registry.getLicense(testLicenseId);
        
        assertEq(expiresAt, newExpiry);
    }
    
    function testTransferLicense() public {
        address newNode = address(0x4);
        
        vm.prank(issuer);
        registry.issueLicense(
            testShardId,
            node,
            block.timestamp + 30 days,
            1000000,
            LicenseRegistry.LicenseType.Subscription,
            testSignature
        );
        
        vm.prank(node);
        registry.transferLicense(testLicenseId, newNode);
        
        assertTrue(registry.verifyLicenseForShard(testShardId, newNode));
    }
    
    function testVerifyLicenseForShard() public {
        vm.prank(issuer);
        registry.issueLicense(
            testShardId,
            node,
            block.timestamp + 30 days,
            1000000,
            LicenseRegistry.LicenseType.Subscription,
            testSignature
        );
        
        assertTrue(registry.verifyLicenseForShard(testShardId, node));
        assertFalse(registry.verifyLicenseForShard(testShardId, address(0x5)));
    }
    
    function testGetNodeLicenseCount() public {
        vm.prank(issuer);
        registry.issueLicense(
            testShardId,
            node,
            block.timestamp + 30 days,
            1000000,
            LicenseRegistry.LicenseType.Subscription,
            testSignature
        );
        
        bytes32 otherShard = keccak256("other-shard");
        
        vm.prank(issuer);
        registry.issueLicense(
            otherShard,
            node,
            block.timestamp + 30 days,
            1000000,
            LicenseRegistry.LicenseType.PayPerUse,
            testSignature
        );
        
        assertEq(registry.getNodeLicenseCount(node), 2);
    }
    
    function testSetDefaultMaxTokens() public {
        vm.prank(owner);
        registry.setDefaultMaxTokens(5000000);
        
        assertEq(registry.defaultMaxTokens(), 5000000);
    }
    
    function testRemoveTrustedIssuer() public {
        vm.prank(owner);
        registry.removeTrustedIssuer(issuer);
        
        vm.prank(issuer);
        vm.expectRevert("Only trusted issuers");
        registry.issueLicense(
            testShardId,
            node,
            block.timestamp + 30 days,
            1000000,
            LicenseRegistry.LicenseType.Subscription,
            testSignature
        );
    }
    
    function testLicenseTokenLimit() public {
        vm.prank(issuer);
        registry.issueLicense(
            testShardId,
            node,
            block.timestamp + 30 days,
            100,
            LicenseRegistry.LicenseType.PayPerUse,
            testSignature
        );
        
        vm.prank(node);
        vm.expectRevert("Token limit exceeded");
        registry.useLicense(testLicenseId, 101);
    }
    
    function testLicenseTransfer() public {
        address newNode = address(0x4);
        
        vm.prank(issuer);
        registry.issueLicense(
            testShardId,
            node,
            block.timestamp + 30 days,
            1000000,
            LicenseRegistry.LicenseType.Subscription,
            testSignature
        );
        
        vm.prank(node);
        registry.transferLicense(testLicenseId, newNode);
        
        assertFalse(registry.verifyLicense(testLicenseId));
    }
    
    function testLicenseRenewal() public {
        vm.prank(issuer);
        registry.issueLicense(
            testShardId,
            node,
            block.timestamp + 30 days,
            1000000,
            LicenseRegistry.LicenseType.Subscription,
            testSignature
        );
        
        vm.warp(block.timestamp + 25 days);
        
        vm.prank(issuer);
        registry.renewLicense(testLicenseId, 60 days, 2000000);
        
        assertTrue(registry.verifyLicense(testLicenseId));
    }
    
    function testMultipleIssuers() public {
        address issuer2 = address(0x5);
        
        vm.prank(owner);
        registry.addTrustedIssuer(issuer2);
        
        vm.prank(issuer);
        bytes32 license1 = registry.issueLicense(
            testShardId,
            node,
            block.timestamp + 30 days,
            1000000,
            LicenseRegistry.LicenseType.Subscription,
            testSignature
        );
        
        vm.prank(issuer2);
        bytes32 license2 = registry.issueLicense(
            testShardId,
            node,
            block.timestamp + 30 days,
            1000000,
            LicenseRegistry.LicenseType.Subscription,
            testSignature
        );
        
        assertTrue(license1 != license2);
    }
    
    function testRevokeLicense() public {
        vm.prank(issuer);
        registry.issueLicense(
            testShardId,
            node,
            block.timestamp + 30 days,
            1000000,
            LicenseRegistry.LicenseType.Subscription,
            testSignature
        );
        
        vm.prank(issuer);
        registry.revokeLicense(testLicenseId);
        
        assertFalse(registry.verifyLicense(testLicenseId));
    }
}
