pragma solidity ^0.6.2;

import "./IVault.sol";

//A Dragon Vault is a vault that automatically stakes farmed QUICK.
//The strategy contract tells the vault about the amount of QUICK harvested and staked.
interface IDragonVault is IVault {

    //Strategy calls notifyQuick to let the vault know that a certain amount of dQuick was deposited
    function notifyQuick(address _reward, uint256 _amount) external;
}