pragma solidity ^0.6.7;

interface IERCFund {
    function feeShareEnabled() external view returns (bool);

    function depositToFeeDistributor(address token, uint256 amount) external;

    function getFee() external view returns (uint256);
}