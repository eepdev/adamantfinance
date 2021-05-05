pragma solidity ^0.6.7;

import "./base/BaseStrategyOtherPair.sol";

contract StrategyOtherPair is BaseStrategyOtherPair {

    string private pair_name;

    constructor(address rewards, address lp, address tokenA, address tokenB, address strategist, string memory _pair_name)
        public
        BaseStrategyOtherPair(
            rewards,
            lp,
            tokenA,
            tokenB,
            strategist
        )
    {
        pair_name = _pair_name;
    }

    // **** Views ****

    function pairName() external view returns (string memory) {
        return pair_name;
    }
}
