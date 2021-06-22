// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

struct RewardData {
    address token;
    uint256 amount;
}
struct LockedBalance {
    uint256 amount;
    uint256 unlockTime;
}

// Interface for EPS Staking contract - http://ellipsis.finance/
interface IMultiFeeDistribution {

    /* ========== VIEWS ========== */
    function totalSupply() external view returns (uint256);
    function lockedSupply() external view returns (uint256);

    function rewardPerToken(address _rewardsToken) external view returns (uint256);

    function getRewardForDuration(address _rewardsToken) external view returns (uint256);

    // Address and claimable amount of all reward tokens for the given account
    function claimableRewards(address account) external view returns (RewardData[] memory);

    // Total balance of an account, including unlocked, locked and earned tokens
    function totalBalance(address user) view external returns (uint256 amount);

    // Total withdrawable balance for an account to which no penalty is applied
    function unlockedBalance(address user) view external returns (uint256 amount);

    // Final balance received and penalty balance paid by user upon calling exit
    function withdrawableBalance(address user) view external returns (uint256 amount, uint256 penaltyAmount);

    // Information on the "earned" balances of a user
    // Earned balances may be withdrawn immediately for a 50% penalty
    function earnedBalances(address user) view external returns (uint256 total, LockedBalance[] memory earningsData);

    // Information on a user's locked balances
    function lockedBalances(address user) view external returns (uint256 total, uint256 unlockable, uint256 locked, LockedBalance[] memory lockData);

    /* ========== MUTATIVE FUNCTIONS ========== */

    // Mint new tokens
    // Minted tokens receive rewards normally but incur a 50% penalty when
    // withdrawn before lockDuration has passed.
    function mint(address user, uint256 amount) external;

    // Withdraw full unlocked balance and claim pending rewards
    function exit() external;

    // Withdraw all currently locked tokens where the unlock time has passed
    function withdrawExpiredLocks() external;

    // Claim all pending staking rewards (both BUSD and EPS)
    function getReward() external;

    // Stake tokens to receive rewards
    // Locked tokens cannot be withdrawn for lockDuration and are eligible to receive stakingReward rewards
    function stake(uint256 amount, bool lock) external;
    
    // Withdraw staked tokens
    // First withdraws unlocked tokens, then earned tokens. Withdrawing earned tokens
    // incurs a 50% penalty which is distributed based on locked balances.
    function withdraw(uint256 amount) external;
    
    /* ========== ADMIN CONFIGURATION ========== */

    // Used to let FeeDistribution know that _rewardsToken was added to it
    function notifyRewardAmount(address _rewardsToken, uint256 rewardAmount) external;
}