// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// Uniform shape every per-protocol 4337 account exposes under the
/// multi-protocol privacy paymaster.
///
/// The account is the security boundary for protocol-specific validation
/// (proof, nullifier, recipient, ...). The paymaster is the security
/// boundary for economic checks (gross >= priced max cost) and only
/// trusts accounts it has explicitly whitelisted via `setApprovedSender`.
interface IPrivacyAccount {
    /// Per-protocol accounts never hold ETH — the unshield always
    /// credits the paymaster directly, never the account. Tail calls
    /// therefore carry no `value` field: any attempt to send ETH would
    /// revert anyway, so the field would only be a footgun.
    struct Call {
        address target;
        bytes data;
    }

    /// Execute a single unshield (must succeed) followed by best-effort
    /// tail calls (return values ignored, reverts do NOT bubble up).
    /// MUST only be callable by the EntryPoint.
    function execute(
        bytes calldata unshieldCalldata,
        Call[] calldata tail
    ) external;

    /// View-only hook called by `PrivacyPaymaster` during
    /// `_validatePaymasterUserOp`. Performs all protocol-specific
    /// validation of the single-unshield blob and returns what the
    /// paymaster needs to price the operation:
    ///
    ///   - `expectedSender`: the account the paymaster should accept as
    ///     `userOp.sender` (typically `address(this)`; returned so the
    ///     paymaster can sanity-check even if whitelisting drifts).
    ///   - `feeToken`: the ERC20 (or `address(0)` for native) the
    ///     unshield will credit to the paymaster. Derived from the
    ///     unshield calldata itself — the paymaster separately checks
    ///     it against its fee-token allowlist.
    ///   - `grossAmount`: the amount of `feeToken` the paymaster will
    ///     actually receive, net of any protocol-internal unshield fee.
    ///
    /// Reverts on any invalid unshield (wrong selector, wrong recipient,
    /// bad proof, spent nullifier, ...). MUST be view-safe: the
    /// paymaster calls it under 4337 staked simulation storage rules,
    /// so reads are confined to this account + protocol instance.
    function evaluateUserOperation(
        bytes calldata unshieldCalldata,
        address paymaster
    )
        external
        view
        returns (
            address expectedSender,
            address feeToken,
            uint256 grossAmount
        );
}
