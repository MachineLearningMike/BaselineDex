// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
// import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/ICrossFarm.sol";
import "./interfaces/ICrssToken.sol";
import "./interfaces/IMigratorChef.sol";
import "./CrossFarm.sol";

import "hardhat/console.sol";

// import "@nomiclabs/buidler/console.sol";

// MasterChef is the master of Crss. He can make Crss and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once CRSS is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract CrossFarm2 is CrossFarm {
    function getVersion() external pure returns (string memory) {
        return "VERSION 2";
    }
}
