pragma solidity ^0.6.7;

import "./VaultBase.sol";
import "../interfaces/IERCFund.sol";

//Stakes farmed QUICK in the Dragon's Lair
contract DragonVault is VaultBase {
    
    //The Quick staking address (also the dQuick token contract)
    address public dragonLair = 0xf28164A485B0B2C90639E47b0f377b4a438a16B1;

    constructor(IStrategy _strategy, address _minter, address _ercFund) 
        public
        VaultBase(_strategy, _minter, _ercFund
        )
    {
        
    }

    // Handles claiming the user's pending rewards
    function _claimReward(address _user) internal override {
        UserInfo storage user = userInfo[_user];
        if (user.shares > 0) {
            uint256 pendingReward = user.shares.mul(accRewardPerShare).div(1e12).sub(user.rewardDebt);
            if (pendingReward > 0) {
                totalPendingReward = totalPendingReward.sub(pendingReward);
                //Calculate fee
                uint256 feeAmount = pendingReward.mul(IERCFund(ercFund).getFee()).div(keepMax);
                uint256 afterFeeAmount = pendingReward.sub(feeAmount);
                //Send fee to fund
                IERC20(dragonLair).safeTransfer(ercFund, feeAmount);
                //Transfer remaining dQuick to the user
                _safeRewardTransfer(_user, afterFeeAmount);
                
                //Apply ADDY reward multiplier to the feeAmount that the minter will mint for
                feeAmount = applyRewardMultiplier(feeAmount);
                //Based on the profit generated for fee-sharing, the minter will mint to MultiFeeDistribution and then stake the minted tokens for the user
                minter.mintFor(_user, IStrategy(strategy).harvestedToken(), feeAmount);
                emit Claimed(_user, pendingReward);
            }
        }
    }

    // Internal function to safely transfer the reward token in case there is a rounding error
    function _safeRewardTransfer(address _to, uint256 _amount) internal {
        uint256 rewardBal = IERC20(dragonLair).balanceOf(address(this));
        if (_amount > rewardBal) {
            IERC20(dragonLair).transfer(_to, rewardBal);
        } else {
            IERC20(dragonLair).transfer(_to, _amount);
        }
    }

    //Strategy calls notifyQuick to let the vault know that a certain amount of dQuick was deposited
    function notifyQuick(address _reward, uint256 _amount) public {
        require(msg.sender == strategy);
        if(_amount == 0) {
            return;
        }

        totalPendingReward = totalPendingReward.add(_amount);
        accRewardPerShare = accRewardPerShare.add(_amount.mul(1e12).div(totalShares)); //shouldn't be adding reward if totalShares == 0 anyway

        emit RewardAdded(_reward, _amount);
    }
    
    //Only dQuick should be in this contract
    function salvage(address _recipient, address _token, uint256 _amount) public onlyOwner {
        require(_token != dragonLair, "cannot salvage");
        IERC20(_token).safeTransfer(_recipient, _amount);
    }
}
