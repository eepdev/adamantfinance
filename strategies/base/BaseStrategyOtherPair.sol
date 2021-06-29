// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "./BaseStrategyStakingRewards.sol";
import "../../interfaces/IERCFund.sol";
import "../../interfaces/IGenericVault.sol";

//For A/B token pairs, where I have to convert the harvested token to A (ETH/MATIC/USDC/etc) and then sell 1/2 of A for B
abstract contract BaseStrategyOtherPair is BaseStrategyStakingRewards {

    // Addresses for MATIC
    address public tokenA;
    address public tokenB;
    address public WMATIC = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    
    uint256 public constant keepMax = 10000;

    // Uniswap swap paths
    address[] public reward_a_path;
    address[] public a_b_path;
    address[] public reward_matic_path;

    constructor(
        address _rewards,
        address _want,
        address _tokenA,
        address _tokenB,
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
        require(_tokenA != address(0));
        require(_tokenB != address(0));

        tokenA = _tokenA;
        tokenB = _tokenB;

        reward_a_path = new address[](2);
        reward_a_path[0] = _harvestedToken;
        reward_a_path[1] = _tokenA;

        a_b_path = new address[](2);
        a_b_path[0] = _tokenA;
        a_b_path[1] = _tokenB;

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

    function harvest() public override onlyHumanOrWhitelisted nonReentrant {
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

        //Swap remaining harvested tokens for tokenA
        uint256 remainingHarvested = IERC20(harvestedToken).balanceOf(address(this));
        if (remainingHarvested > 0) {
            _swapUniswapWithPath(reward_a_path, remainingHarvested);
        }

        //Swap 1/2 of tokenA for tokenB
        uint256 _balanceA = IERC20(tokenA).balanceOf(address(this));
        if (_balanceA > 0) {
            _swapUniswapWithPath(a_b_path, _balanceA.div(2));
        }

        //Add liquidity
        uint256 aBalance = IERC20(tokenA).balanceOf(address(this));
        uint256 bBalance = IERC20(tokenB).balanceOf(address(this));
        if (aBalance > 0 && bBalance > 0) {
            IERC20(tokenA).safeApprove(currentRouter, 0);
            IERC20(tokenA).safeApprove(currentRouter, aBalance);
            IERC20(tokenB).safeApprove(currentRouter, 0);
            IERC20(tokenB).safeApprove(currentRouter, bBalance);

            IUniswapRouterV2(currentRouter).addLiquidity(
                tokenA, tokenB,
                aBalance, bBalance,
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
