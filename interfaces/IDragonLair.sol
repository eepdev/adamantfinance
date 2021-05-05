// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

// Modified from SushiBar: https://etherscan.io/address/0x8798249c2E607446EfB7Ad49eC89dD1865Ff4272#code
interface IDragonLair {
    // Enter the lair. Pay some QUICK. Earn some dragon QUICK.
    function enter(uint256 _quickAmount) external;

    // Leave the lair. Claim back your QUICK.
    function leave(uint256 _dQuickAmount) external;

    //returns how much QUICK someone gets for depositing dQUICK
    function dQUICKForQUICK(uint256 _dQuickAmount) external view returns (uint256 quickAmount_);
}
