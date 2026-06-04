// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {
    PackedUserOperation
} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";

interface IFeeAdapter {
    /// @notice Executes the fee-paying operation during ERC-4337 validation.
    ///
    /// @param userOp The packed user operation being validated.
    /// @return feeToken The token in which the fee was collected (address(0) for ETH).
    /// @return feePaid The amount of feeToken collected.
    ///
    /// @dev reverts if fee collection fails
    function collectFee(
        PackedUserOperation calldata userOp
    ) external returns (address feeToken, uint256 feePaid);
}
