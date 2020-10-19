// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "./interfaces/ILPERC20.sol";
import "./SnpToken.sol";

contract SnpMaster is Ownable, Pausable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 depositTime; // time of deposit LP token
        string refAddress; //refer address
    }

    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool.
        uint256 lpSupply; // lp supply of LP pool.
        uint256 lastRewardBlock; // Last block number that SNP distribution occurs.
        uint256 accSnpPerShare; // Accumulated SNPs per share, times 1e12. See below.
        uint256 lockPeriod; // lock period of  LP pool
        uint256 unlockPeriod; // unlock period of  LP pool
        bool emergencyEnable; // pool withdraw emergency enable
    }

    // governance address
    address public governance;
    // seele ecosystem address
    address public seeleEcosystem;
    // The SNP TOKEN!
    SnpToken public snptoken;

    // SNP tokens created per block.
    uint256 public snpPerBlock;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when snp mining starts.
    uint256 public startBlock;
    // The block number when snp mining ends.
    uint256 public endBlock;
    // mint end block num,about 5 years.
    uint256 public constant MINTEND_BLOCKNUM = 11262857;

    // Total mint reward.
    uint256 public totalMintReward = 0;
    // Total lp supply with rate.
    uint256 public totallpSupply = 0;

    uint256 public constant farmrate = 51;
    uint256 public constant ecosystemrate = 49;

    event Deposit(
        address indexed user,
        uint256 indexed pid,
        uint256 amount,
        string indexed refAddress
    );
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    constructor(
        SnpToken _snp,
        uint256 _snpPerBlock,
        uint256 _startBlock
    ) public {
        snptoken = _snp;
        snpPerBlock = _snpPerBlock;
        startBlock = _startBlock;
        governance = msg.sender;
        seeleEcosystem = msg.sender;
        endBlock = _startBlock.add(MINTEND_BLOCKNUM);
    }

    function setGovernance(address _governance) public {
        require(msg.sender == governance, "snpmaster:!governance");
        governance = _governance;
    }

    function setSeeleEcosystem(address _seeleEcosystem) public {
        require(msg.sender == seeleEcosystem, "snpmaster:!seeleEcosystem");
        seeleEcosystem = _seeleEcosystem;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock
            ? block.number
            : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                lpSupply: 0,
                accSnpPerShare: 0,
                lockPeriod: 0,
                unlockPeriod: 0,
                emergencyEnable: false
            })
        );
    }

    // Update the given pool's lock period and unlock period.
    function setPoolLockTime(
        uint256 _pid,
        uint256 _lockPeriod,
        uint256 _unlockPeriod
    ) public onlyOwner {
        poolInfo[_pid].lockPeriod = _lockPeriod;
        poolInfo[_pid].unlockPeriod = _unlockPeriod;
    }

    // Update the given pool's withdraw emergency Enable.
    function setPoolEmergencyEnable(uint256 _pid, bool _emergencyEnable)
        public
        onlyOwner
    {
        poolInfo[_pid].emergencyEnable = _emergencyEnable;
    }

    // Update end mint block.
    function setEndMintBlock(uint256 _endBlock) public onlyOwner {
        endBlock = _endBlock;
    }

    // Update the given pool's SNP allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );

        PoolInfo storage pool = poolInfo[_pid];
        if (pool.lpSupply > 0) {
            uint256 lpDec = ILPERC20(address(pool.lpToken)).decimals();
            uint256 lpSupply = pool
                .lpSupply
                .mul(pool.allocPoint)
                .mul(1e18)
                .div(100)
                .div(10**lpDec);
            totallpSupply = totallpSupply.sub(lpSupply);

            lpSupply = pool.lpSupply.mul(_allocPoint).mul(1e18).div(100).div(
                10**lpDec
            );
            totallpSupply = totallpSupply.add(lpSupply);
        }

        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpSupply;
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        uint256 lpDec = ILPERC20(address(pool.lpToken)).decimals();
        uint256 lpSupply1e18 = lpSupply.mul(1e18).div(10**lpDec);

        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 snpmint = multiplier
            .mul(snpPerBlock)
            .mul(pool.allocPoint)
            .mul(lpSupply1e18)
            .div(100)
            .div(totallpSupply);

        snptoken.mint(seeleEcosystem, snpmint.mul(ecosystemrate).div(100));

        uint256 snpReward = snpmint.mul(farmrate).div(100);
        snpReward = snptoken.mint(address(this), snpReward);

        totalMintReward = totalMintReward.add(snpReward);

        pool.accSnpPerShare = pool.accSnpPerShare.add(
            snpReward.mul(1e12).div(lpSupply)
        );
        pool.lastRewardBlock = block.number;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to)
        public
        view
        returns (uint256)
    {
        uint256 toFinal = _to > endBlock ? endBlock : _to;
        if (_from >= endBlock) {
            return 0;
        }
        return toFinal.sub(_from);
    }

    // View function to see pending SNPs on frontend.
    function pendingSnp(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accSnpPerShare = pool.accSnpPerShare;
        uint256 lpSupply = pool.lpSupply;
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 lpDec = ILPERC20(address(pool.lpToken)).decimals();
            uint256 lpSupply1e18 = lpSupply.mul(1e18).div(10**lpDec);

            uint256 multiplier = getMultiplier(
                pool.lastRewardBlock,
                block.number
            );
            uint256 snpmint = multiplier
                .mul(snpPerBlock)
                .mul(pool.allocPoint)
                .mul(lpSupply1e18)
                .div(100)
                .div(totallpSupply);

            uint256 snpReward = snpmint.mul(farmrate).div(100);
            accSnpPerShare = accSnpPerShare.add(
                snpReward.mul(1e12).div(lpSupply)
            );
        }
        return user.amount.mul(accSnpPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Deposit LP tokens to Master for SNP allocation.
    function deposit(
        uint256 _pid,
        uint256 _amount,
        string calldata _refuser
    ) public whenNotPaused {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user
                .amount
                .mul(pool.accSnpPerShare)
                .div(1e12)
                .sub(user.rewardDebt);
            if (pending > 0 && pool.lockPeriod == 0) {
                uint256 _depositTime = now - user.depositTime;
                if (_depositTime < 1 days) {
                    uint256 _actualReward = _depositTime
                        .mul(pending)
                        .mul(1e18)
                        .div(1 days)
                        .div(1e18);
                    uint256 _goverAomunt = pending.sub(_actualReward);
                    safeSnpTransfer(governance, _goverAomunt);
                    pending = _actualReward;
                }
                safeSnpTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            user.amount = user.amount.add(_amount);
            pool.lpSupply = pool.lpSupply.add(_amount);
            user.depositTime = now;
            user.refAddress = _refuser;
            uint256 lpDec = ILPERC20(address(pool.lpToken)).decimals();
            uint256 lpSupply = _amount
                .mul(pool.allocPoint)
                .mul(1e18)
                .div(100)
                .div(10**lpDec);
            totallpSupply = totallpSupply.add(lpSupply);
        }
        user.rewardDebt = user.amount.mul(pool.accSnpPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount, user.refAddress);
    }

    // Withdraw LP tokens from Master.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good amount");
        if (_amount > 0 && pool.lockPeriod > 0) {
            require(
                now >= user.depositTime + pool.lockPeriod,
                "withdraw: lock time not reach"
            );
            if (pool.unlockPeriod > 0) {
                require(
                    (now - user.depositTime) % pool.lockPeriod <=
                        pool.unlockPeriod,
                    "withdraw: not in unlock time period"
                );
            }
        }

        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accSnpPerShare).div(1e12).sub(
            user.rewardDebt
        );
        if (pending > 0) {
            uint256 _depositTime = now - user.depositTime;
            if (_depositTime < 1 days && pool.lockPeriod == 0) {
                uint256 _actualReward = _depositTime
                    .mul(pending)
                    .mul(1e18)
                    .div(1 days)
                    .div(1e18);
                uint256 _goverAomunt = pending.sub(_actualReward);
                safeSnpTransfer(governance, _goverAomunt);
                pending = _actualReward;
            }
            safeSnpTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpSupply = pool.lpSupply.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);

            uint256 lpDec = ILPERC20(address(pool.lpToken)).decimals();
            uint256 lpSupply = _amount
                .mul(pool.allocPoint)
                .mul(1e18)
                .div(100)
                .div(10**lpDec);
            totallpSupply = totallpSupply.sub(lpSupply);
        }
        user.rewardDebt = user.amount.mul(pool.accSnpPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(
            pool.lockPeriod == 0 || pool.emergencyEnable == true,
            "emergency withdraw: not good condition"
        );
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);

        uint256 lpDec = ILPERC20(address(pool.lpToken)).decimals();
        uint256 lpSupply = user
            .amount
            .mul(pool.allocPoint)
            .mul(1e18)
            .div(100)
            .div(10**lpDec);
        totallpSupply = totallpSupply.sub(lpSupply);

        emit EmergencyWithdraw(msg.sender, _pid, user.amount);

        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Safe snp transfer function, just in case if rounding error causes pool to not have enough SNPs.
    function safeSnpTransfer(address _to, uint256 _amount) internal {
        uint256 snpBal = snptoken.balanceOf(address(this));
        if (_amount > snpBal) {
            snptoken.transfer(_to, snpBal);
        } else {
            snptoken.transfer(_to, _amount);
        }
    }

    // set snps for every block.
    function setSnpPerBlock(uint256 _snpPerBlock) public onlyOwner {
        require(_snpPerBlock > 0, "!snpPerBlock-0");

        snpPerBlock = _snpPerBlock;
    }
}
