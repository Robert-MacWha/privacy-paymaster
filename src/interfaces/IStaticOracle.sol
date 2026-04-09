// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

/// Minimal surface of balmy's IStaticOracle used by PrivacyPaymaster.
///
/// @dev https://github.com/Balmy-protocol/uniswap-v3-oracle/blob/main/solidity/interfaces/IStaticOracle.sol
interface IStaticOracle {
    /// @notice Returns whether a specific pair can be supported by the oracle
    /// @dev The pair can be provided in tokenA/tokenB or tokenB/tokenA order
    /// @return Whether the given pair can be supported by the oracle
    function isPairSupported(
        address tokenA,
        address tokenB
    ) external view returns (bool);

    /// @notice Returns a quote, based on the given tokens and amount, by querying all of the pair's pools
    /// @dev If some pools are not configured correctly for the given period, then they will be ignored
    /// @dev Will revert if there are no pools available/configured for the pair and period combination
    /// @param baseAmount Amount of token to be converted
    /// @param baseToken Address of an ERC20 token contract used as the baseAmount denomination
    /// @param quoteToken Address of an ERC20 token contract used as the quoteAmount denomination
    /// @param period Number of seconds from which to calculate the TWAP
    /// @return quoteAmount Amount of quoteToken received for baseAmount of baseToken
    /// @return queriedPools The pools that were queried to calculate the quote
    function quoteAllAvailablePoolsWithTimePeriod(
        uint128 baseAmount,
        address baseToken,
        address quoteToken,
        uint32 period
    )
        external
        view
        returns (uint256 quoteAmount, address[] memory queriedPools);
}
