// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
// import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/ICrossFarm.sol";
import "./interfaces/ICrssToken.sol";
import "./interfaces/IXCrssToken.sol";
import "./interfaces/ICrssReferral.sol";
import "./interfaces/IMigratorChef.sol";
import "../core/interfaces/ICrossPair.sol";
import "../periphery/interfaces/ICrossRouter.sol";

import "hardhat/console.sol";

// MasterChef is the master of Crss. He can make Crss and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once CRSS is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract CrossFarm is ICrossFarm, OwnableUpgradeable {
    using SafeMath for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // CrssToken Vest
    struct CrssVest {
        uint256 totalAmount;
        uint256 withdrawAmount;
        uint256 lastWithdraw;
    }

    uint256 month = 30 days;
    uint256 public constant unlockPerMonth = 2000;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        bool isAuto;
        bool isVest;
        CrssVest[] vestList;
        //
        // We do some fancy math here. Basically, any point in time, the amount of CRSSs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accCrssPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accCrssPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20Upgradeable lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. CRSSs to distribute per block.
        uint256 lastRewardBlock; // Last block number that CRSSs distribution occurs.
        uint256 accCrssPerShare; // Accumulated CRSSs per share, times 1e12. See below.
    }

    // The CRSS TOKEN!
    address public crss;
    // The XCRSS TOKEN!
    address public xcrss;
    // Dev address.
    address public devaddr;
    // Router address.
    address public router;
    // CRSS tokens created per block.
    uint256 public crssPerBlock;
    // Bonus muliplier for early crss makers.
    uint256 public BONUS_MULTIPLIER;
    // The migrator contract. It has a lot of power. Can only be set through governance (owner).
    IMigratorChef public migrator;
    // Burn Address
    address public constant burnAddr = 0x0000000000000000000000000000000000000000;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;
    // The block number when CRSS mining starts.
    uint256 public startBlock;

    // Crss referral contract address.
    address public crssReferral;

    // Referral commission rate in basis points.
    uint256 public referralCommissionRate = 100;
    // Max referral commission rate: 10%.
    uint256 public constant MAXIMUM_REFERRAL_COMMISSION_RATE = 1000;

    // Magnifier
    uint256 private magnifier = 10000;
    // Auto Compounding Fee Rate
    uint256 private autoFeeRate = 500;
    // Auto Compounding Burn Rate
    uint256 private autoBurnRate = 2500;
    // Router Action Deadline
    uint256 public constant routerDeadlineDuration = 300;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetcrssReferral(address indexed crssReferral);
    event SetReferralCommissionRate(uint256 referralCommissionRate);
    event ReferralCommissionPaid(address indexed user, address indexed referrer, uint256 commissionAmount);

    function initialize(
        address _crss,
        address _devaddr,
        address _router,
        uint256 _crssPerBlock,
        uint256 _startBlock
    ) external initializer {
        require(msg.sender == ICrssToken(_crss).getOwner(), "Cross: FORBIDDEN");
        __Ownable_init();

        crss = _crss;
        router = _router;
        devaddr = _devaddr;
        crssPerBlock = _crssPerBlock;
        startBlock = _startBlock;

        // staking pool
        // poolInfo.push(PoolInfo({lpToken: _crss, allocPoint: 1000, lastRewardBlock: startBlock, accCrssPerShare: 0}));
        BONUS_MULTIPLIER = 1;
        totalAllocPoint = 1000;
    }

    function setXCrss(address _xcrss) external override onlyOwner {
        require(msg.sender == IXCrssToken(_xcrss).getOwner(), "Cross: FORBIDDEN");
        xcrss = _xcrss;
    }

    function updateMultiplier(uint256 multiplierNumber) public override onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber;
    }

    function poolLength() external view override returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(
        uint256 _allocPoint,
        IERC20Upgradeable _lpToken,
        bool _withUpdate
    ) public override onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({lpToken: _lpToken, allocPoint: _allocPoint, lastRewardBlock: lastRewardBlock, accCrssPerShare: 0})
        );
        updateStakingPool();
    }

    // Update the given pool's CRSS allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public override onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        if (prevAllocPoint != _allocPoint) {
            totalAllocPoint = totalAllocPoint.sub(prevAllocPoint).add(_allocPoint);
            updateStakingPool();
        }
    }

    function updateStakingPool() internal {
        uint256 length = poolInfo.length;
        uint256 points = 0;
        for (uint256 pid = 1; pid < length; ++pid) {
            points = points.add(poolInfo[pid].allocPoint);
        }
        if (points != 0) {
            points = points.div(3);
            totalAllocPoint = totalAllocPoint.sub(poolInfo[0].allocPoint).add(points);
            poolInfo[0].allocPoint = points;
        }
    }

    // Set the migrator contract. Can only be called by the owner.
    function setMigrator(IMigratorChef _migrator) public override onlyOwner {
        migrator = _migrator;
    }

    // Migrate lp token to another lp contract. Can be called by anyone. We trust that migrator contract is good.
    function migrate(uint256 _pid) public override {
        require(address(migrator) != address(0), "migrate: no migrator");
        PoolInfo storage pool = poolInfo[_pid];
        IERC20Upgradeable lpToken = pool.lpToken;
        uint256 bal = lpToken.balanceOf(address(this));
        lpToken.safeApprove(address(migrator), bal);
        IERC20Upgradeable newLpToken = migrator.migrate(lpToken);
        require(bal == newLpToken.balanceOf(address(this)), "migrate: bad");
        pool.lpToken = newLpToken;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view override returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // View function to see pending CRSSs on frontend.
    function pendingCrss(uint256 _pid, address _user) external view override returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accCrssPerShare = pool.accCrssPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 crssReward = multiplier.mul(crssPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accCrssPerShare = accCrssPerShare.add(crssReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accCrssPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public override {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            _updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function _updatePool(uint256 _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 crssReward = multiplier.mul(crssPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        ICrssToken(crss).mint(devaddr, crssReward.div(10));
        ICrssToken(crss).mint(xcrss, crssReward);
        pool.accCrssPerShare = pool.accCrssPerShare.add(crssReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Calculate Reward from staking, and send it if non-auto compounding, or append it to staking if auto
    function _handleReward(uint256 _pid, bool isAuto) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        if (user.amount > 0) {
            // Calculate Reward from staking after the last update
            uint256 pending = user.amount.mul(pool.accCrssPerShare).div(1e12).sub(user.rewardDebt);
            if (pending > 0) {
                if (user.isVest) {
                    // Divide reward into 2, send half to vest
                    uint256 vestReward = pending.div(2);
                    CrssVest memory newVest;
                    newVest.totalAmount = vestReward;
                    newVest.withdrawAmount = 0;
                    newVest.lastWithdraw = block.timestamp;
                    user.vestList.push(newVest);
                    pending -= vestReward;
                } else {
                    // Burn speicifc amount of Reward for Deflationary strategy
                    uint256 burnReward = pending.mul(autoBurnRate).div(magnifier);
                    safeCrssTransfer(burnAddr, burnReward);
                    // Calculate Fee for autoCompounding
                    uint256 autoFee = pending.mul(autoFeeRate).div(magnifier);
                    safeCrssTransfer(devaddr, autoFee);
                    // Reestimate pending amount decreased by burnReward + autoFee
                    pending = pending - burnReward - autoFee;
                }

                // Send Referral Amount to referrer
                payReferralCommission(msg.sender, pending);

                if (!isAuto) {
                    // if user does not take part in auto compounding, send the reward and make it end
                    safeCrssTransfer(msg.sender, pending);
                    return;
                } else {
                    // Approve Crss token to router for swap and add liquidity
                    ICrssToken(crss).approve(address(router), pending);

                    // Get Pair Contract and Swap Crss to pair tokens and Add Liquidity
                    ICrossPair pair = ICrossPair(address(pool.lpToken));

                    // Get Token addresses of Pair
                    address token0 = pair.token0();
                    address token1 = pair.token1();
                    uint256 token0Amt = pending.div(2);
                    uint256 token1Amt = pending - token0Amt;
                    if (crss != token0) {
                        // Swap half earned to token0
                        uint256 _token0Amt = IERC20Upgradeable(token0).balanceOf(address(this));
                        swapTokenForToken(crss, token0, token0Amt);
                        token0Amt = IERC20Upgradeable(token0).balanceOf(address(this)) - _token0Amt;
                    }
                    if (crss != token1) {
                        // Swap half earned to token1
                        uint256 _token1Amt = IERC20Upgradeable(token0).balanceOf(address(this));
                        swapTokenForToken(crss, token1, token1Amt);
                        token1Amt = IERC20Upgradeable(token1).balanceOf(address(this)) - _token1Amt;
                    }
                    // Add Liquidity
                    if (token0Amt > 0 && token1Amt > 0) {
                        IERC20Upgradeable(token0).safeIncreaseAllowance(router, token0Amt);
                        IERC20Upgradeable(token1).safeIncreaseAllowance(router, token1Amt);
                        uint256 oldBalance = pool.lpToken.balanceOf(address(this));
                        ICrossRouter(router).addLiquidity(
                            token0,
                            token1,
                            token0Amt,
                            token1Amt,
                            0,
                            0,
                            address(this),
                            block.timestamp + routerDeadlineDuration
                        );
                        {
                            // Calculate newly accumulated LP amount and return it
                            uint256 newBalance = pool.lpToken.balanceOf(address(this));
                            user.amount += newBalance.sub(oldBalance);
                        }
                    }
                }
            }
        }
    }

    // Deposit LP tokens to MasterChef for CRSS allocation.
    function _deposit(uint256 _pid, uint256 _amount) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(msg.sender, address(this), _amount);
            user.amount = user.amount.add(_amount);
        }

        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function _withdraw(uint256 _pid, uint256 _amount) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(msg.sender, _amount);
        }

        emit Withdraw(msg.sender, _pid, _amount);
    }

    function updatePool(uint256 _pid) public override {
        _updatePool(_pid);
    }

    // Deposit LP tokens to MasterChef for CRSS allocation.
    function deposit(
        uint256 _pid,
        uint256 _amount,
        bool _isAuto,
        address _referrer,
        bool _isVest
    ) public override {
        require(_pid != 0, "deposit CRSS by staking");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        if (user.amount > 0) {
            require(user.isAuto == _isAuto, "Cannot change auto compound in progress");
        }
        // User can not change Auto and Vest state while staking
        if (user.amount > 0) {
            require(user.isAuto == _isAuto, "Cannot change auto compound in progress");
            require(user.isVest == _isVest, "Cannot change vesting option in progress");
        }

        // Announce to CrssToken that it has entered Stake Session, all transfers are for staking
        ICrssToken(crss).setDexSession(ICrssToken.DexSession.Stake);

        _updatePool(_pid);

        if (_amount > 0 && crssReferral != address(0) && _referrer != address(0) && _referrer != msg.sender) {
            ICrssReferral(crssReferral).recordReferral(msg.sender, _referrer);
        }

        // Get the newly minted LP amount from auto compound: 0 for non-auto account
        _handleReward(_pid, _isAuto);
        _deposit(_pid, _amount);

        // Update user's rewardDebt, and isAuto state
        user.rewardDebt = user.amount.mul(pool.accCrssPerShare).div(1e12);
        user.isAuto = _isAuto;
        user.isVest = _isVest;
        // Announce to CrssToken that Staking has ended
        ICrssToken(crss).setDexSession(ICrssToken.DexSession.None);
    }

    // Turn Staking Reward to Auto Compound
    function earn(uint256 _pid) public override {
        require(_pid != 0, "deposit CRSS by staking");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        // Announce to CrssToken that it has entered Stake Session, all transfers are for staking
        ICrssToken(crss).setDexSession(ICrssToken.DexSession.Stake);

        _updatePool(_pid);

        // Handle reward from staking: 1. Send to user when he is a non-auto user, 2. Turn it into LP and compound it to current pool
        _handleReward(_pid, true);
        _deposit(_pid, 0);

        // Update user's rewardDebt
        user.rewardDebt = user.amount.mul(pool.accCrssPerShare).div(1e12);

        // Announce to CrssToken that Staking has ended
        ICrssToken(crss).setDexSession(ICrssToken.DexSession.None);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public override {
        require(_pid != 0, "withdraw CRSS by unstaking");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        // Announce to CrssToken that it has entered Stake Session, all transfers are for staking
        ICrssToken(crss).setDexSession(ICrssToken.DexSession.Stake);

        _updatePool(_pid);

        // Handle reward from staking: 1. Send to user when he is a non-auto user, 2. Turn it into LP and compound it to current pool
        _handleReward(_pid, user.isAuto);
        _withdraw(_pid, _amount);

        // Update user's rewardDebt, and isAuto state
        user.rewardDebt = user.amount.mul(pool.accCrssPerShare).div(1e12);
        user.isAuto = false;

        // Announce to CrssToken that Staking has ended
        ICrssToken(crss).setDexSession(ICrssToken.DexSession.None);
    }

    // Withdraw Vested Crss
    function withdrawVest(uint256 _amount) public override {
        CrssVest[] storage vestList = userInfo[0][msg.sender].vestList;

        for (uint256 i = 0; i < vestList.length; i++) {
            // if requested amount is less than zero, stop executing loop
            if (_amount <= 0) {
                return;
            }
            // Calculate elapsed time
            uint256 elapsed = block.timestamp - vestList[i].lastWithdraw;
            // Calculate how many months elapsed
            uint256 monthElapsed = elapsed / month >= 5 ? 5 : elapsed / month;
            // Calculate how much can be withdrawn according to it vesting period and elapsed period
            uint256 unlockAmount = vestList[i].totalAmount.mul(unlockPerMonth).mul(monthElapsed).div(magnifier) -
                vestList[i].withdrawAmount;
            if (unlockAmount > _amount) {
                // if unlockAmount is bigger than requested amount, the requested one can be compensated at all
                vestList[i].withdrawAmount += _amount;
                _amount = 0;
            } else {
                // update withdrawAmount in the vest list
                vestList[i].withdrawAmount += unlockAmount;
                _amount -= unlockAmount;
            }

            // if all the vested Crss are withdrawn in Current record, delete it
            if (vestList[i].withdrawAmount == vestList[i].totalAmount) {
                delete vestList[i];
                i--;
            }
        }

        // If _amount is not equal to zero, which means the total withdrawable amount is smaller than requested amount, revert it
        require(_amount == 0, "Cross: Requested amount exceeds the withdrawable amount");
    }

    // Stake CRSS tokens to MasterChef
    function enterStaking(uint256 _amount) public override {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        _updatePool(0);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accCrssPerShare).div(1e12).sub(user.rewardDebt);
            if (pending > 0) {
                safeCrssTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
            user.isAuto = false;
            user.isVest = false;
        }
        user.rewardDebt = user.amount.mul(pool.accCrssPerShare).div(1e12);

        IXCrssToken(xcrss).mint(msg.sender, _amount);
        emit Deposit(msg.sender, 0, _amount);
    }

    // Withdraw CRSS tokens from STAKING.
    function leaveStaking(uint256 _amount) public override {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        _updatePool(0);
        uint256 pending = user.amount.mul(pool.accCrssPerShare).div(1e12).sub(user.rewardDebt);
        if (pending > 0) {
            safeCrssTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accCrssPerShare).div(1e12);

        IXCrssToken(xcrss).burn(msg.sender, _amount);
        emit Withdraw(msg.sender, 0, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public override {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
        user.isAuto = false;
    }

    // Pay referral commission to the referrer who referred this user.
    function payReferralCommission(address _user, uint256 _pending) internal {
        if (crssReferral != address(0) && referralCommissionRate > 0) {
            address referrer = ICrssReferral(crssReferral).getReferrer(_user);
            uint256 commissionAmount = _pending.mul(referralCommissionRate).div(10000);

            if (referrer != address(0) && commissionAmount > 0) {
                ICrssToken(crss).mint(referrer, commissionAmount);
                ICrssReferral(crssReferral).recordReferralCommission(referrer, commissionAmount);
                emit ReferralCommissionPaid(_user, referrer, commissionAmount);
            }
        }
    }

    // Update referral commission rate by the owner
    function setReferralCommissionRate(uint256 _referralCommissionRate) external onlyOwner {
        require(
            _referralCommissionRate <= MAXIMUM_REFERRAL_COMMISSION_RATE,
            "setReferralCommissionRate: invalid referral commission rate basis points"
        );
        referralCommissionRate = _referralCommissionRate;
        emit SetReferralCommissionRate(_referralCommissionRate);
    }

    // Safe crss transfer function, just in case if rounding error causes pool to not have enough CRSSs.
    function safeCrssTransfer(address _to, uint256 _amount) internal {
        IXCrssToken(xcrss).safeCrssTransfer(_to, _amount);
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public override {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
    }

    function swapTokenForToken(
        address token0,
        address token1,
        uint256 amount
    ) internal {
        address[] memory path = new address[](2);
        path[0] = token0;
        path[1] = token1;
        ICrossRouter(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amount,
            0,
            path,
            address(this),
            block.timestamp + routerDeadlineDuration
        );
    }
}
