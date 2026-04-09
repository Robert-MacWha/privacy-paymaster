// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IAccount} from "@account-abstraction/contracts/interfaces/IAccount.sol";
import {
    IEntryPoint
} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {
    PackedUserOperation
} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";

import {IPrivacyAccount} from "./IPrivacyAccount.sol";

/// Abstract base that every per-protocol 4337 account inherits from.
///
/// Collects everything that is genuinely identical across protocols:
///   - the EntryPoint binding + `CallerNotEntryPoint` gate
///   - a trivial `validateUserOp` (real validation lives in
///     `evaluateUserOperation`, which the paymaster calls)
///   - the `execute` entry point: forward the unshield blob to the
///     immutable `PROTOCOL_TARGET`, then run the tail best-effort
///
/// Subclasses only implement `evaluateUserOperation` — the
/// protocol-specific view that the paymaster uses to validate the
/// unshield and price the fee.
abstract contract BasePrivacyAccount is IAccount, IPrivacyAccount {
    // ----- ERRORS -----
    error CallerNotEntryPoint();
    error UnshieldFailed();

    // ----- IMMUTABLES -----
    IEntryPoint public immutable ENTRY_POINT;
    /// Address the unshield blob is forwarded to. Typed as `address`
    /// because every protocol has a different "entrypoint" type; the
    /// subclass casts it to its own interface in `evaluateUserOperation`.
    address public immutable PROTOCOL_TARGET;

    constructor(IEntryPoint _entryPoint, address _protocolTarget) {
        ENTRY_POINT = _entryPoint;
        PROTOCOL_TARGET = _protocolTarget;
    }

    // ----- IAccount -----
    function validateUserOp(
        PackedUserOperation calldata,
        bytes32,
        uint256
    ) external virtual override returns (uint256 validationData) {
        // Real validation runs in `evaluateUserOperation`, which the
        // paymaster calls during `_validatePaymasterUserOp`. This hook
        // only needs to gate the caller and return the success code.
        if (msg.sender != address(ENTRY_POINT)) revert CallerNotEntryPoint();
        validationData = 0;
    }

    // ----- IPrivacyAccount -----
    function execute(
        bytes calldata unshieldCalldata,
        Call[] calldata tail
    ) external override {
        if (msg.sender != address(ENTRY_POINT)) revert CallerNotEntryPoint();

        // The unshield MUST succeed — this is how the paymaster gets paid.
        // aderyn-ignore-next-line(unchecked-low-level-call)
        (bool ok, ) = PROTOCOL_TARGET.call(unshieldCalldata);
        if (!ok) revert UnshieldFailed();

        // Tail calls are best-effort: return values ignored, reverts
        // isolated from the unshield + paymaster settlement. No `value`
        // is forwarded — the account never holds ETH.
        uint256 len = tail.length;
        for (uint256 i = 0; i < len; ++i) {
            Call calldata c = tail[i];
            // aderyn-ignore-next-line(unchecked-low-level-call)
            (bool tok, ) = c.target.call(c.data);
            tok;
        }
    }

    /// Subclasses MUST implement. See `IPrivacyAccount.evaluateUserOperation`.
    function evaluateUserOperation(
        bytes calldata unshieldCalldata,
        address paymaster
    )
        external
        view
        virtual
        override
        returns (
            address expectedSender,
            address feeToken,
            uint256 grossAmount
        );
}
