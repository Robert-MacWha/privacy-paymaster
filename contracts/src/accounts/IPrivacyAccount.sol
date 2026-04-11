// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// Uniform interface for 4337 accounts that can pay a PrivacyPaymaster with
/// unshielded funds.
///
/// Implementors guarantee that any `unshieldCalldata` that `previewUnshield`
/// approves MUST result in the paymaster being credited with the predicted `feeToken`
/// and `feeAmount` when `execute` is called with the same `unshieldCalldata`. Failing
/// to do so enables griefing of the paymaster.
interface IPrivacyAccount {
    struct Call {
        address target;
        bytes data;
    }

    /// Performs all protocol-specific validation of the unshield
    /// blob.
    ///
    /// @param unshieldCalldata The exact calldata the account will
    /// forward to the unshield protocol.
    /// @return feeToken The ERC20 (or `address(0)` for native) being
    /// unshielded and credited to the paymaster.
    /// @return feeAmount The amount of `feeToken` being unshielded to the
    /// paymaster.
    ///
    /// @dev Reverts on any invalid unshield.
    function previewUnshield(
        bytes calldata unshieldCalldata
    ) external view returns (address feeToken, uint256 feeAmount);

    /// Executes an unshield followed by the tail calls.
    ///
    /// @dev The unshield call MUST always be called first, and MUST result in
    /// the predicted `feeToken` and `feeAmount` being credited to the paymaster.
    ///
    /// @dev The `tail` calls MUST NOT cause the entire transaction to revert if
    /// any fail.
    function execute(
        bytes calldata unshieldCalldata,
        Call[] calldata tail
    ) external;
}
