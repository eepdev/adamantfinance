// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

// Modified Frax.finance staking rewards contract
// https://github.com/FraxFinance/frax-solidity/blob/master/contracts/Staking/StakingRewards.sol

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import './TransferHelper.sol';
import "./StringHelpers.sol";
import "./Pausable.sol";

import "../interfaces/IMinter.sol";

// Inheritance

interface IMigrator {
    function migrate(uint256 _amount) external;
}

interface IStakingRewards {
    // Views
    function lastTimeRewardApplicable() external view returns (uint256);

    function rewardPerToken() external view returns (uint256);

    function earned(address account) external view returns (uint256);

    function getRewardForDuration() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    // Mutative

    function stake(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function getReward() external;

    //function exit() external;
}

contract RewardsDistributionRecipient is Ownable {
    address public rewardsDistribution;

    //function notifyRewardAmount(uint256 reward, uint256 duration) external;

    modifier onlyRewardsDistribution() {
        require(msg.sender == rewardsDistribution, "Caller is not RewardsDistribution contract");
        _;
    }

    function setRewardsDistribution(address _rewardsDistribution) external onlyOwner {
        rewardsDistribution = _rewardsDistribution;
    }
}

contract AddyStakingRewards is Ownable, IStakingRewards, RewardsDistributionRecipient, ReentrancyGuard, Pausable {
    using SafeMath for uint256;
    using SafeERC20 for ERC20;

    /* ========== STATE VARIABLES ========== */

    address public WETH; //Used to calculate the # of ADDY each user gets; reducing the multiplier in the minter contract will cause the # of claimable ADDY to decrease as well
    ERC20 public rewardsToken;
    ERC20 public stakingToken;
    uint256 public periodFinish = 0;

    // Constant for various precisions
    uint256 private constant PRICE_PRECISION = 1e6;
    uint256 private constant MULTIPLIER_BASE = 1e6;

    // Max reward per second
    uint256 public rewardRate;

    uint256 public rewardsDuration = 604800; // 7 * 86400  (7 days)

    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored = 0;

    address public migrator;
    address public minter;
    address public externalStakingRewards; //The Quickswap/Sushi staking rewards we're staking in (or a wrapper contract for it)

    uint256 public locked_stake_max_multiplier = 3000000; // 6 decimals of precision. 1x = 1000000
    uint256 public locked_stake_time_for_max_multiplier = 3 * 365 * 86400; // 3 years
    uint256 public locked_stake_min_time = 604800; // 7 * 86400  (7 days)
    string private locked_stake_min_time_str = "604800"; // 7 days on genesis

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    uint256 private _staking_token_supply = 0;
    uint256 private _staking_token_boosted_supply = 0;
    mapping(address => uint256) private _unlocked_balances;
    mapping(address => uint256) private _locked_balances;
    mapping(address => uint256) private _boosted_balances;

    mapping(address => LockedStake[]) private lockedStakes;

    mapping(address => bool) public greylist;

    bool public unlockedStakes; // Release lock stakes in case of system migration

    struct LockedStake {
        bytes32 kek_id;
        uint256 start_timestamp;
        uint256 amount;
        uint256 ending_timestamp;
        uint256 multiplier; // 6 decimals of precision. 1x = 1000000
    }

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _rewardsDistribution,
        address _minter,
        address _rewardsToken, //0xc3FdbadC7c795EF1D6Ba111e06fF8F16A20Ea539 ADDY (or ADDY proxy token redeemable for ADDY to mitigate the damage of any possible minting exploits)
        address _stakingToken, //0xa5BF14BB945297447fE96f6cD1b31b40d31175CB ADDY/ETH LP
        address _weth_address, //0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619 WETH
        address _external_staking_rewards
    ) public {
        rewardsDistribution = _rewardsDistribution;
        minter = _minter;

        rewardsToken = ERC20(_rewardsToken);
        stakingToken = ERC20(_stakingToken);
        WETH = _weth_address;
        externalStakingRewards = _external_staking_rewards;

        lastUpdateTime = block.timestamp;
        unlockedStakes = false;
    }

    /* ========== VIEWS ========== */

    function totalSupply() external override view returns (uint256) {
        return _staking_token_supply;
    }

    function totalBoostedSupply() external view returns (uint256) {
        return _staking_token_boosted_supply;
    }

    function stakingMultiplier(uint256 secs) public view returns (uint256) {
        uint256 multiplier = uint(MULTIPLIER_BASE).add(secs.mul(locked_stake_max_multiplier.sub(MULTIPLIER_BASE)).div(locked_stake_time_for_max_multiplier));
        if (multiplier > locked_stake_max_multiplier) multiplier = locked_stake_max_multiplier;
        return multiplier;
    }

    // Total unlocked and locked liquidity tokens
    function balanceOf(address account) external override view returns (uint256) {
        return (_unlocked_balances[account]).add(_locked_balances[account]);
    }

    // Total unlocked liquidity tokens
    function unlockedBalanceOf(address account) external view returns (uint256) {
        return _unlocked_balances[account];
    }

    // Total locked liquidity tokens
    function lockedBalanceOf(address account) public view returns (uint256) {
        return _locked_balances[account];
    }

    // Total 'balance' used for calculating the percent of the pool the account owns
    // Takes into account the locked stake time multiplier
    function boostedBalanceOf(address account) external view returns (uint256) {
        return _boosted_balances[account];
    }

    function lockedStakesOf(address account) external view returns (LockedStake[] memory) {
        return lockedStakes[account];
    }

    function stakingDecimals() external view returns (uint256) {
        return stakingToken.decimals();
    }

    function rewardsFor(address account) external view returns (uint256) {
        // You may have use earned() instead, because of the order in which the contract executes 
        return rewards[account];
    }

    function lastTimeRewardApplicable() public override view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public override view returns (uint256) {
        if (_staking_token_supply == 0) {
            return rewardPerTokenStored;
        }
        else {
            return rewardPerTokenStored.add(
                lastTimeRewardApplicable().sub(lastUpdateTime).mul(rewardRate).mul(MULTIPLIER_BASE).mul(1e18).div(PRICE_PRECISION).div(_staking_token_boosted_supply)
            );
        }
    }

    function earned(address account) public override view returns (uint256) {
        return _boosted_balances[account].mul(rewardPerToken().sub(userRewardPerTokenPaid[account])).div(1e18).add(rewards[account]);
    }

    function getRewardForDuration() external override view returns (uint256) {
        return rewardRate.mul(rewardsDuration).mul(MULTIPLIER_BASE).div(PRICE_PRECISION);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stake(uint256 amount) external override nonReentrant notPaused updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        require(greylist[msg.sender] == false, "address has been greylisted");
        require(msg.sender == tx.origin, "no contracts");

        // Pull the tokens from the staker
        TransferHelper.safeTransferFrom(address(stakingToken), msg.sender, address(this), amount);

        //Deposit the tokens in the external staking rewards contract
        depositToExternalStakingRewards(amount);

        // Staking token supply and boosted supply
        _staking_token_supply = _staking_token_supply.add(amount);
        _staking_token_boosted_supply = _staking_token_boosted_supply.add(amount);

        // Staking token balance and boosted balance
        _unlocked_balances[msg.sender] = _unlocked_balances[msg.sender].add(amount);
        _boosted_balances[msg.sender] = _boosted_balances[msg.sender].add(amount);

        emit Staked(msg.sender, amount);
    }

    function stakeLocked(uint256 amount, uint256 secs) external nonReentrant notPaused updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        require(secs > 0, "Cannot wait for a negative number");
        require(msg.sender == tx.origin, "no contracts");
        require(greylist[msg.sender] == false, "address has been greylisted");
        require(secs >= locked_stake_min_time, StringHelpers.strConcat("Minimum stake time not met (", locked_stake_min_time_str, ")") );

        uint256 multiplier = stakingMultiplier(secs);
        uint256 boostedAmount = amount.mul(multiplier).div(PRICE_PRECISION);
        lockedStakes[msg.sender].push(LockedStake(
            keccak256(abi.encodePacked(msg.sender, block.timestamp, amount)),
            block.timestamp,
            amount,
            block.timestamp.add(secs),
            multiplier
        ));

        // Pull the tokens from the staker
        TransferHelper.safeTransferFrom(address(stakingToken), msg.sender, address(this), amount);

        //Deposit the tokens in the external staking rewards contract
        depositToExternalStakingRewards(amount);

        // Staking token supply and boosted supply
        _staking_token_supply = _staking_token_supply.add(amount);
        _staking_token_boosted_supply = _staking_token_boosted_supply.add(boostedAmount);

        // Staking token balance and boosted balance
        _locked_balances[msg.sender] = _locked_balances[msg.sender].add(amount);
        _boosted_balances[msg.sender] = _boosted_balances[msg.sender].add(boostedAmount);

        emit StakeLocked(msg.sender, amount, secs);
    }

    function withdraw(uint256 amount) public override nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");

        // Staking token balance and boosted balance
        _unlocked_balances[msg.sender] = _unlocked_balances[msg.sender].sub(amount);
        _boosted_balances[msg.sender] = _boosted_balances[msg.sender].sub(amount);

        // Staking token supply and boosted supply
        _staking_token_supply = _staking_token_supply.sub(amount);
        _staking_token_boosted_supply = _staking_token_boosted_supply.sub(amount);

        //Withdraw the tokens from the external staking rewards contract
        withdrawFromExternalStakingRewards(amount);

        // Give the tokens to the withdrawer
        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function withdrawLocked(bytes32 kek_id) public nonReentrant updateReward(msg.sender) {
        LockedStake memory thisStake;
        thisStake.amount = 0;
        uint theIndex;
        for (uint i = 0; i < lockedStakes[msg.sender].length; i++){ 
            if (kek_id == lockedStakes[msg.sender][i].kek_id){
                thisStake = lockedStakes[msg.sender][i];
                theIndex = i;
                break;
            }
        }
        require(thisStake.kek_id == kek_id, "Stake not found");
        require(block.timestamp >= thisStake.ending_timestamp || unlockedStakes == true, "Stake is still locked!");

        uint256 theAmount = thisStake.amount;
        uint256 boostedAmount = theAmount.mul(thisStake.multiplier).div(PRICE_PRECISION);
        if (theAmount > 0){
            // Staking token balance and boosted balance
            _locked_balances[msg.sender] = _locked_balances[msg.sender].sub(theAmount);
            _boosted_balances[msg.sender] = _boosted_balances[msg.sender].sub(boostedAmount);

            // Staking token supply and boosted supply
            _staking_token_supply = _staking_token_supply.sub(theAmount);
            _staking_token_boosted_supply = _staking_token_boosted_supply.sub(boostedAmount);

            // Remove the stake from the array
            delete lockedStakes[msg.sender][theIndex];

            //Withdraw the tokens from the external staking rewards contract
            withdrawFromExternalStakingRewards(theAmount);

            // Give the tokens to the withdrawer
            stakingToken.safeTransfer(msg.sender, theAmount);

            emit WithdrawnLocked(msg.sender, theAmount, kek_id);
        }
    }

    function getReward() public override nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            IMinter(minter).mintFor(msg.sender, WETH, reward); //ADDY is minted into the fee dist contract based on the WETH value of shares accumulated
            //rewardsToken.transfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }
    
    //Transfers a locked stake belonging to the user to the migration logic contract and executes arbitrary migration logic (i.e. to a new locked staking reward contract)
    //Ownership of this contract should be renounced after the migrator is set, so users can trust that the migration contract won't be changed
    //Forfeits all pending rewards (since minter privileges may have been revoked from this contract)
    //Not like Pancake's, etc's migrate function, the user needs to manually call it, for end users reading this who don't know what "msg.sender" means
    function migrateLockedStake(bytes32 kek_id) external nonReentrant {
        require(migrator != address(0), "No migrator set");
        
        LockedStake memory thisStake;
        thisStake.amount = 0;
        uint theIndex;
        for (uint i = 0; i < lockedStakes[msg.sender].length; i++){ 
            if (kek_id == lockedStakes[msg.sender][i].kek_id){
                thisStake = lockedStakes[msg.sender][i];
                theIndex = i;
                break;
            }
        }
        require(thisStake.kek_id == kek_id, "Stake not found");

        rewards[msg.sender] = 0;
        uint256 theAmount = thisStake.amount;
        uint256 boostedAmount = theAmount.mul(thisStake.multiplier).div(PRICE_PRECISION);
        if (theAmount > 0){
            // Staking token balance and boosted balance
            _locked_balances[msg.sender] = _locked_balances[msg.sender].sub(theAmount);
            _boosted_balances[msg.sender] = _boosted_balances[msg.sender].sub(boostedAmount);

            // Staking token supply and boosted supply
            _staking_token_supply = _staking_token_supply.sub(theAmount);
            _staking_token_boosted_supply = _staking_token_boosted_supply.sub(boostedAmount);

            // Remove the stake from the array
            delete lockedStakes[msg.sender][theIndex];

            //Withdraw the tokens from the external staking rewards contract
            withdrawFromExternalStakingRewards(theAmount);

            // Approve tokens and execute arbitrary migration logic
            stakingToken.safeApprove(migrator, 0);
            stakingToken.safeApprove(migrator, theAmount);
            IMigrator(migrator).migrate(theAmount); //will fail if migrator is null

            emit WithdrawnLocked(msg.sender, theAmount, kek_id);
        }
    }

    function depositToExternalStakingRewards(uint256 amount) internal {
        ERC20(stakingToken).safeApprove(externalStakingRewards, 0);
        ERC20(stakingToken).safeApprove(externalStakingRewards, amount);
        IStakingRewards(externalStakingRewards).stake(amount);
    }

    function withdrawFromExternalStakingRewards(uint256 amount) internal {
        IStakingRewards(externalStakingRewards).withdraw(amount);
    }

    //Usage: Get reward, then use recoverERC20 to transfer it to the fee distribution fund
    function getRewardFromExternalStakingRewards() external onlyOwner {
        IStakingRewards(externalStakingRewards).getReward();
    }

    /* ========== RESTRICTED FUNCTIONS ========== */
    
    function notifyRewardAmount(uint256 reward, uint256 _rewardsDuration) external onlyRewardsDistribution updateReward(address(0)) {
        require(block.timestamp.add(_rewardsDuration) >= periodFinish, "Cannot reduce existing period");
        require(reward <= 1e19, "adding too much"); //Set limit of 10 ETH worth to add at once
        require(_rewardsDuration <= 30 days, "duration too long"); //Set limit of 30 days to guard against accidentally swapping the args
        
        if (block.timestamp >= periodFinish) {
            rewardRate = reward.div(_rewardsDuration);
        } else {
            uint256 remaining = periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(rewardRate);
            rewardRate = reward.add(leftover).div(_rewardsDuration);
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        //uint balance = rewardsToken.balanceOf(address(this));
        //require(rewardRate <= balance.div(_rewardsDuration), "Provided reward too high");

        //Check above not applicable, since minter contract mints ADDY rewards to the fee dist contract
        //1e77 is way more tokens than the supply will ever be

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(_rewardsDuration);
        emit RewardAdded(reward, periodFinish);
    }

    // Added to support recovering LP Rewards from other systems to be distributed to holders
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        // Admin cannot withdraw the staking token from the contract
        require(tokenAddress != address(stakingToken));
        ERC20(tokenAddress).transfer(owner(), tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    function setMultipliers(uint256 _locked_stake_max_multiplier) external onlyOwner {
        require(_locked_stake_max_multiplier >= 1, "Multiplier must be greater than or equal to 1");

        locked_stake_max_multiplier = _locked_stake_max_multiplier;
        
        emit LockedStakeMaxMultiplierUpdated(locked_stake_max_multiplier);
    }

    function setLockedStakeTimeForMinAndMaxMultiplier(uint256 _locked_stake_time_for_max_multiplier, uint256 _locked_stake_min_time) external onlyOwner {
        require(_locked_stake_time_for_max_multiplier >= 1, "Multiplier Max Time must be greater than or equal to 1");
        require(_locked_stake_min_time >= 1, "Multiplier Min Time must be greater than or equal to 1");
        
        locked_stake_time_for_max_multiplier = _locked_stake_time_for_max_multiplier;

        locked_stake_min_time = _locked_stake_min_time;
        locked_stake_min_time_str = StringHelpers.uint2str(_locked_stake_min_time);

        emit LockedStakeTimeForMaxMultiplier(locked_stake_time_for_max_multiplier);
        emit LockedStakeMinTime(_locked_stake_min_time);
    }

    function greylistAddress(address _address, bool _greylisted) external onlyOwner {
        greylist[_address] = _greylisted;
    }

    function unlockStakes() external onlyOwner {
        unlockedStakes = !unlockedStakes;
    }

    function setMigrator(address _address) external onlyOwner {
        migrator = _address;
    }

    /* ========== MODIFIERS ========== */

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward, uint256 periodFinish);
    event Staked(address indexed user, uint256 amount);
    event StakeLocked(address indexed user, uint256 amount, uint256 secs);
    event Withdrawn(address indexed user, uint256 amount);
    event WithdrawnLocked(address indexed user, uint256 amount, bytes32 kek_id);
    event RewardPaid(address indexed user, uint256 reward);
    event Recovered(address token, uint256 amount);
    event LockedStakeMaxMultiplierUpdated(uint256 multiplier);
    event LockedStakeTimeForMaxMultiplier(uint256 secs);
    event LockedStakeMinTime(uint256 secs);
}
