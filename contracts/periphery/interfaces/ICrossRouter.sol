// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IPancakeRouter02.sol";

interface ICrossRouter is IPancakeRouter02 {
    function setCrssContract(address _crssContract) external;

    function getOwner() external view returns (address);
}
