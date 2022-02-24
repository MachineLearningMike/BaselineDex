// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./interfaces/ICrssToken.sol";
import "../periphery/interfaces/ICrossRouter.sol";
import "../core/interfaces/ICrossFactory.sol";
import "../core/interfaces/ICrossPair.sol";

import "hardhat/console.sol";

// CrssToken with Governance.
contract CrssToken is ICrssToken, OwnableUpgradeable {
    using SafeMath for uint256;

    string private _name;
    string private _symbol;
    uint8 private _decimals;

    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private __totalSupply;
    mapping(address => uint256) private __balances;

    address public override router;
    address public override farm;
    address public override crssBnbPair;

    uint8 constant DECIMALS = 18;
    uint256 public constant override maxSupply = 50 * 1e6 * 10**DECIMALS;
    uint256 public constant override magnifier = 1e4;

    uint256 public override devFeeRate;
    uint256 public override liquidityFeeRate;
    uint256 public override buybackFeeRate;

    uint256 public override maxTransferAmountRate;
    uint256 public maxSwapTransferAmountRate;

    address public override devTo;
    address public override buybackTo;
    address public constant override berryAddress = address(0);

    mapping(address => bool) public knownDexContract;
    mapping(address => bool) public knownPairContract;

    bool private shouldPayFee;

    DexSession private dexSession;

    // Data for Swap and Liquify Functionality

    bool private shouldSwapAndLiquify;

    // Set them private or public???
    // ????????????????????????????????
    uint256 public liquifyThreshold;
    uint256 public liquifyAccumulated;

    // Data for Implement Transaction-Oriented Overview
    // Shoud be private when deploy
    // ?????????????????????????????
    struct TxHistory {
        address account;
        uint256 sent;
        uint256 received;
    }

    TxHistory[] public transfersInOneTx;

    struct SwapHistory {
        address txOrigin;
        uint256 sent;
        uint256 received;
    }
    mapping(address => SwapHistory) public swapTransfersInOneTx;

    //
    address public txOrigin;

    // Data for Delegates

    mapping(address => address) internal __delegates;

    /// @notice A checkpoint for marking number of votes from a given block
    struct Checkpoint {
        uint32 fromBlock;
        uint256 votes;
    }

    /// @notice A record of votes checkpoints for each account, by index
    mapping(address => mapping(uint32 => Checkpoint)) public checkpoints;

    /// @notice The number of checkpoints for each account
    mapping(address => uint32) public numCheckpoints;

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant DELEGATION_TYPEHASH =
        keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    mapping(address => uint256) public nonces;

    /// @notice An event thats emitted when an account changes its delegate
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);

    /// @notice An event thats emitted when a delegate account's vote balance changes
    event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);

    receive() external payable {}

    function initialize(
        address _router,
        address _devTo,
        address _buybackTo,
        uint256 _liquifyThreshold
    ) external initializer {
        require(_msgSender() == ICrossRouter(_router).getOwner(), "Cross: FORBIDDEN");
        __Ownable_init();
        _name = "Crosswise Token";
        _symbol = "CRSS";
        _decimals = 18;
        router = _router;
        devTo = _devTo;
        buybackTo = _buybackTo;

        devFeeRate = 4; // 0.04%
        liquidityFeeRate = 3; // 0.03%
        buybackFeeRate = 3; // 0.03%

        liquifyThreshold = _liquifyThreshold;
        maxTransferAmountRate = 50;
        maxSwapTransferAmountRate = 50;
        shouldPayFee = true;

        knownDexContract[address(0)] = true;
        knownDexContract[address(this)] = true;
        knownDexContract[_router] = true;
        dexSession = DexSession.None;

        // Mint 1e6 Crss to the caller for testing
        __mint(_msgSender(), 1e6 * 10**DECIMALS);
        __moveDelegates(address(0), __delegates[_msgSender()], 1e6 * 10**DECIMALS);
    }

    function getOwner() external view override returns (address) {
        return owner();
    }

    function setRouter(address _router) external override onlyOwner {
        require(_msgSender() == ICrossRouter(_router).getOwner(), "Cross: FORBIDDEN");
        router = _router;
        crssBnbPair = ICrossFactory(ICrossRouter(router).factory()).createPair(
            address(this),
            ICrossRouter(router).WETH()
        );
        knownDexContract[crssBnbPair] = true;
        knownPairContract[crssBnbPair] = true;
    }

    function setFarm(address crssFarm) external override onlyOwner {
        farm = crssFarm;
    }

    function setDevTo(address _devTo) public onlyOwner {
        devTo = _devTo;
    }

    function setBuyBackTo(address _buybackTo) public onlyOwner {
        buybackTo = _buybackTo;
    }

    function setLiquifyThreshold(uint256 _liquifyThreshold) public onlyOwner {
        liquifyThreshold = _liquifyThreshold;
    }

    function setDexSession(DexSession session) public override {
        require(_msgSender() == router || _msgSender() == address(this), "Cross: FORBIDDEN");
        if (dexSession == DexSession.None) {
            dexSession = session;
            shouldPayFee = true;
        } else if (session == DexSession.None) {
            dexSession = session;
            if (shouldSwapAndLiquify) {
                // uint256 startGas = gasleft();
                shouldSwapAndLiquify = false;
                swapAndLiquify();
                // uint256 endGas = gasleft();
                // uint256 gasUsed = (startGas - endGas) * tx.gasprice;
            }
        }
    }

    function setDexSessionInternal(DexSession session) internal {
        if (dexSession == DexSession.None) {
            dexSession = session;
            shouldPayFee = true;
        } else if (session == DexSession.None) {
            dexSession = session;
            if (shouldSwapAndLiquify) {
                // uint256 startGas = gasleft();
                shouldSwapAndLiquify = false;
                swapAndLiquify();
                // uint256 endGas = gasleft();
                // uint256 gasUsed = (startGas - endGas) * tx.gasprice;
            }
        }
    }

    function getFeePer1e10() external view override returns (uint256 feeInner, uint256 feeOuter) {
        uint256 totalFeeRate = devFeeRate + buybackFeeRate + liquidityFeeRate;
        feeInner = totalFeeRate.mul(1e10).div(magnifier);
        feeOuter = totalFeeRate.mul(1e10).div(10000 - (devFeeRate + buybackFeeRate + liquidityFeeRate));
    }

    function setPairContract(address account) external override {
        require(_msgSender() == router, "Cross: FORBIDDEN");
        knownDexContract[account] = true;
        knownPairContract[account] = true;
    }

    function setKnownDexContract(address account, bool status) external override onlyOwner {
        knownDexContract[account] = status;
    }

    function name() public view virtual returns (string memory) {
        return _name;
    }

    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual returns (uint8) {
        return DECIMALS;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return __totalSupply;
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        return __balances[account];
    }

    function mint(address _to, uint256 _amount) public override onlyOwner {
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) public override onlyOwner {
        _burn(_from, _amount);
    }

    function berry(address _from, uint256 _amount) public onlyOwner {
        __transfer(_from, berryAddress, _amount);
        __moveDelegates(__delegates[_from], __delegates[berryAddress], _amount);
    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        _approve(sender, _msgSender(), currentAllowance - amount);

        _transfer(sender, recipient, amount); // No guarentee it doesn't make a change to _allowances. Revert if it fails.

        return true;
    }

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        return true;
    }

    function _mint(address to, uint256 amount) internal virtual {
        require(__totalSupply + amount <= maxSupply, "ERC20: Exceed Max Supply");
        require(_msgSender() == farm, "Cross: FORBIDDEN");
        __mint(to, amount);
        __moveDelegates(address(0), __delegates[to], amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
        __burn(account, amount);
        __moveDelegates(__delegates[account], __delegates[address(0)], amount);
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        setDexSessionInternal(DexSession.Transfer);
        _checkTxWideTransferAmount(sender, recipient, amount);
        _checkTxWideSwapTransferAmount(sender, recipient, amount);
        if (shouldPayFee && !(knownDexContract[sender] && knownDexContract[recipient])) {
            amount -= _payFees(sender, amount);
            shouldPayFee = false;
        }

        __transfer(sender, recipient, amount);
        __moveDelegates(__delegates[sender], __delegates[recipient], amount);

        if (dexSession == DexSession.Transfer) {
            setDexSessionInternal(DexSession.None);
        }
    }

    function _checkTxWideTransferAmount(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        // Check the transaction-wide, accumulated transfer amount, rather than call-wide transfer amount.
        uint256 _maxTransferAmount = __totalSupply.mul(maxTransferAmountRate).div(magnifier);
        if (sender == owner() || recipient == owner()) {} else if (tx.origin == txOrigin) {
            for (uint256 i = 0; i < transfersInOneTx.length; i++) {
                if (transfersInOneTx[i].account == sender) {
                    transfersInOneTx[i].sent += amount;
                    require(transfersInOneTx[i].sent < _maxTransferAmount, "CrssToken: Exceed MaxTransferAmount");
                } else if (transfersInOneTx[i].account == recipient) {
                    transfersInOneTx[i].received += amount;
                    require(transfersInOneTx[i].received < _maxTransferAmount, "CrssToken: Exceed MaxTransferAmount");
                } else {
                    transfersInOneTx.push(TxHistory(sender, amount, 0));
                    transfersInOneTx.push(TxHistory(recipient, 0, amount));
                    require(amount < _maxTransferAmount, "CrssToken: Exceed MaxTransferAmount");
                }
            }
        } else {
            txOrigin = tx.origin;
            for (uint256 i = 0; i < transfersInOneTx.length; i++) {
                delete transfersInOneTx[i];
            }
            transfersInOneTx.push(TxHistory(sender, amount, 0));
            transfersInOneTx.push(TxHistory(recipient, 0, amount));
            require(amount < _maxTransferAmount, "CrssToken: Exceed MaxTransferAmount");
        }
    }

    function _checkTxWideSwapTransferAmount(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        if (dexSession != DexSession.Swap) {
            return;
        }
        if (knownPairContract[sender]) {
            uint256 crssReserve = ICrossPair(sender).getCrssReserve(address(this));
            uint256 _maxTransferAmount = crssReserve.mul(maxSwapTransferAmountRate).div(magnifier);
            if (tx.origin != swapTransfersInOneTx[sender].txOrigin) {
                swapTransfersInOneTx[sender].txOrigin = tx.origin;
                swapTransfersInOneTx[sender].sent = 0;
                swapTransfersInOneTx[sender].received = 0;
            }
            swapTransfersInOneTx[sender].sent += amount;
            require(swapTransfersInOneTx[sender].sent < _maxTransferAmount, "Cross: Exceed Swap Amount");
        }
        if (knownPairContract[recipient]) {
            uint256 crssReserve = ICrossPair(recipient).getCrssReserve(address(this));
            uint256 _maxTransferAmount = crssReserve.mul(maxSwapTransferAmountRate).div(magnifier);
            if (tx.origin != swapTransfersInOneTx[recipient].txOrigin) {
                swapTransfersInOneTx[recipient].txOrigin = tx.origin;
                swapTransfersInOneTx[recipient].sent = 0;
                swapTransfersInOneTx[recipient].received = 0;
            }
            swapTransfersInOneTx[recipient].received += amount;
            require(swapTransfersInOneTx[recipient].received < _maxTransferAmount, "Cross: Exceed Swap Amount");
        }
    }

    function _payFees(address sender, uint256 amount) internal virtual returns (uint256 fees) {
        uint256 devFee = amount.mul(devFeeRate).div(10000);
        uint256 buybackFee = amount.mul(buybackFeeRate).div(10000);
        uint256 liquidityFee = amount.mul(liquidityFeeRate).div(10000);

        __transfer(sender, devTo, devFee);
        __moveDelegates(__delegates[sender], __delegates[devTo], devFee);

        __transfer(sender, buybackTo, buybackFee);
        __moveDelegates(__delegates[sender], __delegates[buybackTo], buybackFee);

        __transfer(sender, address(this), liquidityFee);
        __moveDelegates(__delegates[sender], __delegates[address(this)], liquidityFee);

        liquifyAccumulated += liquidityFee;
        if (liquifyAccumulated > liquifyThreshold) {
            shouldSwapAndLiquify = true;
        }
        fees = devFee + buybackFee + liquidityFee;
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function __mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        __beforeTokenTransfer(address(0), account, amount);
        __totalSupply += amount;
        __balances[account] += amount;
        __afterTokenTransfer(address(0), account, amount);

        emit Transfer(address(0), account, amount);
    }

    function __burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");
        uint256 accountBalance = __balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");

        __beforeTokenTransfer(account, address(0), amount);
        __balances[account] = accountBalance - amount;
        __totalSupply -= amount;
        __afterTokenTransfer(account, address(0), amount);

        emit Transfer(account, address(0), amount);
    }

    function __transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        uint256 senderBalance = __balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");

        __beforeTokenTransfer(sender, recipient, amount);
        __balances[sender] = senderBalance - amount;
        __balances[recipient] += amount;
        __afterTokenTransfer(sender, recipient, amount);

        emit Transfer(sender, recipient, amount);
    }

    function __beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}

    function __afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}

    function swapAndLiquify() private {
        uint256 contractTokenBalance = balanceOf(address(this));
        // split the contract balance into halves
        uint256 _maxTransferAmount = maxTransferAmount();
        contractTokenBalance = contractTokenBalance > _maxTransferAmount ? _maxTransferAmount : contractTokenBalance;

        uint256 half = contractTokenBalance.div(2);
        uint256 otherHalf = contractTokenBalance.sub(half);

        // liquifyAccumulated reduced by half, to prevent continuous liquify action
        liquifyAccumulated -= half;

        // capture the contract's current ETH balance.
        // this is so that we can capture exactly the amount of ETH that the
        // swap creates, and not make the liquidity event include any ETH that
        // has been manually sent to the contract
        uint256 initialBalance = address(this).balance;
        // swap tokens for ETH
        swapTokensForETH(half); // <- this breaks the ETH -> HATE swap when swap+liquify is triggered

        // how much ETH did we just swap into?
        uint256 newBalance = address(this).balance.sub(initialBalance);

        // Finally Set liquifyAccumulated
        liquifyAccumulated = __balances[address(this)];
        // add liquidity to uniswap
        addLiquidity(otherHalf, newBalance);
    }

    function swapTokensForETH(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> WBNB
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = ICrossRouter(router).WETH();

        address crss = address(this);
        _approve(address(this), address(router), tokenAmount);

        // make the swap
        ICrossRouter(router).swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            crss,
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(router), tokenAmount);

        // add the liquidity
        (, , uint256 liquidity) = ICrossRouter(router).addLiquidityETHSupportingFeeOnTransferTokens{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(this),
            block.timestamp
        );

        require(liquidity > 0, "Add liquidity failed");
    }

    function maxTransferAmount() public view returns (uint256) {
        return __totalSupply.mul(maxTransferAmountRate).div(magnifier);
    }

    function __delegate(address delegator, address delegatee) internal {
        address currentDelegate = __delegates[delegator];
        uint256 delegatorBalance = balanceOf(delegator); // balance of underlying CRSSs (not scaled);
        __delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        __moveDelegates(currentDelegate, delegatee, delegatorBalance);
    }

    function delegates(address delegator) external view returns (address) {
        return __delegates[delegator];
    }

    function delegate(address delegatee) external {
        return __delegate(_msgSender(), delegatee);
    }

    function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        bytes32 domainSeparator = keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name())), getChainId(), address(this))
        );

        bytes32 structHash = keccak256(abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, expiry));

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "CRSS::delegateBySig: invalid signature");
        require(nonce == nonces[signatory]++, "CRSS::delegateBySig: invalid nonce");
        require(block.timestamp <= expiry, "CRSS::delegateBySig: signature expired");
        return __delegate(signatory, delegatee);
    }

    function getCurrentVotes(address account) external view returns (uint256) {
        uint32 nCheckpoints = numCheckpoints[account];
        return nCheckpoints > 0 ? checkpoints[account][nCheckpoints - 1].votes : 0;
    }

    function getPriorVotes(address account, uint256 blockNumber) external view returns (uint256) {
        require(blockNumber < block.number, "CRSS::getPriorVotes: not yet determined");

        uint32 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance
        if (checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return checkpoints[account][nCheckpoints - 1].votes;
        }

        // Next check implicit zero balance
        if (checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }

        uint32 lower = 0;
        uint32 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint32 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoint memory cp = checkpoints[account][center];
            if (cp.fromBlock == blockNumber) {
                return cp.votes;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return checkpoints[account][lower].votes;
    }

    function safe32(uint256 n, string memory errorMessage) internal pure returns (uint32) {
        require(n < 2**32, errorMessage);
        return uint32(n);
    }

    function getChainId() internal view returns (uint256) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        return chainId;
    }

    function __moveDelegates(
        address srcRep,
        address dstRep,
        uint256 amount
    ) internal {
        if (srcRep != dstRep && amount > 0) {
            if (srcRep != address(0)) {
                // decrease old representative
                uint32 srcRepNum = numCheckpoints[srcRep];
                uint256 srcRepOld = srcRepNum > 0 ? checkpoints[srcRep][srcRepNum - 1].votes : 0;
                uint256 srcRepNew = srcRepOld.sub(amount);
                __writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                // increase new representative
                uint32 dstRepNum = numCheckpoints[dstRep];
                uint256 dstRepOld = dstRepNum > 0 ? checkpoints[dstRep][dstRepNum - 1].votes : 0;
                uint256 dstRepNew = dstRepOld.add(amount);
                __writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
            }
        }
    }

    function __writeCheckpoint(
        address delegatee,
        uint32 nCheckpoints,
        uint256 oldVotes,
        uint256 newVotes
    ) internal {
        uint32 blockNumber = safe32(block.number, "CRSS::__writeCheckpoint: block number exceeds 32 bits");

        if (nCheckpoints > 0 && checkpoints[delegatee][nCheckpoints - 1].fromBlock == blockNumber) {
            checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
        } else {
            checkpoints[delegatee][nCheckpoints] = Checkpoint(blockNumber, newVotes);
            numCheckpoints[delegatee] = nCheckpoints + 1;
        }

        emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }
}
