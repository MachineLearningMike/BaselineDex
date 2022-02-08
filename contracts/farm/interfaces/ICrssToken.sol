// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

interface ICrssToken is IERC20Upgradeable {
    function getOwner() external view returns (address);

    function setRouter(address router) external;

    function setFarm(address crssFarm) external;

    function mint(address _to, uint256 _amount) external;
}
