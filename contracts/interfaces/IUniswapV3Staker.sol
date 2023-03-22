// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.2;

/// @title Uniswap V3 Staker Interface
/// @notice Allows staking nonfungible liquidity tokens in exchange for reward tokens
interface IUniswapV3Staker {

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
}
