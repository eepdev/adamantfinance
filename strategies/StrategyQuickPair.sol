pragma solidity ^0.6.7;

import "./base/BaseStrategyRewardPair.sol";

contract StrategyQuickPair is BaseStrategyRewardPair {

    address public QUICK = 0x831753DD7087CaC61aB5644b308642cc1c33Dc13;
    address public QUICKSWAP_ROUTER = 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff; //Quickswap router
    string private pair_name;

    constructor(address rewards, address lp, address otherToken, address strategist, string memory _pair_name)
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
        pair_name = _pair_name;
    }

    // **** Views ****

    function pairName() external view returns (string memory) {
        return pair_name;
    }

    function getFeeDistToken() external override view returns (address) {
        return harvestedToken;
    }
}
