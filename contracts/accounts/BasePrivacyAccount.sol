// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IAccount} from "@account-abstraction/contracts/interfaces/IAccount.sol";
import {
    IEntryPoint
} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {
    PackedUserOperation
} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";

import {IPrivacyAccount} from "../interfaces/IPrivacyAccount.sol";

/// Abstract PrivacyAccount implementing universal `execute` logic.
abstract contract BasePrivacyAccount is IAccount, IPrivacyAccount {
    // ----- ERRORS -----
    error CallerNotEntryPoint();
    error FeeFailed(bytes returnData);
    error TailCallReverted(uint256 index, address target, bytes returnData);
    error OnlySelf();

    // ----- EVENTS -----
    event TailCallFailed(bytes reason);

    // ----- IMMUTABLES -----
    IEntryPoint public immutable ENTRY_POINT;

    /// Address on which to call unshield.
    address private immutable PROTOCOL_TARGET;

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
        // Validation runs in `evaluateUserOperation`, which the paymaster
        // calls during `_validatePaymasterUserOp`.
        if (msg.sender != address(ENTRY_POINT)) revert CallerNotEntryPoint();
        validationData = 0;
    }

    // ----- IPrivacyAccount -----
    function previewFee(
        bytes calldata feeCalldata,
        bytes calldata paymasterAndData
    )
        external
        view
        virtual
        override
        returns (address feeToken, uint256 feeAmount);

    function execute(
        bytes calldata feeCalldata,
        Call[] calldata tail
    ) external override {
        if (msg.sender != address(ENTRY_POINT)) revert CallerNotEntryPoint();

        // The fee payment MUST succeed so the paymaster gets paid.
        // aderyn-ignore-next-line(unchecked-low-level-call)
        (bool ok, bytes memory ret) = PROTOCOL_TARGET.call(feeCalldata);
        if (!ok) revert FeeFailed(ret);

        // Tail calls are executed atomically after fee payment. If any tail call
        // reverts, all are reverted but the fee payment still goes through.
        try this._executeTailCalls(tail) {
            // all tail calls succeeded
        } catch (bytes memory reason) {
            emit TailCallFailed(reason);
        }
    }

    function _executeTailCalls(Call[] calldata tail) external {
        if (msg.sender != address(this)) revert OnlySelf();

        uint256 len = tail.length;
        for (uint256 i = 0; i < len; ++i) {
            Call calldata c = tail[i];
            (bool callOk, bytes memory ret) = c.target.call(c.data);
            if (!callOk) {
                revert TailCallReverted(i, c.target, ret);
            }
        }
    }
}
