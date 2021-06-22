pragma solidity ^0.6.12;

import "../base/BaseStrategyOtherPair.sol";

contract StrategyOtherPair is BaseStrategyOtherPair {

    address public QUICK = 0x831753DD7087CaC61aB5644b308642cc1c33Dc13;
    address public QUICKSWAP_ROUTER = 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff; //Quickswap router

    constructor(address rewards, address lp, address tokenA, address tokenB, address strategist)
        public
        BaseStrategyOtherPair(
            rewards,
            lp,
            tokenA,
            tokenB,
            QUICK,
            strategist,
            QUICKSWAP_ROUTER
        )
    {

    }
}
