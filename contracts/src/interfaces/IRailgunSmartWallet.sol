// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// Minimal Railgun SmartWallet surface used by the Railgun adapter.
///
/// The full `Transaction` / `BoundParams` / `TokenData` types live in the
/// railgun-contracts repo. Reproducing them verbatim here ties the repo
/// to a specific Railgun version; the adapter instead decodes the raw
/// calldata struct layout it cares about (see RailgunAdapter.sol).
interface IRailgunSmartWallet {
    /// Submit one or more Railgun transactions. The paymaster adapter
    /// enforces `txs.length == 1` — users who want batches use the
    /// uniform account `tail` array instead.
    function transact(bytes calldata txsBlob) external;
}
