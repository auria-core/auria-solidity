// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract LicenseRegistry {
    struct License {
        bytes32 licenseId;
        bytes32 shardId;
        address nodePublicKey;
        uint256 issuedAt;
        uint256 expiresAt;
        address issuer;
        bytes signature;
        bool revoked;
    }

    mapping(bytes32 => License) public licenses;
    mapping(bytes32 => bool) public revokedLicenses;
    mapping(address => bool) public trustedIssuers;

    event LicenseIssued(bytes32 indexed licenseId, bytes32 indexed shardId, address indexed node);
    event LicenseRevoked(bytes32 indexed licenseId);
    event IssuerAdded(address indexed issuer);
    event IssuerRemoved(address indexed issuer);

    modifier onlyTrustedIssuer() {
        require(trustedIssuers[msg.sender], "Only trusted issuers");
        _;
    }

    function addTrustedIssuer(address issuer) external {
        trustedIssuers[issuer] = true;
        emit IssuerAdded(issuer);
    }

    function removeTrustedIssuer(address issuer) external {
        trustedIssuers[issuer] = false;
        emit IssuerRemoved(issuer);
    }

    function issueLicense(
        bytes32 _shardId,
        address _nodePublicKey,
        uint256 _expiresAt,
        bytes calldata _signature
    ) external onlyTrustedIssuer returns (bytes32) {
        uint256 issuedAt = block.timestamp;
        bytes32 licenseId = keccak256(
            abi.encodePacked(_shardId, _nodePublicKey, issuedAt)
        );

        licenses[licenseId] = License({
            licenseId: licenseId,
            shardId: _shardId,
            nodePublicKey: _nodePublicKey,
            issuedAt: issuedAt,
            expiresAt: _expiresAt,
            issuer: msg.sender,
            signature: _signature,
            revoked: false
        });

        emit LicenseIssued(licenseId, _shardId, _nodePublicKey);
        return licenseId;
    }

    function verifyLicense(bytes32 _licenseId) external view returns (bool) {
        License memory license = licenses[_licenseId];
        
        if (license.licenseId == 0) return false;
        if (license.revoked) return false;
        if (block.timestamp >= license.expiresAt) return false;
        
        return true;
    }

    function revokeLicense(bytes32 _licenseId) external {
        require(licenses[_licenseId].issuer == msg.sender, "Not issuer");
        licenses[_licenseId].revoked = true;
        revokedLicenses[_licenseId] = true;
        emit LicenseRevoked(_licenseId);
    }

    function getLicense(bytes32 _licenseId) external view returns (
        bytes32, bytes32, address, uint256, uint256, bool
    ) {
        License memory l = licenses[_licenseId];
        return (l.licenseId, l.shardId, l.nodePublicKey, l.issuedAt, l.expiresAt, l.revoked);
    }
}
