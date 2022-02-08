// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./interfaces/IXCrssToken.sol";
import "../libraries/utils/UpgradableOwnable.sol";
import "./xCrssToken.sol";

// xCrssToken with Governance.
contract xCrssToken2 is xCrssToken {
    function getVersion() external pure returns (string memory) {
        return "VERSION 2";
    }
}
