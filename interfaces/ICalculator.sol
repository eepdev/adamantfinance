pragma solidity ^0.6.12;

interface ICalculator {
    function valueOfAsset(address asset, uint256 amount)
        external
        view
        returns (uint256 valueInETH);
}
