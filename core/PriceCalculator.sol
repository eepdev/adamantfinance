// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../interfaces/IDragonLair.sol";

contract PriceCalculator {
    using SafeMath for uint256;

    address public constant WETH = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;

    address public constant QUICK = 0x831753DD7087CaC61aB5644b308642cc1c33Dc13;
    address public constant dQUICK = 0xf28164A485B0B2C90639E47b0f377b4a438a16B1;

    address public constant QUICK_WETH = 0x1Bd06B96dd42AdA85fDd0795f3B4A79DB914ADD5;

    function priceOfQuick() view public returns (uint256) {
        return valueOfAsset(QUICK, 1e18);
    }

    //Returns the value of an asset in ETH
    //1) Since contracts cannot deposit into vaults, that means flash loan attacks aren't possible, can't pay off loan in same block
    //2) Manipulators manually driving up the price of the asset by buying a lot of it aren't a danger 
    //as long as there are multiple pools with that asset, since arbitrage bots will fix the price
    //The value gained from an attack is also low compared to capital required (2k ETH to double price of QUICK/ETH)
    function valueOfAsset(address asset, uint256 amount) public view returns (uint256 valueInETH) {
        if(asset == WETH) {
            return amount;
        }
        if(asset != QUICK && asset != dQUICK) {
            //only supports QUICK right now
            return 0;
        }
        if(asset == dQUICK) {
            amount = IDragonLair(dQUICK).dQUICKForQUICK(amount);
        }

        uint256 _quick = IERC20(QUICK).balanceOf(QUICK_WETH);
        if(_quick == 0) {
            return 0;
        }
        valueInETH = IERC20(WETH).balanceOf(QUICK_WETH).mul(amount).div(_quick);
    }
}
