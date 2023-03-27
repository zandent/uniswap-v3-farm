// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

import "./interfaces/IERC721.sol";
import "./interfaces/INonfungiblePositionManager.sol";
import "./interfaces/IUniswapV3Staker.sol";
// import "./libraries/SafeERC20.sol";

import "./PPIToken.sol";
import "./PPIRate.sol";
import "./VotingEscrow.sol";
import "./utils/NeedInitialize.sol";
import "./roles/WhitelistedRole.sol";

contract FarmController is NeedInitialize, WhitelistedRole {
    // using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many tokens the user has provided.
        uint256 workingSupply; // boosted user share.
        uint256 rewardPerShare; // Accumulated reward per share.
        uint256 pendingReward; // reward not claimed
        uint256[] tokenIds; // staked token IDs
    }

    // Info of each pool.
    struct PoolInfo {
        address token0; // Address of token0 contract.
        address token1; // Address of token1 contract.
        uint24 fee; // fee tier of the pool
        uint256 allocPoint; // How many allocation points assigned to this pool. CAKEs to distribute per block.
        uint256 lastRewardTime; // Last block number that CAKEs distribution occurs.
        uint256 totalSupply; // token total supply.
        uint256 workingSupply; // boosted token supply.
        uint256 accRewardPerShare; // Accumulated reward per share.
    }

    // Info of each pool by token id
    struct PoolInfoByTokenId {
        bool active;    //true if the token id is deposited into address(this)
        address token0; // Address of token0 contract.
        address token1; // Address of token1 contract.
        uint24 fee; // fee tier of the pool
        address owner; // owner of NFT
    }

    PPIToken public ppi;
    VotingEscrow public votingEscrow;
    // user_boost_share = min(
    //   user_stake_amount,
    //   k% * user_stake_amount + (1 - k%) * total_stake_amount * (user_locked_share / total_locked_share)
    // )
    uint256 public k;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    //uint256: tokenid to pool info
    mapping(uint256 => PoolInfoByTokenId) public poolInfoByTokenId;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;
    // treasury address
    address public treasuryAddr;
    // market address
    address public marketAddr;
    // dev address
    address public devAddr;
    // PPI Rate
    address public ppiRate;
    // reward claimable
    bool public claimable;
    // NonfungiblePositionManager NFT token tracker
    address public NonfungiblePositionManager;
    //allcapoint reward for total liquidity
    uint256 public rewardAllocaPointForAmount;
    //allcapoint reward for liqudity concentration in uniswap v3 pool
    uint256 public rewardAllocaPointForConcentration;
    // IUniswapV3Staker
    IUniswapV3Staker public UniswapV3Staker;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event UpdateWorkingSupply(
        address indexed user,
        uint256 indexed pid,
        uint256 workingSupply
    );
    event Claim(address indexed user, uint256 indexed pid, uint256 amount);

    function initialize(
        address _treasuryAddr,
        address _marketAddr,
        address _devAddr,
        address _votingEscrow,
        address _ppiRate,
        address _ppi, // reward token
        uint256 _startTime,
        address _token0,// first pool token0
        address _token1, // first pool token1,
        uint24 _fee, // fee tier
        address _NonfungiblePositionManager
    ) external onlyInitializeOnce {
        _addWhitelistAdmin(msg.sender);

        ppiRate = _ppiRate;
        treasuryAddr = _treasuryAddr;
        marketAddr = _marketAddr;
        devAddr = _devAddr;

        ppi = PPIToken(_ppi);
        votingEscrow = VotingEscrow(_votingEscrow);

        NonfungiblePositionManager = _NonfungiblePositionManager;
        
        UniswapV3Staker = IUniswapV3Staker(address(0));

        // first farming pool
        poolInfo.push(
            PoolInfo({
                token0: _token0,
                token1: _token1,
                fee: _fee,
                allocPoint: 1000,
                lastRewardTime: _startTime,
                totalSupply: 0,
                workingSupply: 0,
                accRewardPerShare: 0
            })
        );

        totalAllocPoint = 1000;
        k = 33;
        rewardAllocaPointForAmount = 5;
        rewardAllocaPointForConcentration = 5;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function getPoolInfo(uint256 offset)
        external
        view
        returns (PoolInfo[] memory result)
    {
        uint256 n =
            offset + 100 < poolInfo.length ? offset + 100 : poolInfo.length;
        if (n > offset) {
            result = new PoolInfo[](n - offset);
            for (uint256 i = offset; i < n; ++i) {
                result[i - offset] = poolInfo[i];
            }
        }
    }
    function getAllocPointByPid(uint256 pid)
        external
        view
        returns (uint256 allocPoint)
    {
        return poolInfo[pid].allocPoint;
    }
    function getPoolInfoByTokenId(uint256 tokenId) external view returns (PoolInfoByTokenId memory poolInfoEntry){
        return poolInfoByTokenId[tokenId];
    }
    // Update the given pool's reward allocation point. Can only be called by the owner.
    function setUniswapV3Staker(
        address _UniswapV3Staker
    ) external onlyWhitelistAdmin {
        UniswapV3Staker = IUniswapV3Staker(_UniswapV3Staker);
    }
    // Add a new lp to the pool. Can only be called by the whitelist admin.
    function add(
        uint256 _allocPoint,
        address _token0,
        address _token1,
        uint24 _fee,
        uint256 _startTime,
        bool _withUpdate
    ) external onlyWhitelistAdmin {
        if (_withUpdate) {
            massUpdatePools();
        }
        if (_startTime < block.timestamp) _startTime = block.timestamp;
        totalAllocPoint = totalAllocPoint + _allocPoint;
        poolInfo.push(
            PoolInfo({
                token0: _token0,
                token1: _token1,
                fee: _fee,
                allocPoint: _allocPoint,
                lastRewardTime: _startTime,
                totalSupply: 0,
                workingSupply: 0,
                accRewardPerShare: 0
            })
        );
    }

    // Update the given pool's reward allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) external onlyWhitelistAdmin {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        if (prevAllocPoint != _allocPoint) {
            totalAllocPoint = totalAllocPoint - prevAllocPoint + _allocPoint;
        }
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    function updatePool(uint256 _pid) public {
        _updatePool(_pid);
    }
    // set reward alloca points
    function updateRewardAllocaPoint(uint256 _rewardAllocaPointForAmount, uint256 _rewardAllocaPointForConcentration) external onlyWhitelistAdmin {
        rewardAllocaPointForAmount = _rewardAllocaPointForAmount;
        rewardAllocaPointForConcentration = _rewardAllocaPointForConcentration;
    }
    // Update reward variables of the given pool to be up-to-date.
    function _updatePool(uint256 _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }
        if (pool.totalSupply == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        uint256 reward =
            (PPIRate(ppiRate).calculateReward(
                pool.lastRewardTime,
                block.timestamp
            ) * pool.allocPoint) / totalAllocPoint;
        // reward allocation
        reward = reward * rewardAllocaPointForAmount/(rewardAllocaPointForAmount+rewardAllocaPointForConcentration);
        ppi.mint(treasuryAddr, (reward * 15) / 100);
        ppi.mint(devAddr, (reward * 15) / 100);
        ppi.mint(marketAddr, (reward * 20) / 100);
        reward = (reward * 50) / 100;
        // update prefix sum
        pool.accRewardPerShare =
            pool.accRewardPerShare +
            (reward * (10**18)) /
            pool.workingSupply;
        pool.lastRewardTime = block.timestamp;
    }

    function _updateUser(uint256 _pid, address _user)
        internal
        returns (uint256 reward)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        reward =
            (user.workingSupply *
                (pool.accRewardPerShare - user.rewardPerShare)) /
            (10**18);
        reward += user.pendingReward;
        if (claimable) {
            user.pendingReward = 0;
            ppi.mint(_user, reward);
        } else {
            user.pendingReward = reward;
        }
        user.rewardPerShare = pool.accRewardPerShare;
    }

    function _checkpoint(uint256 _pid, address _user) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 l = (k * user.amount) / 100;
        uint256 votingTotal = votingEscrow.totalSupply();
        if (votingTotal > 0)
            l +=
                (((pool.totalSupply * votingEscrow.balanceOf(_user)) /
                    votingTotal) * (100 - k)) /
                100;
        if (l > user.amount) l = user.amount;
        pool.workingSupply = pool.workingSupply + l - user.workingSupply;
        user.workingSupply = l;
        emit UpdateWorkingSupply(_user, _pid, l);
    }

    // Deposit tokens to Controller for reward allocation.
    function deposit(uint256 _pid, uint256 tokenId)
        external
        returns (uint256 reward)
    {
        _updatePool(_pid);
        reward = _updateUser(_pid, msg.sender);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        (
            ,
            ,
            address token0,
            address token1,
            uint24 fee,
            ,
            ,
            uint128 liquidity,
            ,
            ,
            ,
        ) = INonfungiblePositionManager(NonfungiblePositionManager).positions(tokenId);
        require(((pool.token0 == token0 && pool.token1 == token1) || (pool.token0 == token1 && pool.token1 == token0)) && pool.fee == fee, "FarmController: tokenId does not match pid");
        PoolInfoByTokenId storage poolInfoEntry = poolInfoByTokenId[tokenId];
        require(poolInfoEntry.active == false, "FarmController: tokenId already exists in the pool");
        if (liquidity > 0) {
            user.amount += liquidity;
            user.tokenIds.push(tokenId);
            poolInfoEntry.active = true;
            poolInfoEntry.token0 = token0;
            poolInfoEntry.token1 = token1;
            poolInfoEntry.fee = fee;
            poolInfoEntry.owner = msg.sender;
            pool.totalSupply += liquidity;
            IERC721(NonfungiblePositionManager).safeTransferFrom(
                address(msg.sender),
                address(this),
                tokenId
            );
        }
        _checkpoint(_pid, msg.sender);
        emit Deposit(msg.sender, _pid, liquidity);
    }

    // Claim reward from farmer and staker inherited from Deposit
    function claim(uint256 _pid)
        external
        returns (uint256 reward)
    {
        _updatePool(_pid);
        reward = _updateUser(_pid, msg.sender);
        _checkpoint(_pid, msg.sender);
        UniswapV3Staker.claimReward(address(ppi), msg.sender, 0);
        emit Claim(msg.sender, _pid, reward);
    }

    // Withdraw tokens from Controller.
    function withdraw(uint256 _pid, uint256 tokenId)
        external
        returns (uint256 reward)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        (
            ,
            ,
            address token0,
            address token1,
            uint24 fee,
            ,
            ,
            uint128 liquidity,
            ,
            ,
            ,
        ) = INonfungiblePositionManager(NonfungiblePositionManager).positions(tokenId);
        require(((pool.token0 == token0 && pool.token1 == token1) || (pool.token0 == token1 && pool.token1 == token0)) && pool.fee == fee, "FarmController: tokenId does not match pid");
        PoolInfoByTokenId storage poolInfoEntry = poolInfoByTokenId[tokenId];
        require(poolInfoEntry.active == true && poolInfoEntry.owner == msg.sender, "FarmController: only active owner can withdraw lp in the pool");
        (
            ,
            uint48 numberOfStakes,
            ,
        ) = UniswapV3Staker.deposits(tokenId);
        require(numberOfStakes == 0, "FarmController: must unstake from UniswapV3Staker");
        _updatePool(_pid);
        reward = _updateUser(_pid, msg.sender);
        if (liquidity > 0) {
            user.amount -= liquidity;
            pool.totalSupply -= liquidity;
            poolInfoEntry.active = false;
            IERC721(NonfungiblePositionManager).safeTransferFrom(address(this), address(msg.sender), tokenId);
            //TODO; maybe remove the entry of the userinfo tokenIds. ONLY for frontend
        }
        _checkpoint(_pid, msg.sender);
        emit Withdraw(msg.sender, _pid, liquidity);
    }

    // kick someone from boosting if his/her locked share expired
    function kick(uint256 _pid, address _user) external {
        require(
            votingEscrow.balanceOf(_user) == 0,
            "FarmController: user locked balance is not zero"
        );
        UserInfo storage user = userInfo[_pid][_user];
        uint256 oldWorkingSupply = user.workingSupply;
        _updatePool(_pid);
        _updateUser(_pid, _user);
        _checkpoint(_pid, _user);
        require(
            oldWorkingSupply > user.workingSupply,
            "FarmController: user working supply is up-to-date"
        );
    }

    /* ==== admin functions ==== */
    function setAddr(
        address _treasuryAddr,
        address _marketAddr,
        address _devAddr
    ) external onlyWhitelistAdmin {
        treasuryAddr = _treasuryAddr;
        marketAddr = _marketAddr;
        devAddr = _devAddr;
    }

    function setClaimable(bool _claimable) external onlyWhitelistAdmin {
        claimable = _claimable;
    }

    function userUsedTokenIds(address user, uint256 pid) external view returns (uint256[] memory tokenIds) {
        return userInfo[pid][user].tokenIds;
    }
    function nonBoostFactor() external view returns(uint) {
        return k;
    }
    function boostTotalSupply() external view returns(uint) {
        return votingEscrow.totalSupply();
    }
    function boostBalance(address _user) external view returns(uint) {
        return votingEscrow.balanceOf(_user);
    }
    function onERC721Received(
        address,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4) {
        // require(
        //     msg.sender == address(nonfungiblePositionManager),
        //     'UniswapV3Staker::onERC721Received: not a univ3 nft'
        // );

        // (, , , , , int24 tickLower, int24 tickUpper, , , , , ) = nonfungiblePositionManager.positions(tokenId);

        // deposits[tokenId] = Deposit({owner: from, numberOfStakes: 0, tickLower: tickLower, tickUpper: tickUpper});
        // emit DepositTransferred(tokenId, address(0), from);

        // if (data.length > 0) {
        //     if (data.length == 160) {
        //         _stakeToken(abi.decode(data, (IncentiveKey)), tokenId);
        //     } else {
        //         IncentiveKey[] memory keys = abi.decode(data, (IncentiveKey[]));
        //         for (uint256 i = 0; i < keys.length; i++) {
        //             _stakeToken(keys[i], tokenId);
        //         }
        //     }
        // }
        // require(false, "onERC721Received forbidden");
        return this.onERC721Received.selector;
    }
}
