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
    error UnshieldFailed();

    // ----- EVENTS -----
    event TailCallFailed(
        uint256 indexed index,
        address indexed target,
        bytes returnData
    );

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
        (bool ok, ) = PROTOCOL_TARGET.call(feeCalldata);
        if (!ok) revert UnshieldFailed();

        // Tail calls are best-effort: a revert would roll back the unshield
        // and leave the paymaster unpaid. Failures are emitted as events.
        uint256 len = tail.length;
        for (uint256 i = 0; i < len; ++i) {
            Call calldata c = tail[i];
            // aderyn-ignore-next-line(unchecked-low-level-call)
            (bool callOk, bytes memory ret) = c.target.call(c.data);
            if (!callOk) emit TailCallFailed(i, c.target, ret);
        }
    }
}
