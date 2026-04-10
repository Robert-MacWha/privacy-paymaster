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
    struct Call {
        address target;
        bytes data;
    }

    /// Performs all protocol-specific validation of the single-unshield
    /// blob and returns what the paymaster needs to price the operation:
    ///
    /// @param unshieldCalldata The exact calldata the account will
    /// forward to the unshield protocol.
    /// @return feeToken The ERC20 (or `address(0)` for native) being
    /// unshielded and credited to the paymaster.
    /// @return grossAmount The amount of `feeToken` the paymaster will
    /// receive.
    ///
    /// Reverts on any invalid unshield (wrong selector, wrong recipient,
    /// bad proof, spent nullifier, ...).
    function evaluateUserOperation(
        bytes calldata unshieldCalldata
    ) external view returns (address feeToken, uint256 grossAmount);

    /// Execute a single unshield (must succeed) followed by best-effort
    /// tail calls (return values ignored, reverts isolated to emits).
    function execute(
        bytes calldata unshieldCalldata,
        Call[] calldata tail
    ) external;
}
