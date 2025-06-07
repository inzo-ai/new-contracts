// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

contract PolicyLedger is Ownable {

    address public policyLifecycleManagerAddress;

    enum PolicyStatus {
        PendingApplication,
        Active,
        Expired,
        Cancelled,
        ClaimUnderReview,
        ClaimPaid,
        ClaimRejected
    }

    enum RiskTier {
        Standard,
        Preferred,
        HighRisk
    }

    struct Policy {
        uint256 policyId;
        address policyHolder;
        PolicyStatus currentStatus;
        RiskTier riskTier;
        uint256 premiumAmount;
        uint256 coverageAmount;
        uint256 startDate;
        uint256 endDate;
        string assetIdentifier;
        bytes32 policyDetailsHash;
        uint256 creationTimestamp;
        uint256 lastUpdateTimestamp;
    }

    struct CreatePolicyInput {
        address policyHolder;
        RiskTier riskTier;
        uint256 premiumAmount;
        uint256 coverageAmount;
        uint256 startDate;
        uint256 endDate;
        string assetIdentifier;
        bytes32 policyDetailsHash;
    }
    
    struct UpdatePolicyTermsInput {
        uint256 newPremiumAmount;
        uint256 newCoverageAmount;
        uint256 newEndDate;
        string newAssetIdentifier;
        bytes32 newPolicyDetailsHash;
    }

    mapping(uint256 => Policy) public policies;
    mapping(address => uint256[]) public userPolicies;
    
    uint256 private _nextPolicyId;
    uint256 public totalActivePolicies;

    event PolicyCreated(
        uint256 indexed policyId,
        address indexed policyHolder,
        uint256 coverageAmount,
        uint256 premiumAmount
    );
    event PolicyStatusUpdated(
        uint256 indexed policyId,
        PolicyStatus newStatus
    );
    event PolicyTermsUpdated(
        uint256 indexed policyId
    );

    constructor(address initialOwner) Ownable(initialOwner) {
        _nextPolicyId = 1;
    }

    modifier onlyPolicyLifecycleManager() {
        require(msg.sender == policyLifecycleManagerAddress, "PL:!PLM");
        _;
    }

    modifier policyExists(uint256 _policyId) {
        require(policies[_policyId].policyId != 0, "PL:!EXIST");
        _;
    }

    function setPolicyLifecycleManager(address _managerAddress) external onlyOwner {
        policyLifecycleManagerAddress = _managerAddress;
    }

    function createPolicy(
        CreatePolicyInput calldata _input
    ) external onlyPolicyLifecycleManager returns (uint256) {
        require(_input.policyHolder != address(0), "PL:HOLDER_ZERO");
        require(_input.premiumAmount > 0, "PL:PREMIUM_ZERO");
        require(_input.coverageAmount > 0, "PL:COVERAGE_ZERO");
        require(_input.endDate > _input.startDate, "PL:END_DATE_INVALID");

        uint256 policyId = _nextPolicyId;
        Policy storage newPolicy = policies[policyId];

        newPolicy.policyId = policyId;
        newPolicy.policyHolder = _input.policyHolder;
        newPolicy.currentStatus = PolicyStatus.PendingApplication;
        newPolicy.riskTier = _input.riskTier;
        newPolicy.premiumAmount = _input.premiumAmount;
        newPolicy.coverageAmount = _input.coverageAmount;
        newPolicy.startDate = _input.startDate;
        newPolicy.endDate = _input.endDate;
        newPolicy.assetIdentifier = _input.assetIdentifier;
        newPolicy.policyDetailsHash = _input.policyDetailsHash;
        newPolicy.creationTimestamp = block.timestamp;
        newPolicy.lastUpdateTimestamp = block.timestamp;

        userPolicies[_input.policyHolder].push(policyId);
        
        _nextPolicyId++;
        emit PolicyCreated(policyId, _input.policyHolder, _input.coverageAmount, _input.premiumAmount);
        return policyId;
    }
    
    function updatePolicyStatus(uint256 _policyId, PolicyStatus _newStatus) 
        external 
        onlyPolicyLifecycleManager
        policyExists(_policyId) 
    {
        Policy storage policyToUpdate = policies[_policyId];
        PolicyStatus oldStatus = policyToUpdate.currentStatus;

        policyToUpdate.currentStatus = _newStatus;
        policyToUpdate.lastUpdateTimestamp = block.timestamp;

        if (oldStatus != PolicyStatus.Active && _newStatus == PolicyStatus.Active) {
            totalActivePolicies++;
        } else if (oldStatus == PolicyStatus.Active && _newStatus != PolicyStatus.Active) {
            if (totalActivePolicies > 0) totalActivePolicies--;
        }
        emit PolicyStatusUpdated(_policyId, _newStatus);
    }

    function updatePolicyTerms(uint256 _policyId, UpdatePolicyTermsInput calldata _termsInput)
        external
        onlyPolicyLifecycleManager
        policyExists(_policyId)
    {
        Policy storage policyToUpdate = policies[_policyId];
        require(policyToUpdate.currentStatus == PolicyStatus.PendingApplication || policyToUpdate.currentStatus == PolicyStatus.Active, "PL:TERMS_UPDATE_INVALID_STATE");

        if (_termsInput.newPremiumAmount > 0) {
            policyToUpdate.premiumAmount = _termsInput.newPremiumAmount;
        }
        if (_termsInput.newCoverageAmount > 0) {
            policyToUpdate.coverageAmount = _termsInput.newCoverageAmount;
        }
        if (_termsInput.newEndDate > policyToUpdate.startDate) {
            policyToUpdate.endDate = _termsInput.newEndDate;
        }
        if (bytes(_termsInput.newAssetIdentifier).length > 0) {
            policyToUpdate.assetIdentifier = _termsInput.newAssetIdentifier;
        }
        if (_termsInput.newPolicyDetailsHash != bytes32(0)) {
            policyToUpdate.policyDetailsHash = _termsInput.newPolicyDetailsHash;
        }
        
        policyToUpdate.lastUpdateTimestamp = block.timestamp;
        emit PolicyTermsUpdated(_policyId);
    }

    function getPolicyEssentialDetails(uint256 _policyId) 
        external 
        view 
        policyExists(_policyId) 
        returns (
            uint256 policyId,
            address policyHolder,
            PolicyStatus currentStatus,
            uint256 coverageAmount
        ) 
    {
        return (
            policies[_policyId].policyId,
            policies[_policyId].policyHolder,
            policies[_policyId].currentStatus,
            policies[_policyId].coverageAmount
        );
    }

    function getPolicyAssetIdentifier(uint256 _policyId) 
        external 
        view 
        policyExists(_policyId) 
        returns (string memory) 
    {
        return policies[_policyId].assetIdentifier;
    }

    function getPolicyStatus(uint256 _policyId) external view policyExists(_policyId) returns (PolicyStatus) {
        return policies[_policyId].currentStatus;
    }
    
    function getPolicyFinancialTerms(uint256 _policyId) 
        external view policyExists(_policyId) 
        returns (uint256 premium, uint256 coverage, RiskTier riskTier) {
        return (
            policies[_policyId].premiumAmount, 
            policies[_policyId].coverageAmount,
            policies[_policyId].riskTier
        );
    }

    function getUserPolicyIds(address _user) external view returns (uint256[] memory) {
        return userPolicies[_user];
    }

    function getNextPolicyId() external view returns (uint256) {
        return _nextPolicyId;
    }
}