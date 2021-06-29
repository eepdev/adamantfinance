// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/ICalculator.sol";
import "../interfaces/IMultiFeeDistribution.sol";

contract Minter is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    /* ========== STATE VARIABLES ========== */

    mapping(address => bool) private _minters;
    address public calculator;
    address public feeDistribution;
    address public dev;
    
    uint256 public addyPerProfitEth = 500; //500 ADDY per ETH = $4-5 per ADDY, similar to price of BUNNY during presale

    /* ========== CONSTRUCTOR ========== */
    
    constructor(address _dev, address _calculator)
        public
    {
        dev = _dev;
        calculator = _calculator;
    }

    /* ========== MODIFIERS ========== */

    modifier onlyMinter {
        require(isMinter(msg.sender) == true, "AddyMinter: caller is not the minter");
        _;
    }

    function mintFor(address user, address asset, uint256 amount) external onlyMinter {
        uint256 valueInEth = ICalculator(calculator).valueOfAsset(asset, amount);
        
        uint256 mintAddy = amountAddyToMint(valueInEth);
        if (mintAddy == 0) return;
        IMultiFeeDistribution(feeDistribution).mint(user, mintAddy);
        //For every 100 tokens minted, 15 additional tokens will go towards development to ensure rapid innovation.
        IMultiFeeDistribution(feeDistribution).mint(dev, mintAddy.mul(15).div(100));
    }
    
    /* ========== VIEWS ========== */

    function isMinter(address account) public view returns (bool) {
        return _minters[account];
    }

    function amountAddyToMint(uint256 ethProfit) public view returns (uint256) {
        return ethProfit.mul(addyPerProfitEth);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /// @dev Obviously should be timelocked
    function setAddyPerProfitEth(uint256 _ratio) external onlyOwner {
        addyPerProfitEth = _ratio;
    }

    /// @dev Should be timelocked, potential minting amount manipulation risk
    function setCalculator(address newCalculator) public onlyOwner {
        calculator = newCalculator;
    }
    
    function setFeeDistribution(address newFeeDistribution) public onlyOwner {
        feeDistribution = newFeeDistribution;
    }

    /// @dev Obviously should be timelocked
    function setMinter(address minter, bool canMint) external onlyOwner {
        if (canMint) {
            _minters[minter] = canMint;
        } else {
            delete _minters[minter];
        }
    }
}