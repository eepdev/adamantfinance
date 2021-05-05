// SPDX-License-Identifier: MIT
pragma solidity ^0.6.7;

import "./base/BaseStrategyStakingRewards.sol";
import "../interfaces/IDragonLair.sol";
import "../interfaces/IDragonVault.sol";

//Compounds farmed QUICK to get more QUICK
contract StrategyDragonLair is BaseStrategyStakingRewards {

    string private pair_name;

    // Token addresses for MATIC
    address public quick = 0x831753DD7087CaC61aB5644b308642cc1c33Dc13;

    //The Quick staking address and the dQuick token contract
    address public dragonLair = 0xf28164A485B0B2C90639E47b0f377b4a438a16B1;
    
    uint256 public constant keepMax = 10000;

    constructor(
        address _rewards,
        address _want, //the LP token
        address _strategist, 
        string memory _pair_name
    )
        public
        BaseStrategyStakingRewards(
            _rewards,
            _want,
            _strategist,
            dragonLair
        )
    {
        pair_name = _pair_name;
    }

    // **** State Mutations ****

    function harvest() public override {
        //prevent unauthorized smart contracts from calling harvest()
        require(msg.sender == tx.origin || msg.sender == owner() || msg.sender == strategist, "not authorized");
        
        _getReward();

        uint256 _quick_balance = IERC20(quick).balanceOf(address(this));
        if (_quick_balance > 0) {
            //Stake QUICK in lair to get dQuick
            IERC20(quick).safeApprove(dragonLair, 0);
            IERC20(quick).safeApprove(dragonLair, _quick_balance);
            IDragonLair(dragonLair).enter(_quick_balance);
        }

        //Tell vault about dQuick earnings and send it to the vault
        uint256 dQuickBalance = IERC20(dragonLair).balanceOf(address(this));
        _notifyJar(dQuickBalance);
        IERC20(dragonLair).safeTransfer(jar, IERC20(dragonLair).balanceOf(address(this)));
    }

    function _notifyJar(uint256 _amount) internal override {
        IDragonVault(jar).notifyQuick(harvestedToken, _amount);
    }

    // **** Views ****

    function pairName() external view returns (string memory) {
        return pair_name;
    }
}
