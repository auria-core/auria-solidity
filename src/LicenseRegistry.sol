// SPDX-License-Identifier: MIT
// File: LicenseRegistry.sol - This file is part of AURIA
// Copyright (c) 2026 AURIA Developers and Contributors
// Description:
//     Manages licensing of shards and expert models on the blockchain.
//     Issues, tracks, and revokes licenses for node operators to serve
//     specific shards or experts. Maintains a registry of trusted issuers
//     who can grant and revoke licenses for model access.
//
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract LicenseRegistry is Ownable, Pausable, ReentrancyGuard {
    struct License {
        bytes32 licenseId;
        bytes32 shardId;
        address nodePublicKey;
        uint256 issuedAt;
        uint256 expiresAt;
        uint256 maxTokens;
        uint256 tokensUsed;
        address issuer;
        bytes signature;
        bool revoked;
        LicenseType licenseType;
    }

    enum LicenseType {
        Subscription,
        PayPerUse,
        Enterprise,
        Community
    }

    mapping(bytes32 => License) public licenses;
    mapping(bytes32 => bool) public revokedLicenses;
    mapping(address => bool) public trustedIssuers;
    mapping(address => bytes32[]) public nodeLicenses;
    mapping(bytes32 => bytes32[]) public shardLicenses;
    mapping(address => uint256) public issuerCounts;
    
    uint256 public constant MAX_LICENSE_DURATION = 365 days;
    uint256 public defaultMaxTokens = 1_000_000;
    
    event LicenseIssued(bytes32 indexed licenseId, bytes32 indexed shardId, address indexed node, uint256 expiresAt);
    event LicenseRevoked(bytes32 indexed licenseId);
    event LicenseRenewed(bytes32 indexed licenseId, uint256 newExpiry);
    event LicenseTransferred(bytes32 indexed licenseId, address from, address to);
    event IssuerAdded(address indexed issuer);
    event IssuerRemoved(address indexed issuer);
    event DefaultMaxTokensUpdated(uint256 newMax);
    event LicenseUsed(bytes32 indexed licenseId, uint256 tokens, uint256 remaining);

    modifier onlyTrustedIssuer() {
        require(trustedIssuers[msg.sender], "Only trusted issuers");
        _;
    }

    constructor() Ownable() {}

    function addTrustedIssuer(address issuer) external onlyOwner whenNotPaused {
        require(issuer != address(0), "Invalid issuer");
        trustedIssuers[issuer] = true;
        issuerCounts[issuer]++;
        emit IssuerAdded(issuer);
    }

    function removeTrustedIssuer(address issuer) external onlyOwner {
        trustedIssuers[issuer] = false;
        emit IssuerRemoved(issuer);
    }

    function issueLicense(
        bytes32 _shardId,
        address _nodePublicKey,
        uint256 _expiresAt,
        uint256 _maxTokens,
        LicenseType _licenseType,
        bytes calldata _signature
    ) external onlyTrustedIssuer whenNotPaused nonReentrant returns (bytes32) {
        require(_nodePublicKey != address(0), "Invalid node");
        require(_expiresAt > block.timestamp, "Invalid expiry");
        require(_expiresAt <= block.timestamp + MAX_LICENSE_DURATION, "Expiry too far");
        
        uint256 issuedAt = block.timestamp;
        bytes32 licenseId = keccak256(
            abi.encodePacked(_shardId, _nodePublicKey, issuedAt, _maxTokens)
        );

        require(licenses[licenseId].licenseId == 0, "License exists");

        licenses[licenseId] = License({
            licenseId: licenseId,
            shardId: _shardId,
            nodePublicKey: _nodePublicKey,
            issuedAt: issuedAt,
            expiresAt: _expiresAt,
            maxTokens: _maxTokens,
            tokensUsed: 0,
            issuer: msg.sender,
            signature: _signature,
            revoked: false,
            licenseType: _licenseType
        });

        nodeLicenses[_nodePublicKey].push(licenseId);
        shardLicenses[_shardId].push(licenseId);
        
        emit LicenseIssued(licenseId, _shardId, _nodePublicKey, _expiresAt);
        return licenseId;
    }

    function issueSubscriptionLicense(
        bytes32 _shardId,
        address _nodePublicKey,
        uint256 _durationDays,
        bytes calldata _signature
    ) external onlyTrustedIssuer whenNotPaused returns (bytes32) {
        uint256 expiresAt = block.timestamp + (_durationDays * 1 days);
        return issueLicense(
            _shardId,
            _nodePublicKey,
            expiresAt,
            defaultMaxTokens,
            LicenseType.Subscription,
            _signature
        );
    }

    function verifyLicense(bytes32 _licenseId) public view whenNotPaused returns (bool) {
        License memory license = licenses[_licenseId];
        
        if (license.licenseId == 0) return false;
        if (license.revoked) return false;
        if (block.timestamp >= license.expiresAt) return false;
        if (license.tokensUsed >= license.maxTokens) return false;
        
        return true;
    }

    function verifyLicenseForShard(bytes32 _shardId, address _node) external view returns (bool) {
        bytes32[] memory shardLicenseIds = shardLicenses[_shardId];
        
        for (uint i = 0; i < shardLicenseIds.length; i++) {
            License memory license = licenses[shardLicenseIds[i]];
            if (license.nodePublicKey == _node && verifyLicense(license.licenseId)) {
                return true;
            }
        }
        return false;
    }

    function useLicense(bytes32 _licenseId, uint256 _tokens) external whenNotPaused nonReentrant {
        License storage license = licenses[_licenseId];
        
        require(license.licenseId != 0, "License not found");
        require(!license.revoked, "License revoked");
        require(block.timestamp < license.expiresAt, "License expired");
        require(license.tokensUsed + _tokens <= license.maxTokens, "Insufficient tokens");
        
        license.tokensUsed += _tokens;
        
        emit LicenseUsed(_licenseId, _tokens, license.maxTokens - license.tokensUsed);
    }

    function getRemainingTokens(bytes32 _licenseId) external view returns (uint256) {
        License memory license = licenses[_licenseId];
        if (license.licenseId == 0) return 0;
        return license.maxTokens - license.tokensUsed;
    }

    function revokeLicense(bytes32 _licenseId) external whenNotPaused {
        License storage license = licenses[_licenseId];
        require(license.licenseId != 0, "License not found");
        require(license.issuer == msg.sender || msg.sender == owner(), "Not authorized");
        
        license.revoked = true;
        revokedLicenses[_licenseId] = true;
        
        emit LicenseRevoked(_licenseId);
    }

    function renewLicense(bytes32 _licenseId, uint256 _newExpiry) external whenNotPaused nonReentrant {
        License storage license = licenses[_licenseId];
        require(license.licenseId != 0, "License not found");
        require(license.nodePublicKey == msg.sender || license.issuer == msg.sender, "Not authorized");
        require(_newExpiry > license.expiresAt, "Must extend");
        require(_newExpiry <= block.timestamp + MAX_LICENSE_DURATION, "Expiry too far");
        
        license.expiresAt = _newExpiry;
        license.revoked = false;
        
        emit LicenseRenewed(_licenseId, _newExpiry);
    }

    function transferLicense(bytes32 _licenseId, address _to) external whenNotPaused {
        License storage license = licenses[_licenseId];
        require(license.licenseId != 0, "License not found");
        require(license.nodePublicKey == msg.sender, "Not owner");
        require(_to != address(0), "Invalid recipient");
        
        address from = license.nodePublicKey;
        license.nodePublicKey = _to;
        
        nodeLicenses[_to].push(_licenseId);
        
        emit LicenseTransferred(_licenseId, from, _to);
    }

    function getLicense(bytes32 _licenseId) external view returns (
        bytes32 licenseId,
        bytes32 shardId,
        address nodePublicKey,
        uint256 issuedAt,
        uint256 expiresAt,
        uint256 maxTokens,
        uint256 tokensUsed,
        bool revoked,
        LicenseType licenseType
    ) {
        License memory l = licenses[_licenseId];
        return (
            l.licenseId,
            l.shardId,
            l.nodePublicKey,
            l.issuedAt,
            l.expiresAt,
            l.maxTokens,
            l.tokensUsed,
            l.revoked,
            l.licenseType
        );
    }

    function getNodeLicenseCount(address _node) external view returns (uint256) {
        return nodeLicenses[_node].length;
    }

    function getNodeLicenses(address _node) external view returns (bytes32[] memory) {
        return nodeLicenses[_node];
    }

    function getShardLicenseCount(bytes32 _shardId) external view returns (uint256) {
        return shardLicenses[_shardId].length;
    }

    function setDefaultMaxTokens(uint256 _maxTokens) external onlyOwner {
        defaultMaxTokens = _maxTokens;
        emit DefaultMaxTokensUpdated(_maxTokens);
    }

    function batchRevoke(bytes32[] calldata _licenseIds) external onlyOwner whenNotPaused {
        for (uint i = 0; i < _licenseIds.length; i++) {
            License storage license = licenses[_licenseIds[i]];
            if (license.licenseId != 0 && !license.revoked) {
                license.revoked = true;
                revokedLicenses[_licenseIds[i]] = true;
                emit LicenseRevoked(_licenseIds[i]);
            }
        }
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
