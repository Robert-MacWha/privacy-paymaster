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

contract TornadoPaymaster is BasePaymaster {
    // ----- ERRORS -----
    error InvalidSelector();
    error InvalidSender();
    error InvalidRecipient();
    error NonZeroRefund();
    error NullifierAlreadySpent(bytes32 nullifierHash);
    error UnknownRoot(bytes32 root);
    error InvalidProof();

    // ----- CONSTANTS -----
    ITornadoInstance public immutable TORNADO_INSTANCE;
    TornadoAccount public immutable TORNADO_ACCOUNT;
    // gas overhead to cover postOp execution after the final transfer. Best-effort
    // estimation to prevent griefing while minimizing overpayment by users.
    uint256 public constant POST_OP_GAS_OVERHEAD = 1e5;
    // budget for final call to recipient in postOp. We want to forward as much
    // as possible, but also must place a hard cap to prevent griefing.
    uint256 public constant FORWARD_GAS_BUDGET = 1e4;
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

    receive() external payable {}

    // aderyn-ignore-next-line(centralization-risk)
    function sweep(address payable to) external onlyOwner {
        (bool ok, ) = to.call{value: address(this).balance}("");
        require(ok, "sweep failed");
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
        bool senderIsValid = userOp.sender == address(TORNADO_ACCOUNT);
        if (!senderIsValid) revert InvalidSender();

        bool isWithdraw = bytes4(userOp.callData[:4]) ==
            TornadoAccount.withdraw.selector;
        if (!isWithdraw) revert InvalidSelector();

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
        IPaymaster.PostOpMode,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) internal override {
        // context is exactly the 20-byte destination slice written in validation
        // forge-lint: disable-next-line(unsafe-typecast)
        address payable destination = payable(address(bytes20(context)));

        uint256 denomination = TORNADO_INSTANCE.denomination();
        uint256 fee = actualGasCost +
            (POST_OP_GAS_OVERHEAD * actualUserOpFeePerGas);
        if (fee > denomination) fee = denomination; // safety cap

        uint256 remainder = denomination - fee;

        //? Best-effort forward. If the destination rejects, we MUST NOT
        //? revert. Reverting here would roll back the withdrawal, but the
        //? EntryPoint would still charge us for the gas, enabling griefing attacks.
        // aderyn-ignore-next-line(unchecked-low-level-call)
        destination.call{value: remainder, gas: FORWARD_GAS_BUDGET}("");
    }

    // ----- Internals -----
    function _verifyWithdrawal(
        bytes memory proof,
        bytes32 root,
        bytes32 nullifierHash,
        uint256 refund
    ) internal {
        // Eth-specific requirement
        if (refund != 0) revert NonZeroRefund();

        if (TORNADO_INSTANCE.nullifierHashes(nullifierHash))
            revert NullifierAlreadySpent(nullifierHash);
        if (!TORNADO_INSTANCE.isKnownRoot(root)) revert UnknownRoot(root);

        IVerifier verifier = IVerifier(TORNADO_INSTANCE.verifier());

        //? The verifier can revert on malformed proofs. Catch and revert with
        //? standard error.
        try
            verifier.verifyProof(
                proof,
                [
                    uint256(root),
                    uint256(nullifierHash),
                    uint256(uint160(address(this))), // recipient
                    uint256(0), // relayer
                    uint256(0), // fee
                    uint256(0) // refund
                ]
            )
        returns (bool valid) {
            if (!valid) revert InvalidProof();
        } catch {
            revert InvalidProof();
        }
    }
}
