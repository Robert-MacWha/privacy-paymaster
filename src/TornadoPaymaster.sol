// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {
    BasePaymaster
} from "@account-abstraction/contracts/core/BasePaymaster.sol";
import {
    PackedUserOperation
} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {
    IPaymaster
} from "@account-abstraction/contracts/interfaces/IPaymaster.sol";
import {
    IEntryPoint
} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {ITornadoInstance} from "./interfaces/ITornadoInstance.sol";
import {IVerifier} from "./interfaces/IVerifier.sol";
import {TornadoAccount} from "./TornadoAccount.sol";

/// Custom paymaster / account contract that can be used to withdraw funds from a
/// tornadocash pool.
///
/// The user flow is as follows:
/// 1. User generates withdrawal proof off-chain.
/// 2. User creates a UserOperation calling `withdraw` on this contract.
/// 3. EntryPoint calls `validate*` on this contract which validates the proof and
///    params against tornado's state.
/// 4. If valid, the EntryPoint calls `TornadoAccount.withdraw` which executes the
///    tornado withdrawal with this paymaster as the recipient, causing the
///    denomination to land in this contract.
/// 5. After withdrawal, the entryPoint calls `postOp` on this contract which deducts
///    the fee from the withdrawn amount and forwards the rest to the user's desired
///    destination.
contract TornadoPaymaster is BasePaymaster {
    // ----- ERRORS -----
    error InvalidSelector();
    error InvalidSender();
    error InvalidRecipient();
    error NonZeroRefund();
    error NullifierAlreadySpent(bytes32 nullifierHash);
    error UnknownRoot(bytes32 root);
    error InvalidProof();
    error ForwardFailed();

    // ----- CONSTANTS -----
    ITornadoInstance public immutable TORNADO_INSTANCE;
    TornadoAccount public immutable TORNADO_ACCOUNT;
    uint256 public constant POST_OP_GAS_OVERHEAD = 10_000;
    uint256 private constant PAYMASTER_AND_DATA_OFFSET = 20 + 16 + 16; // paymaster(20) || verificationGasLimit(16) || postOpGasLimit(16)

    // ----- CONSTRUCTOR -----
    constructor(
        IEntryPoint __entryPoint,
        address owner,
        ITornadoInstance _tornadoInstance,
        TornadoAccount _tornadoAccount
    ) BasePaymaster(__entryPoint, owner) {
        TORNADO_INSTANCE = _tornadoInstance;
        TORNADO_ACCOUNT = _tornadoAccount;
    }

    // ----- BasePaymaster -----
    function _validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32,
        uint256
    )
        internal
        virtual
        override
        returns (bytes memory context, uint256 validationData)
    {
        if (userOp.sender != address(TORNADO_ACCOUNT)) revert InvalidSender();
        if (bytes4(userOp.callData[:4]) != TornadoAccount.withdraw.selector)
            revert InvalidSelector();

        (
            bytes memory proof,
            bytes32 root,
            bytes32 nullifierHash,
            address recipient,
            uint256 refund
        ) = abi.decode(
                userOp.callData[4:],
                (bytes, bytes32, bytes32, address, uint256)
            );
        if (recipient != address(this)) revert InvalidRecipient();
        _verifyWithdrawal(proof, root, nullifierHash, refund);

        //? Destination address is encoded in context and used in postOp to forward
        //? withdrawn funds after fee deduction
        context = userOp.paymasterAndData[
            PAYMASTER_AND_DATA_OFFSET:PAYMASTER_AND_DATA_OFFSET + 20
        ];
        validationData = 0;
    }

    function _postOp(
        IPaymaster.PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) internal override {
        //? If the first postOp call reverted (e.g. the destination rejected the
        //? forward), EntryPoint retries with `postOpReverted`. We intentionally
        //? early-return here so the full denomination stays in this contract.
        //? This is the anti-grief invariant.
        if (mode == IPaymaster.PostOpMode.postOpReverted) return;

        // context is exactly the 20-byte destination slice written in validation
        // forge-lint: disable-next-line(unsafe-typecast)
        address payable destination = payable(address(bytes20(context)));

        uint256 denomination = TORNADO_INSTANCE.denomination();
        uint256 fee = actualGasCost +
            (POST_OP_GAS_OVERHEAD * actualUserOpFeePerGas);
        if (fee > denomination) fee = denomination; // safety cap

        uint256 remainder = denomination - fee;
        (bool ok, ) = destination.call{value: remainder}("");
        if (!ok) revert ForwardFailed();
    }

    // ----- Internals -----
    function _verifyWithdrawal(
        bytes memory proof,
        bytes32 root,
        bytes32 nullifierHash,
        uint256 refund
    ) internal {
        //? Eth-specific requirement — cheap check first
        if (refund != 0) revert NonZeroRefund();

        // Validate the withdrawal params against tornado state
        if (TORNADO_INSTANCE.nullifierHashes(nullifierHash))
            revert NullifierAlreadySpent(nullifierHash);
        if (!TORNADO_INSTANCE.isKnownRoot(root)) revert UnknownRoot(root);

        IVerifier verifier = IVerifier(TORNADO_INSTANCE.verifier());
        bool valid = verifier.verifyProof(
            proof,
            [
                uint256(root),
                uint256(nullifierHash),
                uint256(uint160(address(this))), // recipient
                uint256(0), // relayer
                uint256(0), // fee
                uint256(0) // refund
            ]
        );
        if (!valid) revert InvalidProof();
    }

    receive() external payable {}
}
