// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "../CrssToken.sol";

interface ICrssToken is IERC20Upgradeable {
    enum DexSession { None, Swap, AddLiquidity, RemoveLiquidity } 
    
    function getOwner() external view returns (address);
    
    // function router() external view returns (address);
    
    // function farm() external view returns (address);
  
    // function crssBNBPair() external view returns (address);

    // function maxSupply() external view returns (uint256);

    // function magnifier() external view returns (uint256);

    // function liquidityFee() external view returns (uint256);

    // function devFee() external view returns (uint256);

    // function buyBackFee() external view returns (uint256);

    // function maxTransferAmountRate() external view returns (uint256);

    // function devTo() external view returns (address);

    // function buybackTo() external view returns (address);

    // function berryAddress() external view returns (address);

    // function freeAntiWhaleList(address account) external view returns (bool);

    function setRouter(address router) external;

    function setFarm(address crssFarm) external;

    function mint(address _to, uint256 _amount) external;

    function burn(address _from, uint256 _amount) external;

    function setDexSession( DexSession session ) external;

    function setKnownDexContract(address account, bool status) external;

    function getFeePer1e10() external view returns (uint256 feeRateInner, uint256 feeRateOuter);

}
