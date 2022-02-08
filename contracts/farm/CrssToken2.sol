// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./interfaces/ICrssToken.sol";
import "../periphery/interfaces/ICrossRouter.sol";
import "./CrssToken.sol";

import "hardhat/console.sol";

// CrssToken with Governance.
contract CrssToken2 is CrssToken {
    function getVersion() external pure returns (string memory) {
        return "VERSION 2";
    }
}
