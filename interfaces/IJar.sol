pragma solidity ^0.6.12;

//A Jar is a contract that users deposit funds into.
//Jar contracts are paired with a strategy contract that interacts with the pool being farmed.
interface IJar {
    function token() external view returns (address);

    function getRatio() external view returns (uint256);

    function balance() external view returns (uint256);

    function balanceOf(address _user) external view returns (uint256);

    function depositAll() external;

    function deposit(uint256) external;

    //function depositFor(address user, uint256 amount) external;

    function withdrawAll() external;

    //function withdraw(uint256) external;

    function earn() external;

    function strategy() external view returns (address);

    //function decimals() external view returns (uint8);

    //function getLastTimeRestaked(address _address) external view returns (uint256);

    //function notifyReward(address _reward, uint256 _amount) external;

    //function getPendingReward(address _user) external view returns (uint256);
}