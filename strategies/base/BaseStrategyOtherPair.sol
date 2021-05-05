// SPDX-License-Identifier: MIT
pragma solidity ^0.6.7;

import "./BaseStrategyStakingRewards.sol";
import "../../interfaces/IERCFund.sol";
import "../../interfaces/IGenericVault.sol";

//For A/B token pairs, where I have to convert QUICK to A (ETH/MATIC/USDC/etc) and then sell 1/2 of A for B
abstract contract BaseStrategyOtherPair is BaseStrategyStakingRewards {

    // Token addresses for MATIC
    address public quick = 0x831753DD7087CaC61aB5644b308642cc1c33Dc13;
    address public tokenA;
    address public tokenB;
    
    uint256 public constant keepMax = 10000;

    // Uniswap swap paths
    address[] public quick_a_path;
    address[] public a_b_path;

    constructor(
        address _rewards,
        address _want,
        address _tokenA,
        address _tokenB,
        address _strategist
    )
        public
        BaseStrategyStakingRewards(
            _rewards,
            _want,
            _strategist,
            quick
        )
    {
        tokenA = _tokenA;
        tokenB = _tokenB;

        quick_a_path = new address[](2);
        quick_a_path[0] = quick;
        quick_a_path[1] = _tokenA;

        a_b_path = new address[](2);
        a_b_path[0] = _tokenA;
        a_b_path[1] = _tokenB;
    }

    // **** State Mutations ****

    function harvest() public override {
        //prevent unauthorized smart contracts from calling harvest()
        require(msg.sender == tx.origin || msg.sender == owner() || msg.sender == strategist, "not authorized");
        
        _getReward();

        uint256 _quick_balance = IERC20(quick).balanceOf(address(this));

        //Distribute fee and swap Quick for tokenA
        if (_quick_balance > 0) {
            uint256 feeAmount = _quick_balance.mul(IERCFund(strategist).getFee()).div(keepMax);
            uint256 afterFeeAmount = _quick_balance.sub(feeAmount);
            _notifyJar(feeAmount);

            IERC20(quick).safeTransfer(strategist, feeAmount);
            //Calling depositToFeeDistributor increases the harvest cost from 600k gas to 800k gas
            //IERC20(quick).safeApprove(strategist, 0);
            //IERC20(quick).safeApprove(strategist, feeAmount);
            //IERCFund(strategist).depositToFeeDistributor(quick, feeAmount);

            _swapUniswapWithPath(quick_a_path, afterFeeAmount);
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
        IGenericVault(jar).notifyReward(harvestedToken, _amount);
    }
}
