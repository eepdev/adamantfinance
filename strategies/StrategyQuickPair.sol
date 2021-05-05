pragma solidity ^0.6.7;

import "./base/BaseStrategyQuickPair.sol";

contract StrategyQuickPair is BaseStrategyQuickPair {

    string private pair_name;

    constructor(address rewards, address lp, address otherToken, address strategist, string memory _pair_name)
        public
        BaseStrategyQuickPair(
            rewards,
            lp,
            otherToken,
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
