// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.2;
pragma abicoder v2;
/// @title Uniswap V3 Staker Interface
/// @notice Allows staking nonfungible liquidity tokens in exchange for reward tokens
interface IUniswapV3Staker {
    /// @param rewardToken The token being distributed as a reward
    /// @param pool The Uniswap V3 pool
    /// @param startTime The time when the incentive program begins
    /// @param endTime The time when rewards stop accruing
    /// @param refundee The address which receives any remaining reward tokens when the incentive is ended
    struct IncentiveKey {
        address rewardToken;
        address pool;
        uint256 startTime;
        uint256 endTime;
        address refundee;
    }
    /// @param rewardToken The token being distributed as a reward
    /// @param startTime The time when the incentive program begins
    /// @param endTime The time when rewards stop accruing
    /// @param refundee The address which receives any remaining reward tokens when the incentive is ended
    struct IncentiveKeyIgnoringPool {
        address rewardToken;
        uint256 startTime;
        uint256 endTime;
        address refundee;
    }
    /// @notice Represents a staking incentive
    /// @param key The ID of the incentive computed from its parameters
    /// @return totalRewardClaimed The amount of reward token already claimed by users
    /// @return totalRewardUnclaimed The amount of reward token not yet claimed by users
    /// @return totalSecondsClaimedX128 Total liquidity-seconds claimed, represented as a UQ32.128
    /// @return numberOfStakes The count of deposits that are currently staked for the incentive
    function incentives(bytes32 key)
        external
        view
        returns (
            uint256 totalRewardClaimed,
            uint256 totalRewardUnclaimed,
            uint160 totalSecondsClaimedX128,
            uint96 numberOfStakes
        );
    /// @notice Represents produced rewards per user
    /// @param user, address of user
    /// @param keyIP The ID of the incentive computed from its parameters
    /// @return rewardProduced The amount of reward token not produced by users 
    function userRewardProduced(address user, bytes32 keyIP) external
        view
        returns (
            uint256
        );
    /// @notice Returns information about a deposited NFT
    /// @return owner The owner of the deposited NFT
    /// @return numberOfStakes Counter of how many incentives for which the liquidity is staked
    /// @return tickLower The lower tick of the range
    /// @return tickUpper The upper tick of the range
    function deposits(uint256 tokenId)
        external
        view
        returns (
            address owner,
            uint48 numberOfStakes,
            int24 tickLower,
            int24 tickUpper
        );
    /// @notice Transfers `amountRequested` of accrued `rewardToken` rewards from the contract to the recipient `to`
    /// @param rewardToken The token being distributed as a reward
    /// @param to The address where claimed rewards will be sent to
    /// @param amountRequested The amount of reward tokens to claim. Claims entire reward amount if set to 0.
    /// @return reward The amount of reward tokens claimed
    function claimReward(
        address rewardToken,
        address to,
        uint256 amountRequested
    ) external returns (uint256 reward);
    /// @notice Stakes a Uniswap V3 LP token
    /// @param key The key of the incentive for which to stake the NFT
    /// @param tokenId The ID of the token to stake
    /// @param owner The owner of the token to stake
    function stakeToken(IncentiveKey memory key, uint256 tokenId, address owner) external;

    /// @notice Unstakes a Uniswap V3 LP token
    /// @param key The key of the incentive for which to unstake the NFT
    /// @param tokenId The ID of the token to unstake
    /// @param owner The owner of the token to stake
    function unstakeToken(IncentiveKey memory key, uint256 tokenId, address owner) external;

    /// @notice unstake key1, claim all rewards from previous icnentives and stake to key2
    /// @param key1 The key of the incentive
    /// @param key2 The key of the incentive
    /// @param tokenId The ID of the token
    /// @param rewardToken The token being distributed as a reward
    /// @param to The address where claimed rewards will be sent to
    function unstakeClaimRewardandStakeNew(IncentiveKey memory key1, IncentiveKey memory key2, uint256 tokenId, address rewardToken,
            address to) external;
    
    /// @notice Ends an incentive after the incentive end time has passed and all stakes have been withdrawn
    /// @param key Details of the incentive to end
    /// @return refund The remaining reward tokens when the incentive is ended
    function endIncentive(IncentiveKey memory key) external returns (uint256 refund);
}
