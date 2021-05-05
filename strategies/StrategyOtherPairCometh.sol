pragma solidity ^0.6.7;

import "./base/BaseStrategyOtherPairNonReentrant.sol";

contract StrategyOtherPairCometh is BaseStrategyOtherPairNonReentrant {

    address public constant MUST_TOKEN = 0x9C78EE466D6Cb57A4d01Fd887D2b5dFb2D46288f;
    address public constant COMETH_ROUTER = 0x93bcDc45f7e62f89a8e901DC4A0E2c6C427D9F25;
    string private pair_name;

    constructor(address rewards, address lp, address tokenA, address tokenB, address strategist, string memory _pair_name)
        public
        BaseStrategyOtherPairNonReentrant(
            rewards,
            lp,
            tokenA,
            tokenB,
            MUST_TOKEN,
            strategist,
            COMETH_ROUTER
        )
    {
        pair_name = _pair_name;
    }

    // **** Views ****

    function pairName() external view returns (string memory) {
        return pair_name;
    }
}
