// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";


contract InzoStake is Ownable, ReentrancyGuard {
    IERC20 public immutable token;

    mapping(address => uint256) public stakedBalance;
    uint256 public totalStaked;
    
    uint256 public rewardRate;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsAdded(address indexed funder, uint256 amount);

    modifier updateReward(address _account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;
        if (_account != address(0)) {
            rewards[_account] = earned(_account);
            userRewardPerTokenPaid[_account] = rewardPerTokenStored;
        }
        _;
    }

    constructor(address initialOwner, address _tokenAddress) Ownable(initialOwner) {
        token = IERC20(_tokenAddress);
        lastUpdateTime = block.timestamp;
    }

    function earned(address _account) public view returns (uint256) {
        return stakedBalance[_account] * (rewardPerToken() - userRewardPerTokenPaid[_account]) / 1e18 + rewards[_account];
    }
    
    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) { return rewardPerTokenStored; }
        return rewardPerTokenStored + (((block.timestamp - lastUpdateTime) * rewardRate * 1e18) / totalStaked);
    }
    
    function addRewards(uint256 _rewardAmount) external onlyOwner updateReward(address(0)) {
        require(_rewardAmount > 0, "Amount must be > 0");
        require(token.transferFrom(msg.sender, address(this), _rewardAmount), "Transfer failed");

        uint256 duration = 7 days; 
        if (block.timestamp >= lastUpdateTime + duration) {
            rewardRate = _rewardAmount / duration;
        } else {
            uint256 remaining = (lastUpdateTime + duration) - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (_rewardAmount + leftover) / duration;
        }
        lastUpdateTime = block.timestamp;
        emit RewardsAdded(msg.sender, _rewardAmount);
    }

    function stake(uint256 _amount) external nonReentrant updateReward(msg.sender) {
        require(_amount > 0, "Stake amount must be > 0");
        totalStaked += _amount;
        stakedBalance[msg.sender] += _amount;
        require(token.transferFrom(msg.sender, address(this), _amount), "Stake transfer failed");
        emit Staked(msg.sender, _amount);
    }
    
    function withdraw(uint256 _amount) external nonReentrant {
        claimReward(); 
        require(_amount > 0, "Withdraw amount must be > 0");
        require(stakedBalance[msg.sender] >= _amount, "Insufficient staked balance");
        totalStaked -= _amount;
        stakedBalance[msg.sender] -= _amount;
        require(token.transfer(msg.sender, _amount), "Withdraw transfer failed");
        emit Withdrawn(msg.sender, _amount);
    }
    
    function claimReward() public nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            require(token.transfer(msg.sender, reward), "Reward transfer failed");
            emit RewardPaid(msg.sender, reward);
        }
    }
}