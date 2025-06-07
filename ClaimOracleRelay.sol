// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

contract ClaimOracleRelay is Ownable {

    address public oracleAddress;
    address public policyLifecycleManagerAddress;

    mapping(address => bool) public kycVerifiedUsers;
    
    struct ClaimDecision {
        uint256 policyId;
        uint256 claimId;
        bool isApproved;
        uint256 payoutAmount;
        address processedByOracle;
        uint256 timestamp;
    }
    
    mapping(bytes32 => ClaimDecision) public processedClaims; 

    event OracleAddressChanged(address indexed oldOracle, address indexed newOracle);
    event KycStatusUpdated(address indexed user, bool isVerified, address indexed oracle);
    event ClaimDecisionSubmitted(
        uint256 indexed policyId,
        uint256 claimId,
        bool isApproved,
        uint256 payoutAmount,
        address indexed oracle
    );
    event ClaimDecisionReverted(bytes32 indexed claimHash, address indexed oracle);


    constructor(address initialOwner, address _initialOracleAddress) Ownable(initialOwner) {
        require(_initialOracleAddress != address(0), "COR:ZERO_ORACLE_ADDR");
        oracleAddress = _initialOracleAddress;
    }

    modifier onlyOracle() {
        require(msg.sender == oracleAddress, "COR:NOT_ORACLE");
        _;
    }

    function setOracleAddress(address _newOracleAddress) external onlyOwner {
        require(_newOracleAddress != address(0), "COR:NEW_ZERO_ORACLE_ADDR");
        address oldOracle = oracleAddress;
        oracleAddress = _newOracleAddress;
        emit OracleAddressChanged(oldOracle, _newOracleAddress);
    }

    function setPolicyLifecycleManagerAddress(address _plmAddress) external onlyOwner {
        policyLifecycleManagerAddress = _plmAddress;
    }

    function updateKycStatus(address _userAddress, bool _isVerified) external onlyOracle {
        require(_userAddress != address(0), "COR:KYC_ZERO_USER");
        kycVerifiedUsers[_userAddress] = _isVerified;
        emit KycStatusUpdated(_userAddress, _isVerified, msg.sender);
    }

    function submitClaimDecision(
        uint256 _policyId,
        uint256 _claimId,
        bool _isApproved,
        uint256 _payoutAmountIfApproved
    ) external onlyOracle {
        require(_policyId != 0, "COR:ZERO_POLICY_ID");
        
        if (_isApproved) {
            require(_payoutAmountIfApproved > 0, "COR:APPROVED_ZERO_PAYOUT");
        } else {
            require(_payoutAmountIfApproved == 0, "COR:REJECTED_NONZERO_PAYOUT");
        }

        bytes32 claimHash = keccak256(abi.encodePacked(_policyId, _claimId));
        require(processedClaims[claimHash].timestamp == 0, "COR:CLAIM_ALREADY_PROCESSED");
        
        processedClaims[claimHash] = ClaimDecision({
            policyId: _policyId,
            claimId: _claimId,
            isApproved: _isApproved,
            payoutAmount: _payoutAmountIfApproved,
            processedByOracle: msg.sender,
            timestamp: block.timestamp
        });

        emit ClaimDecisionSubmitted(_policyId, _claimId, _isApproved, _payoutAmountIfApproved, msg.sender);
    }
    
    function revertClaimDecision(uint256 _policyId, uint256 _claimId) external onlyOracle {
        bytes32 claimHash = keccak256(abi.encodePacked(_policyId, _claimId));
        ClaimDecision storage decisionToRevert = processedClaims[claimHash];
        
        require(decisionToRevert.timestamp != 0, "COR:CLAIM_NOT_PROCESSED_YET");
        require(decisionToRevert.processedByOracle == msg.sender, "COR:REVERT_UNAUTH_ORACLE"); 

        delete processedClaims[claimHash]; 
        
        emit ClaimDecisionReverted(claimHash, msg.sender);
    }


    function isKycVerified(address _userAddress) external view returns (bool) {
        return kycVerifiedUsers[_userAddress];
    }

    function getClaimDecision(uint256 _policyId, uint256 _claimId) external view returns (ClaimDecision memory) {
        bytes32 claimHash = keccak256(abi.encodePacked(_policyId, _claimId));
        return processedClaims[claimHash];
    }

    function hasClaimBeenProcessed(uint256 _policyId, uint256 _claimId) external view returns (bool) {
        bytes32 claimHash = keccak256(abi.encodePacked(_policyId, _claimId));
        return processedClaims[claimHash].timestamp != 0;
    }
}