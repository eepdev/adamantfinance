pragma solidity ^0.6.0;

interface ICalculator {
    function valueOfAsset(address asset, uint256 amount)
        external
        view
        returns (uint256 valueInETH);
}
