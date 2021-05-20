pragma solidity ^0.6.7;

import "./VaultBase.sol";

contract GenericVault is VaultBase {

    constructor(IStrategy _strategy, address _minter, address _ercFund) 
        public
        VaultBase(_strategy, _minter, _ercFund)
    {
        
    }

    // Handles claiming the user's pending rewards
    function _claimReward(address _user) internal override {
        UserInfo storage user = userInfo[_user];
        if (user.shares > 0) {
            uint256 pendingReward = user.shares.mul(accRewardPerShare).div(1e12).sub(user.rewardDebt);
            if (pendingReward > 0) {
                totalPendingReward = totalPendingReward.sub(pendingReward);
                
                //Apply reward multiplier to the pendingReward that the minter will mint for
                pendingReward = applyRewardMultiplier(pendingReward);
                //Minter will mint to MultiFeeDistribution and then stake the minted tokens for the user
                minter.mintFor(_user, IStrategy(strategy).getFeeDistToken(), pendingReward);
                emit Claimed(_user, pendingReward);
            }
        }
    }

    //Strategy calls notifyReward to let the vault know that it earned a certain amount of profit (the performance fee) for gov token stakers
    function notifyReward(address _reward, uint256 _amount) public {
        require(msg.sender == strategy);
        if(_amount == 0) {
            return;
        }

        totalPendingReward = totalPendingReward.add(_amount);
        accRewardPerShare = accRewardPerShare.add(_amount.mul(1e12).div(totalShares)); //shouldn't be adding reward if totalShares == 0 anyway

        emit RewardAdded(_reward, _amount);
    }
}
