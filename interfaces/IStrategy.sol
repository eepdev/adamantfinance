pragma solidity ^0.6.12;

interface IStrategy {
    //Returns the token sent to the fee dist contract, which is used to calculate the amount of ADDY to mint when claiming rewards
    function getFeeDistToken() external view returns (address);

    function lastHarvestTime() external view returns (uint256);

    function rewards() external view returns (address);

    function want() external view returns (address);

    function deposit() external;

    function withdrawForSwap(uint256) external returns (uint256);

    function withdraw(uint256) external;

    function balanceOf() external view returns (uint256);

    function getHarvestable() external view returns (uint256);

    function harvest() external;

    function setJar(address _jar) external;
}