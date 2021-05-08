// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";

import "../interfaces/IDragonLair.sol";

contract PriceCalculator {
    using SafeMath for uint256;

    //I can use a map, but hardcoding prices makes this contract easier to understand for end users 
    address public constant WETH = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
    //Other tokens
    address public constant QUICK = 0x831753DD7087CaC61aB5644b308642cc1c33Dc13;
    address public constant dQUICK = 0xf28164A485B0B2C90639E47b0f377b4a438a16B1;
    address public constant MUST = 0x9C78EE466D6Cb57A4d01Fd887D2b5dFb2D46288f;
    address public constant WMATIC = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    //Pools
    address public constant QUICK_WETH = 0x1Bd06B96dd42AdA85fDd0795f3B4A79DB914ADD5;
    address public constant MUST_WETH = 0x8826C072657983939c26E684edcfb0e4133f0B3d;
    address public constant WMATIC_WETH = 0xadbF1854e5883eB8aa7BAf50705338739e558E5b;

    function priceOfQuick() view public returns (uint256) {
        return valueOfAsset(QUICK, 1e18);
    }

    //Returns the value of an asset in ETH
    //1) Since contracts cannot deposit into vaults, that means flash loan attacks aren't possible, can't pay off loan in same block
    //2) Manipulators manually driving up the price of the asset by buying a lot of it aren't a danger 
    //as long as there are multiple pools with that asset, since arbitrage bots will fix the price
    //The value gained from an attack is also low compared to capital required (2k ETH to double price of QUICK/ETH)
    function valueOfAsset(address asset, uint256 amount) public view returns (uint256) {
        if(asset == WETH) {
            return amount;
        }
        if(asset == dQUICK) {
            amount = IDragonLair(dQUICK).dQUICKForQUICK(amount);
            return _valueOfAsset(QUICK, amount, QUICK_WETH);
        }
        if(asset == QUICK) {
            return _valueOfAsset(QUICK, amount, QUICK_WETH);
        }
        if(asset == MUST) {
            return _valueOfAsset(MUST, amount, MUST_WETH);
        }
        if(asset == WMATIC) {
            return _valueOfAsset(WMATIC, amount, WMATIC_WETH);
        }

        return 0;
    }

    function _valueOfAsset(address asset, uint256 amount, address pool) internal view returns (uint256) {
        uint256 _bal = IERC20(asset).balanceOf(pool);
        if(_bal == 0) {
            return 0;
        }
        //Set a price cap of 1 ETH on the asset to limit the damage from a price manipulation attack?
        //return Math.min(amount, IERC20(WETH).balanceOf(pool).mul(amount).div(_bal));
        return IERC20(WETH).balanceOf(pool).mul(amount).div(_bal);
    }
}
