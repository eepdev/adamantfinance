pragma solidity ^0.6.12;

import "../base/BaseStrategyRewardPair.sol";

contract StrategyQuickPair is BaseStrategyRewardPair {

    address public QUICK = 0x831753DD7087CaC61aB5644b308642cc1c33Dc13;
    address public QUICKSWAP_ROUTER = 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff; //Quickswap router

    constructor(address rewards, address lp, address otherToken, address strategist)
        public
        BaseStrategyRewardPair(
            rewards,
            lp,
            otherToken,
            QUICK,
            strategist,
            QUICKSWAP_ROUTER
        )
    {
        
    }
}
