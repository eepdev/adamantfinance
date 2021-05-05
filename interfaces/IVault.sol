pragma solidity ^0.6.2;

import "./IJar.sol";

//Vaults are jars that emit ADDY rewards.
interface IVault is IJar {

    function getPendingReward(address _user) external view returns (uint256);

    function getLastDepositTime(address _user) external view returns (uint256);

    function getTokensStaked(address _user) external view returns (uint256);

    function totalShares() external view returns (uint256);
}