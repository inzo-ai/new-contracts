// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract InsuranceFundManager is Ownable, ReentrancyGuard {

    IERC20 public immutable inzoUSDToken;
    address public policyLifecycleManagerAddress;

    uint256 public totalPremiumsCollected;
    uint256 public totalClaimsPaidOut;
    
    mapping(uint256 => uint256) public policyPremiumsPaid;

    event FundsDepositedForPremium(
        uint256 indexed policyId,
        address indexed payer,
        uint256 amount
    );
    event ClaimPayoutProcessed(
        uint256 indexed policyId,
        address indexed beneficiary,
        uint256 amount
    );
    event EmergencyWithdrawal(
        address indexed token,
        address indexed to,
        uint256 amount
    );
    event PolicyLifecycleManagerAddressChanged(
        address indexed oldPlm,
        address indexed newPlm
    );

    constructor(
        address initialOwner,
        address _inzoUSDTokenAddress,
        address _initialPolicyLifecycleManagerAddress
    ) Ownable(initialOwner) {
        require(_inzoUSDTokenAddress != address(0), "IFM:ZERO_TOKEN_ADDR");
        require(_initialPolicyLifecycleManagerAddress != address(0), "IFM:ZERO_PLM_ADDR");
        
        inzoUSDToken = IERC20(_inzoUSDTokenAddress);
        policyLifecycleManagerAddress = _initialPolicyLifecycleManagerAddress;
    }

    modifier onlyPolicyLifecycleManager() {
        require(msg.sender == policyLifecycleManagerAddress, "IFM:NOT_PLM");
        _;
    }

    function setPolicyLifecycleManager(address _newPlmAddress) external onlyOwner {
        require(_newPlmAddress != address(0), "IFM:NEW_ZERO_PLM_ADDR");
        address oldPlm = policyLifecycleManagerAddress;
        policyLifecycleManagerAddress = _newPlmAddress;
        emit PolicyLifecycleManagerAddressChanged(oldPlm, _newPlmAddress);
    }

    function collectPremium(
        uint256 _policyId,
        address _payer,
        uint256 _premiumAmount
    ) external onlyPolicyLifecycleManager nonReentrant returns (bool) {
        require(_policyId != 0, "IFM:ZERO_POLICY_ID");
        require(_payer != address(0), "IFM:ZERO_PAYER_ADDR");
        require(_premiumAmount > 0, "IFM:ZERO_PREMIUM_AMOUNT");

        uint256 initialBalance = inzoUSDToken.balanceOf(address(this));
        
        bool success = inzoUSDToken.transferFrom(_payer, address(this), _premiumAmount);
        require(success, "IFM:PREMIUM_TRANSFER_FAILED");

        uint256 finalBalance = inzoUSDToken.balanceOf(address(this));
        require(finalBalance == initialBalance + _premiumAmount, "IFM:PREMIUM_AMOUNT_MISMATCH");

        totalPremiumsCollected += _premiumAmount;
        policyPremiumsPaid[_policyId] += _premiumAmount;

        emit FundsDepositedForPremium(_policyId, _payer, _premiumAmount);
        return true;
    }

    function processClaimPayout(
        uint256 _policyId,
        address _beneficiary,
        uint256 _payoutAmount
    ) external onlyPolicyLifecycleManager nonReentrant returns (bool) {
        require(_policyId != 0, "IFM:ZERO_POLICY_ID_PAYOUT");
        require(_beneficiary != address(0), "IFM:ZERO_BENEFICIARY_ADDR");
        require(_payoutAmount > 0, "IFM:ZERO_PAYOUT_AMOUNT");
        
        uint256 currentFundBalance = inzoUSDToken.balanceOf(address(this));
        require(currentFundBalance >= _payoutAmount, "IFM:INSUFFICIENT_FUNDS_FOR_PAYOUT");

        bool success = inzoUSDToken.transfer(_beneficiary, _payoutAmount);
        require(success, "IFM:PAYOUT_TRANSFER_FAILED");

        totalClaimsPaidOut += _payoutAmount;

        emit ClaimPayoutProcessed(_policyId, _beneficiary, _payoutAmount);
        return true;
    }
    
    function getFundBalance() external view returns (uint256) {
        return inzoUSDToken.balanceOf(address(this));
    }

    function getPremiumPaidForPolicy(uint256 _policyId) external view returns (uint256) {
        return policyPremiumsPaid[_policyId];
    }

    function emergencyWithdrawERC20(address _tokenAddress, address _to, uint256 _amount) external onlyOwner nonReentrant {
        require(_to != address(0), "IFM:EMERGENCY_TO_ZERO_ADDR");
        require(_amount > 0, "IFM:EMERGENCY_ZERO_AMOUNT");
        
        IERC20 tokenToWithdraw = IERC20(_tokenAddress);
        uint256 tokenBalance = tokenToWithdraw.balanceOf(address(this));
        require(tokenBalance >= _amount, "IFM:EMERGENCY_INSUFFICIENT_BALANCE");

        bool success = tokenToWithdraw.transfer(_to, _amount);
        require(success, "IFM:EMERGENCY_TRANSFER_FAILED");
        
        emit EmergencyWithdrawal(_tokenAddress, _to, _amount);
    }

    function emergencyWithdrawNative(address payable _to, uint256 _amount) external onlyOwner nonReentrant {
        require(_to != address(0), "IFM:EMERGENCY_NATIVE_TO_ZERO_ADDR");
        require(_amount > 0, "IFM:EMERGENCY_NATIVE_ZERO_AMOUNT");

        uint256 contractBalance = address(this).balance;
        require(contractBalance >= _amount, "IFM:EMERGENCY_NATIVE_INSUFFICIENT_BALANCE");
        
        (bool success, ) = _to.call{value: _amount}("");
        require(success, "IFM:EMERGENCY_NATIVE_TRANSFER_FAILED");

        emit EmergencyWithdrawal(address(0), _to, _amount);
    }
}