// SPDX-License-Identifier: MIT
pragma solidity ^0.6.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../../interfaces/IJar.sol";
import "../../interfaces/IUniswapV2Pair.sol";
import "../../interfaces/IUniswapRouterV2.sol";

abstract contract BaseStrategy is Ownable {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    uint256 public lastHarvestTime = 0;

    // Tokens
    address public want; //The LP token, Harvest calls this "rewardToken"
    address public constant weth = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619; //weth for Matic
    address public harvestedToken; //The token we harvest, will add support for multiple tokens in v2

    // User accounts
    address public strategist; //The address the performance fee is sent to
    address public jar;

    // Dex
    address public currentRouter = 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff; //Quickswap router

    constructor(
        address _want,
        address _strategist,
        address _harvestedToken,
        address _currentRouter
    ) public {
        require(_want != address(0));
        require(_strategist != address(0));

        want = _want;
        strategist = _strategist;
        harvestedToken = _harvestedToken;
        currentRouter = _currentRouter;
    }

    // **** Views **** //

    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    function balanceOfPool() public virtual view returns (uint256);

    function getHarvestable() external virtual view returns (uint256);

    function balanceOf() public view returns (uint256) {
        return balanceOfWant().add(balanceOfPool());
    }

    // **** Setters **** //

    function setJar(address _jar) external onlyOwner {
        require(jar == address(0), "jar already set");
        jar = _jar;
        emit SetJar(_jar);
    }

    //Changes the address the performance fee is sent to
    /*function setStrategist(address _strategist) external onlyOwner {
        strategist = _strategist;
    }*/

    // **** State mutations **** //
    function deposit() public virtual;

    // Withdraw partial funds, normally used with a jar withdrawal
    function withdraw(uint256 _amount) external {
        require(msg.sender == jar, "!jar");
        uint256 _balance = IERC20(want).balanceOf(address(this));
        if (_balance < _amount) {
            _amount = _withdrawSome(_amount.sub(_balance));
            _amount = _amount.add(_balance);
        }

        IERC20(want).safeTransfer(jar, _amount);
    }

    // Withdraw funds, used to swap between strategies
    function withdrawForSwap(uint256 _amount)
        external
        returns (uint256 balance)
    {
        require(msg.sender == jar, "!jar");
        _withdrawSome(_amount);

        balance = IERC20(want).balanceOf(address(this));

        IERC20(want).safeTransfer(jar, balance);
    }

    function _withdrawAll() internal {
        _withdrawSome(balanceOfPool());
    }

    function _withdrawSome(uint256 _amount) internal virtual returns (uint256);

    function harvest() public virtual;

    // **** Internal functions ****
    function _swapUniswap(
        address _from,
        address _to,
        uint256 _amount
    ) internal {
        require(_to != address(0));

        // Swap with uniswap
        IERC20(_from).safeApprove(currentRouter, 0);
        IERC20(_from).safeApprove(currentRouter, _amount);

        address[] memory path;

        if (_from == weth || _to == weth) {
            path = new address[](2);
            path[0] = _from;
            path[1] = _to;
        } else {
            path = new address[](3);
            path[0] = _from;
            path[1] = weth;
            path[2] = _to;
        }

        IUniswapRouterV2(currentRouter).swapExactTokensForTokens(
            _amount,
            0,
            path,
            address(this),
            now.add(60)
        );
    }

    function _swapUniswapWithPath(
        address[] memory path,
        uint256 _amount
    ) internal {
        require(path[1] != address(0));

        // Swap with uniswap
        IERC20(path[0]).safeApprove(currentRouter, 0);
        IERC20(path[0]).safeApprove(currentRouter, _amount);

        IUniswapRouterV2(currentRouter).swapExactTokensForTokens(
            _amount,
            0,
            path,
            address(this),
            now.add(60)
        );
    }

    function _swapUniswapWithPathForFeeOnTransferTokens(
        address[] memory path,
        uint256 _amount
    ) internal {
        require(path[1] != address(0));

        // Swap with uniswap
        IERC20(path[0]).safeApprove(currentRouter, 0);
        IERC20(path[0]).safeApprove(currentRouter, _amount);

        IUniswapRouterV2(currentRouter).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amount,
            0,
            path,
            address(this),
            now.add(60)
        );
    }

    function _distributePerformanceFeesAndDeposit() internal {
        uint256 _want = IERC20(want).balanceOf(address(this));

        if (_want > 0) {
            deposit();
        }
        lastHarvestTime = now;
    }

    // **** Events **** //
    event SetJar(address indexed jar);
}