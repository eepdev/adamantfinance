// Based on https://github.com/iearn-finance/vaults/blob/master/contracts/vaults/yVault.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/governance/IBoostHandler.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/IMinter.sol";
import "../interfaces/IVault.sol";

abstract contract VaultBase is IVault, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    // Info of each user
    struct UserInfo {
        uint256 shares; // User shares
        uint256 rewardDebt; // Reward debt (in terms of WMATIC)
        uint256 lastDepositTime;
        uint256 tokensStaked; // Number of tokens staked, only used to calculate profit on the frontend (different than shares)
    }

    uint256 public constant keepMax = 10000;

    /* ========== STATE VARIABLES ========== */

    // Info of each user
    mapping (address => UserInfo) public userInfo;

    // The total amount of pending rewards available for stakers to claim
    uint256 public override totalPendingReward;
    // Accumulated rewards per share, times 1e12.
    uint256 public accRewardPerShare;
    // The total # of shares issued
    uint256 public override totalShares;
    // Withdrawing before this much time has passed will have a withdrawal penalty
    uint256 public override withdrawPenaltyTime = 3 days;
    // Withdrawal penalty, 100 = 1%
    uint256 public override withdrawPenalty = 50;
    // For vaults that are farming pools with a deposit fee
    uint256 public depositFee = 0;
    //Allowed amount of the token sent to the fee dist each vault can mint ADDY rewards for, default 1000 (1000 WMATIC = roughly 0.65 ETH = 312 ADDY)
    uint256 public override rewardAllocation = 1e18 * 1000;

    // Certain vaults will give up to 10x ADDY rewards
    // Additional usecase for ADDY: lock it to boost the yield of a certain vault
    uint256 private rewardMultiplier = 1000;
    uint256 private constant MULTIPLIER_BASE = 1000;
    uint256 private constant MULTIPLIER_MAX = 10000;
    uint256 private constant BOOST_BASE = 10000;

    IERC20 public override token;
    address public override strategy;
    IMinter internal minter;
    address public ercFund;
    address public boostHandler;

    constructor(IStrategy _strategy, address _minter, address _ercFund)
        public
    {
        require(address(_strategy) != address(0));
        token = IERC20(_strategy.want());
        strategy = address(_strategy);
        minter = IMinter(_minter);
        ercFund = _ercFund;
    }

    /* ========== VIEW FUNCTIONS ========== */

    // 1000 = 1x multiplier
    function getRewardMultiplier() public override view returns (uint256) {
        return rewardMultiplier;
    }

    function applyRewardMultiplier(uint256 _amount) internal view returns (uint256) {
        return _amount.mul(rewardMultiplier).div(MULTIPLIER_BASE);
    }

    function getBoost(address _user) public view returns (uint256) {
        if (boostHandler != address(0)) {
            return IBoostHandler(boostHandler).getBoost(_user, address(this));
        }
        return 0;
    }

    //Returns base amount + amount from boost
    function applyBoost(address _user, uint256 _amount) internal view returns (uint256) {
        if (boostHandler != address(0)) {
            return _amount.add(_amount.mul(getBoost(_user)).div(BOOST_BASE));
        }
        return _amount;
    }

    function getRatio() public override view returns (uint256) {
        return balance().mul(1e18).div(totalShares);
    }

    function balance() public override view returns (uint256) {
        return
            token.balanceOf(address(this)).add(
                IStrategy(strategy).balanceOf()
            );
    }

    function balanceOf(address _user) public override view returns (uint256) {
        return userInfo[_user].shares;
    }

    function getPendingReward(address _user) public override view returns (uint256) {
        return userInfo[_user].shares.mul(accRewardPerShare).div(1e12).sub(userInfo[_user].rewardDebt);
    }

    function getLastDepositTime(address _user) public override view returns (uint256) {
        return userInfo[_user].lastDepositTime;
    }

    function getTokensStaked(address _user) public override view returns (uint256) {
        return userInfo[_user].tokensStaked;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function depositAll() external override {
        deposit(token.balanceOf(msg.sender));
    }

    function deposit(uint256 _amount) public override nonReentrant {
        require(msg.sender == tx.origin, "no contracts");
        _claimReward(msg.sender);

        uint256 _pool = balance();
        uint256 _before = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 _after = token.balanceOf(address(this));
        _amount = _after.sub(_before); // Additional check for deflationary tokens
        uint256 shares = 0;
        if (totalShares == 0) {
            shares = _amount;
        } else {
            shares = (_amount.mul(totalShares)).div(_pool);
        }

        //when farming pools with a deposit fee
        if(depositFee > 0) {
            uint256 fee = shares.mul(depositFee).div(keepMax);
            shares = shares.sub(fee);
        }

        totalShares = totalShares.add(shares);

        UserInfo storage user = userInfo[msg.sender];
        user.shares = user.shares.add(shares);
        user.rewardDebt = user.shares.mul(accRewardPerShare).div(1e12);
        user.lastDepositTime = now;
        user.tokensStaked = user.tokensStaked.add(_amount);

        earn(); 
        emit Deposited(msg.sender, _amount);
    }
 
    function earn() internal {
        uint256 _bal = token.balanceOf(address(this));
        token.safeTransfer(strategy, _bal);
        IStrategy(strategy).deposit();
    }

    // Withdraw all tokens and claim rewards.
    function withdrawAll() external override nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        uint256 _shares = user.shares;
        uint256 r = (balance().mul(_shares)).div(totalShares);

        _claimReward(msg.sender);

        // Check balance
        uint256 b = token.balanceOf(address(this));
        if (b < r) {
            uint256 _withdraw = r.sub(b);
            IStrategy(strategy).withdraw(_withdraw);
            uint256 _after = token.balanceOf(address(this));
            uint256 _diff = _after.sub(b);
            if (_diff < _withdraw) {
                r = b.add(_diff);
            }
        }

        totalShares = totalShares.sub(_shares);

        user.shares = user.shares.sub(_shares);
        user.rewardDebt = user.shares.mul(accRewardPerShare).div(1e12);
        user.tokensStaked = 0;
        // Deduct early withdrawal fee if applicable
        if(user.lastDepositTime.add(withdrawPenaltyTime) >= now) {
            uint256 earlyWithdrawalFee = r.mul(withdrawPenalty).div(keepMax);
            r = r.sub(earlyWithdrawalFee);
            token.safeTransfer(ercFund, earlyWithdrawalFee);
        }

        token.safeTransfer(msg.sender, r);
        emit Withdrawn(msg.sender, r);
    }

    // Withdraw all tokens without caring about rewards in the event that the reward mechanism breaks. 
    // Normal early withdrawal penalties will apply.
    function emergencyWithdraw() public nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        uint256 _shares = user.shares;
        uint256 r = (balance().mul(_shares)).div(totalShares);

        // Check balance
        uint256 b = token.balanceOf(address(this));
        if (b < r) {
            uint256 _withdraw = r.sub(b);
            IStrategy(strategy).withdraw(_withdraw);
            uint256 _after = token.balanceOf(address(this));
            uint256 _diff = _after.sub(b);
            if (_diff < _withdraw) {
                r = b.add(_diff);
            }
        }

        if(_shares <= totalShares) {
            totalShares = totalShares.sub(_shares);
        }
        else {
            totalShares = 0;
        }
        user.shares = 0;
        user.rewardDebt = 0;
        user.tokensStaked = 0;
        // Deduct early withdrawal fee if applicable
        if(user.lastDepositTime.add(withdrawPenaltyTime) >= now) {
            uint256 earlyWithdrawalFee = r.mul(withdrawPenalty).div(keepMax);
            r = r.sub(earlyWithdrawalFee);
            token.safeTransfer(ercFund, earlyWithdrawalFee);
        }

        token.safeTransfer(msg.sender, r);
        emit Withdrawn(msg.sender, r);
    }
    
    function claim() public nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        require(user.shares > 0, "no stake");

        _claimReward(msg.sender);

        user.rewardDebt = user.shares.mul(accRewardPerShare).div(1e12);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    // Handles claiming the user's pending rewards
    function _claimReward(address _user) internal virtual;

    /* ========== RESTRICTED FUNCTIONS ========== */

    //Vault deployer also needs to register the vault with the new minter
    function setMinter(address newMinter) public onlyOwner {
        require(newMinter != address(0));
        minter = IMinter(newMinter);
    }
    
    //Sets a new boost handler
    //Set boost handler to the zero address in order to disable it
    function setBoostHandler(address _handler) public onlyOwner {
        boostHandler = _handler;
    }

    function setWithdrawPenaltyTime(uint256 _withdrawPenaltyTime) public override onlyOwner {
        require(_withdrawPenaltyTime <= 30 days, "delay too high");
        withdrawPenaltyTime = _withdrawPenaltyTime;
    }

    function setWithdrawPenalty(uint256 _withdrawPenalty) public override onlyOwner {
        require(_withdrawPenalty <= 500, "penalty too high");
        withdrawPenalty = _withdrawPenalty;
    }

    function setRewardMultiplier(uint256 _rewardMultiplier) public override onlyOwner {
        require(_rewardMultiplier <= MULTIPLIER_MAX, "multiplier too high");
        rewardMultiplier = _rewardMultiplier;
    }

    //shouldn't be farming things with a high deposit fee in the first place
    function setPoolDepositFee(uint256 _depositFee) public onlyOwner {
        require(_depositFee <= 1000, "?");
        depositFee = _depositFee;
    }

    //Increase the amount of the token sent to the fee dist the vault is allowed to mint ADDY for
    function increaseRewardAllocation(uint256 _newReward) public override onlyOwner {
        rewardAllocation = rewardAllocation.add(_newReward);
        emit RewardAllocated(_newReward, rewardAllocation);
    }

    /* ========== EVENTS ========== */

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardAdded(address reward, uint256 amount);
    event Claimed(address indexed user, uint256 amount);
    event RewardAllocated(uint256 newReward, uint256 totalAllocation);
}
