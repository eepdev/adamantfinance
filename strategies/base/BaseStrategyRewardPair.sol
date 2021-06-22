// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "./BaseStrategyStakingRewards.sol";
import "../../interfaces/IERCFund.sol";
import "../../interfaces/IGenericVault.sol";

//For Reward/Other token pairs i.e. Quick/Frax
abstract contract BaseStrategyRewardPair is BaseStrategyStakingRewards {

    uint256 public constant keepMax = 10000;

    address public otherToken;
    address public WMATIC = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    // Uniswap swap paths
    address[] public reward_other_path;
    address[] public reward_matic_path;

    constructor(
        address _rewards,
        address _want,
        address _otherToken,
        address _harvestedToken,
        address _strategist,
        address _router
    )
        public
        BaseStrategyStakingRewards(
            _rewards,
            _want,
            _strategist,
            _harvestedToken,
            _router
        )
    {
        otherToken = _otherToken;

        reward_other_path = new address[](2);
        reward_other_path[0] = _harvestedToken;
        reward_other_path[1] = otherToken;

        reward_matic_path = new address[](2);
        reward_matic_path[0] = _harvestedToken;
        reward_matic_path[1] = WMATIC;
    }

    function getFeeDistToken() public override view returns (address) {
        return WMATIC;
    }

    // **** State Mutations ****
    
    //Swap feeAmount to WMATIC before sending it to the fee dist, since profit is calculated in terms of WMATIC
    function swapRewardToWmaticAndDistributeFee(uint256 feeAmount) internal {
        if(feeAmount > 0) {
            _swapUniswapWithPath(reward_matic_path, feeAmount);
            uint256 _maticFee = IERC20(WMATIC).balanceOf(address(this));
            _notifyJar(_maticFee);
            IERC20(WMATIC).safeTransfer(strategist, _maticFee);
        }
    }

    function harvest() public override onlyHumanOrWhitelisted {
        //Transfer WMATIC that may already be in the contract to the fee dist fund
        IERC20(WMATIC).safeTransfer(strategist, IERC20(WMATIC).balanceOf(address(this)));
        
        //Calculate the amount of tokens harvested and distribute fee
        uint256 balance_before = IERC20(harvestedToken).balanceOf(address(this));
        _getReward();
        uint256 amountHarvested = IERC20(harvestedToken).balanceOf(address(this)).sub(balance_before);
        if (amountHarvested > 0) {
            uint256 feeAmount = amountHarvested.mul(IERCFund(strategist).getFee()).div(keepMax);
            swapRewardToWmaticAndDistributeFee(feeAmount);
        }

        //Swap 1/2 of the remaining harvestedToken for otherToken
        uint256 remainingHarvested = IERC20(harvestedToken).balanceOf(address(this));
        if (remainingHarvested > 0) {
            _swapUniswapWithPath(reward_other_path, remainingHarvested.div(2));
        }

        uint256 harvestedTokenBalance = IERC20(harvestedToken).balanceOf(address(this));
        uint256 otherBalance = IERC20(otherToken).balanceOf(address(this));
        if (harvestedTokenBalance > 0 && otherBalance > 0) {
            IERC20(harvestedToken).safeApprove(currentRouter, 0);
            IERC20(harvestedToken).safeApprove(currentRouter, harvestedTokenBalance);
            IERC20(otherToken).safeApprove(currentRouter, 0);
            IERC20(otherToken).safeApprove(currentRouter, otherBalance);

            IUniswapRouterV2(currentRouter).addLiquidity(
                harvestedToken, otherToken,
                harvestedTokenBalance, otherBalance,
                0, 0,
                address(this),
                now + 60
            );
        }

        // Stake the LP tokens
        _distributePerformanceFeesAndDeposit();
    }

    function _notifyJar(uint256 _amount) internal override {
        IGenericVault(jar).notifyReward(getFeeDistToken(), _amount);
    }
}
