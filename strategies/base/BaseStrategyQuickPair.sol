// SPDX-License-Identifier: MIT
pragma solidity ^0.6.7;

import "./BaseStrategyStakingRewards.sol";
import "../../interfaces/IERCFund.sol";
import "../../interfaces/IGenericVault.sol";

//For Quick/Other token pairs
abstract contract BaseStrategyQuickPair is BaseStrategyStakingRewards {

    // Token addresses for MATIC
    address public quick = 0x831753DD7087CaC61aB5644b308642cc1c33Dc13;
    address public otherToken;
    
    uint256 public constant keepMax = 10000;

    // Uniswap swap paths
    address[] public quick_other_path;

    constructor(
        address _rewards,
        address _want,
        address _otherToken,
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
        otherToken = _otherToken;

        quick_other_path = new address[](2);
        quick_other_path[0] = quick;
        quick_other_path[1] = otherToken;
    }

    // **** State Mutations ****

    function harvest() public override {
        //prevent unauthorized smart contracts from calling harvest()
        require(msg.sender == tx.origin || msg.sender == owner() || msg.sender == strategist, "not authorized");
        
        _getReward();

        uint256 _quick_balance = IERC20(quick).balanceOf(address(this));

        //Distribute fee and swap 1/2 of Quick for otherToken
        if (_quick_balance > 0) {
            uint256 feeAmount = _quick_balance.mul(IERCFund(strategist).getFee()).div(keepMax);
            uint256 afterFeeAmount = _quick_balance.sub(feeAmount);
            _notifyJar(feeAmount);

            IERC20(quick).safeTransfer(strategist, feeAmount);
            //Calling depositToFeeDistributor increases the harvest cost from 600k gas to 800k gas
            //IERC20(quick).safeApprove(strategist, 0);
            //IERC20(quick).safeApprove(strategist, feeAmount);
            //IERCFund(strategist).depositToFeeDistributor(quick, feeAmount);

            _swapUniswapWithPath(quick_other_path, afterFeeAmount.div(2));
        }

        uint256 quickBalance = IERC20(quick).balanceOf(address(this));
        uint256 otherBalance = IERC20(otherToken).balanceOf(address(this));
        if (quickBalance > 0 && otherBalance > 0) {
            IERC20(quick).safeApprove(currentRouter, 0);
            IERC20(quick).safeApprove(currentRouter, quickBalance);
            IERC20(otherToken).safeApprove(currentRouter, 0);
            IERC20(otherToken).safeApprove(currentRouter, otherBalance);

            IUniswapRouterV2(currentRouter).addLiquidity(
                quick, otherToken,
                quickBalance, otherBalance,
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
