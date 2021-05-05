pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/IUniswapV2Pair.sol";
import "../interfaces/IUniswapRouterV2.sol";
import "../interfaces/IMultiFeeDistribution.sol";

//Contract where the fees are sent to before they are converted and sent to the feeDistributor contract
contract ERCFund is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public constant weth = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619; //weth for Matic
    address public currentRouter = 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff; //Quickswap router
    address public feeDistributor;
    bool public feeSharingEnabled = false;
    uint256 public fee = 200;
    uint256 public feeMAX = 10000;

    constructor(address distributor) public {
        feeDistributor = distributor;
    }

    function notifyFeeDistribution(address token) public {
        uint256 balance = IERC20(token).balanceOf(address(this));

        IERC20(token).safeApprove(feeDistributor, 0);
        IERC20(token).safeApprove(feeDistributor, balance);
        IMultiFeeDistribution(feeDistributor).notifyRewardAmount(token, balance);
    }
    
    //Doesn't support Fee on Transfer tokens, convert those to something else first
    //Transfer token from sender, then transfers it to the fee distributor
    function depositToFeeDistributor(address token, uint256 amount) public {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        IERC20(token).safeApprove(feeDistributor, 0);
        IERC20(token).safeApprove(feeDistributor, amount);
        IMultiFeeDistribution(feeDistributor).notifyRewardAmount(token, amount);
    }

    /* ========== VIEW FUNCTIONS ========== */

    function feeShareEnabled() external view returns (bool) {
        return feeSharingEnabled;
    }
    
    function getFee() external view returns (uint256) {
        return fee;
    }

    /* ========== CONVERSION FUNCTIONS ========== */

    function convertFees(address token_in, address token_out) public onlyOwner {
        uint256 balance = IERC20(token_in).balanceOf(address(this));
        if (balance > 0) {
            _swapUniswap(token_in, token_out, balance);
        }
    }

    function convertFeesWithPath(address token_in, address token_out) public onlyOwner {
        uint256 balance = IERC20(token_in).balanceOf(address(this));
        if (balance > 0) {
            address[] memory pair = new address[](2);
            pair[0] = token_in;
            pair[1] = token_out;
            _swapUniswapWithPath(pair, balance);
        }
    }

    function convertFeesWithPathForFeeOnTransferTokens(address token_in, address token_out) public onlyOwner {
        uint256 balance = IERC20(token_in).balanceOf(address(this));
        if (balance > 0) {
            address[] memory pair = new address[](2);
            pair[0] = token_in;
            pair[1] = token_out;
            _swapUniswapWithPathForFeeOnTransferTokens(pair, balance);
        }
    }

    /* ========== SETTER FUNCTIONS ========== */

    function setFeeDistributor(address distributor) public onlyOwner {
        feeDistributor = distributor;
    }

    function setFeeSharingEnabled(bool enabled) public onlyOwner {
        feeSharingEnabled = enabled;
    }

    function setFee(uint256 _fee) public onlyOwner {
        require(_fee <= 3000);
        fee = _fee;
    }

    /* ========== EMERGENCY FUNCTIONS ========== */

    function recover(address token) public onlyOwner {
        uint256 _token = IERC20(token).balanceOf(address(this));
        if (_token > 0) {
            IERC20(token).safeTransfer(msg.sender, _token);
        }
    }

    /* ========== UNISWAP FUNCTIONS ========== */

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

    // **** Events **** // (forgot to put these in the live version)
    event Recovered(address indexed tokenWithdrew);
    event Notified(address indexed tokenDeposited);
}