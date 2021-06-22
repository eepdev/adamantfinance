pragma solidity ^0.6.12;

import "./BaseStrategy.sol";
import "../../interfaces/IStakingRewards.sol";

// Base contract for SNX Staking rewards contract interfaces

abstract contract BaseStrategyStakingRewards is BaseStrategy {
    address public rewards;

    // **** Getters ****
    constructor(
        address _rewards,
        address _want,
        address _strategist,
        address _harvestedToken,
        address _currentRouter
    )
        public
        BaseStrategy(_want, _strategist, _harvestedToken, _currentRouter)
    {
        rewards = _rewards;
    }

    function balanceOfPool() public override view returns (uint256) {
        return IStakingRewards(rewards).balanceOf(address(this));
    }

    function getHarvestable() external override view returns (uint256) {
        return IStakingRewards(rewards).earned(address(this));
    }

    // **** Setters ****

    function deposit() public override {
        uint256 _want = IERC20(want).balanceOf(address(this));
        if (_want > 0) {
            IERC20(want).safeApprove(rewards, 0);
            IERC20(want).safeApprove(rewards, _want);
            IStakingRewards(rewards).stake(_want);
        }
    }

    function _withdrawSome(uint256 _amount)
        internal
        override
        returns (uint256)
    {
        IStakingRewards(rewards).withdraw(_amount);
        return _amount;
    }

    function _notifyJar(uint256 _amount) internal virtual;

    /* **** Mutative functions **** */

    function _getReward() internal {
        IStakingRewards(rewards).getReward();
    }

    // **** Admin functions ****

    // Added to support recovering LP Rewards from other systems to be distributed to holders
    function salvage(address recipient, address token, uint256 amount) public onlyOwner {
        // Admin cannot withdraw the staking or harvested token from the contract
        require(token != want, "cannot salvage want");
        require(token != harvestedToken, "cannot salvage harvestedToken");
        IERC20(token).safeTransfer(recipient, amount);
    }
}
