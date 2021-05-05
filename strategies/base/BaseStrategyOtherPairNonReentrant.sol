// SPDX-License-Identifier: MIT
pragma solidity ^0.6.7;

import "./BaseStrategyStakingRewards.sol";
import "../../interfaces/IERCFund.sol";
import "../../interfaces/IGenericVault.sol";

//For A/B token pairs, where I have to convert the harvested token to A (ETH/MATIC/USDC/etc) and then sell 1/2 of A for B
//For pools where the reward contract functions have the "nonReentrant" modifier
//Creating a separate contract results in a lot of duplicate code, but not having to check an extra bool each harvest saves gas
abstract contract BaseStrategyOtherPairNonReentrant is BaseStrategyStakingRewards {

    address public tokenA;
    address public tokenB;
    
    uint256 public constant keepMax = 10000;

    // Uniswap swap paths
    address[] public reward_a_path;
    address[] public a_b_path;

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
        tokenA = _tokenA;
        tokenB = _tokenB;

        reward_a_path = new address[](2);
        reward_a_path[0] = _harvestedToken;
        reward_a_path[1] = _tokenA;

        a_b_path = new address[](2);
        a_b_path[0] = _tokenA;
        a_b_path[1] = _tokenB;
    }

    // **** State Mutations ****
    
    function getReward() external {
        _getReward();
    }

    //getReward() needs to be called manually beforehand because deposit() and getReward() have the nonReentrant modifier, so I cannot claim and deposit in the same tx
    function harvest() public override {
        //prevent unauthorized smart contracts from calling harvest()
        require(msg.sender == tx.origin || msg.sender == owner() || msg.sender == strategist, "not authorized");

        uint256 _harvested_balance = IERC20(harvestedToken).balanceOf(address(this));

        //Distribute fee and swap Quick for tokenA
        if (_harvested_balance > 0) {
            uint256 feeAmount = _harvested_balance.mul(IERCFund(strategist).getFee()).div(keepMax);
            uint256 afterFeeAmount = _harvested_balance.sub(feeAmount);
            _notifyJar(feeAmount);

            IERC20(harvestedToken).safeTransfer(strategist, feeAmount);
            _swapUniswapWithPath(reward_a_path, afterFeeAmount);
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
