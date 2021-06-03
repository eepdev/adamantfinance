// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";

import "../interfaces/IDragonLair.sol";
import "../interfaces/IAggregatorInterface.sol";

contract PriceCalculator {
    using SafeMath for uint256;

    //Pair tokens
    address public constant WETH = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
    address public constant WMATIC = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    //Pools
    address public constant WMATIC_WETH = 0xadbF1854e5883eB8aa7BAf50705338739e558E5b;
    //Oracles
    address public constant WMATIC_WETH_ORACLE = 0x327e23A4855b6F663a28c5161541d69Af8973302; //https://data.chain.link/polygon/mainnet/crypto-eth/matic-eth

    //Returns the value of an asset (currently only WMATIC and ETH) in ETH
    //Uses Chainlink oracle and balances of WMATIC/WETH pool to determine the price of WMATIC/WETH
    function valueOfAsset(address asset, uint256 amount) public view returns (uint256) {
        if(asset == WETH) {
            return amount;
        }
        if(asset == WMATIC) {
            //Set a cap of min(1/100 ETH, oraclePrice, poolPrice) on the price of WMATIC
            uint256 value = Math.min(valueOfAssetOracle(WMATIC, amount), _valueOfAsset(WMATIC, amount, WMATIC_WETH));
            return Math.min(amount.div(100), value);
        }
        return 0;
    }

    function _valueOfAsset(address asset, uint256 amount, address pool) internal view returns (uint256) {
        uint256 _bal = IERC20(asset).balanceOf(pool);
        if(_bal == 0) {
            return 0;
        }
        return IERC20(WETH).balanceOf(pool).mul(amount).div(_bal);
    }

    function valueOfAssetOracle(address asset, uint256 amount) public view returns (uint256) {
        if(asset == WMATIC) {
            int256 answer = int256(IAggregatorInterface(WMATIC_WETH_ORACLE).latestAnswer()); //Price of 1 WMATIC in terms of ETH
            if(answer <= 0) return 0; //If the oracle bugs out, then no ADDY will be minted; frontend should alert users if issues with the Chainlink oracle are detected
            uint256 oraclePrice = uint256(answer);
            return oraclePrice.mul(amount).div(1e18);
        }
        return 0;
    }
}
