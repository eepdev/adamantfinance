pragma solidity ^0.6.12;

interface IERCFund {
    function feeShareEnabled() external view returns (bool);

    function depositToFeeDistributor(address token, uint256 amount) external;

    function notifyFeeDistribution(address token) external;

    function getFee() external view returns (uint256);

    function recover(address token) external;
}