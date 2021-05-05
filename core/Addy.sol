pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Addy is ERC20, Ownable {
    
    constructor() public ERC20('Adamant', 'ADDY') {
        _mint(msg.sender, 1 * 10**18);
    }

    function mint(address recipient_, uint256 amount_)
        public
        onlyOwner
        returns (bool)
    {
        uint256 balanceBefore = balanceOf(recipient_);
        _mint(recipient_, amount_);
        uint256 balanceAfter = balanceOf(recipient_);

        return balanceAfter > balanceBefore;
    }

    function transfer(address recipient, uint256 amount) public override returns (bool)
    {
        require(recipient != address(this));
        return super.transfer(recipient, amount);
    }
}
