// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// Uniform interface for 4337 accounts that can pay a PrivacyPaymaster with
/// privacy-protocol funds.
///
/// Implementors guarantee that any `feeCalldata` that `previewFee`
/// approves MUST result in the paymaster being credited with the predicted `feeToken`
/// and `feeAmount` when `execute` is called with the same `feeCalldata`.
interface IPrivacyAccount {
    struct Call {
        address target;
        bytes data;
    }

    /// Performs all protocol-specific validation of the fee payment.
    ///
    /// @param feeCalldata The exact calldata the account will
    /// forward to the privacy protocol to make the fee payment.
    /// @param paymasterAndData The `userOp.paymasterAndData` field.
    /// @return feeToken The ERC20 (or `address(0)` for native) being
    /// paid to the paymaster.
    /// @return feeAmount The amount of `feeToken` being paid to the
    /// paymaster.
    ///
    /// @dev Reverts on any invalid fee payment.
    function previewFee(
        bytes calldata feeCalldata,
        bytes calldata paymasterAndData
    ) external view returns (address feeToken, uint256 feeAmount);

    /// Executes a fee payment followed by the tail calls.
    ///
    /// @dev The fee payment MUST always be called first, and MUST result in
    /// the predicted `feeToken` and `feeAmount` being credited to the paymaster.
    ///
    /// @dev The `tail` calls MUST NOT cause the entire transaction to revert if
    /// any fail.
    function execute(bytes calldata feeCalldata, Call[] calldata tail) external;
}
