pragma solidity ^0.6.12;

import "./IStakingRewards.sol";

interface ILockedStakingRewards is IStakingRewards {
    function stakeLocked(uint256 amount, uint256 secs) external;
    function withdrawLocked(bytes32 kek_id) external;
}