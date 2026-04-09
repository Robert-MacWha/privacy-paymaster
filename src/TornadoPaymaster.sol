// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IAccount} from "@account-abstraction/contracts/interfaces/IAccount.sol";
import {
    BasePaymaster,
    IEntryPoint,
    PackedUserOperation
} from "@account-abstraction/contracts/core/BasePaymaster.sol";
import {
    IPaymaster
} from "@account-abstraction/contracts/interfaces/IPaymaster.sol";
import {ITornadoInstance} from "./interfaces/ITornadoInstance.sol";
import {IVerifier} from "./interfaces/IVerifier.sol";

contract TornadoPaymaster is IAccount, BasePaymaster {
    // ----- ERRORS -----
    error InvalidSelector();
    error SenderNotSelf();
    error CallerNotEntryPoint();
    error NonZeroRefund();
    error NullifierAlreadySpent(bytes32 nullifierHash);
    error UnknownRoot(bytes32 root);
    error InvalidProof();
    error ForwardFailed();

    // ----- CONSTANTS -----
    ITornadoInstance public immutable TORNADO_INSTANCE;
    uint256 public constant POST_OP_GAS_OVERHEAD = 10_000;

    // ----- CONSTRUCTOR -----
    constructor(
        IEntryPoint __entryPoint,
        address owner,
        ITornadoInstance _tornadoInstance
    ) BasePaymaster(__entryPoint, owner) {
        TORNADO_INSTANCE = _tornadoInstance;
    }

    // ----- IAccount -----
    function validateUserOp(
        PackedUserOperation calldata,
        bytes32,
        uint256
    ) external virtual override returns (uint256 validationData) {
        _requireFromEntryPoint();
        validationData = 0;
    }

    /// @notice Entry point calls this function to execute the withdrawal after
    /// validating the proof and other params in `validatePaymasterUserOp`.
    function withdraw(
        bytes calldata proof,
        bytes32 root,
        bytes32 nullifierHash,
        address destination,
        uint256 refund
    ) external {
        _withdrawFromTornado(proof, root, nullifierHash, refund, true);
    }

    // ----- Paymaster -----
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
        if (userOp.sender != address(this)) revert SenderNotSelf();
        if (bytes4(userOp.callData[:4]) != this.withdraw.selector)
            revert InvalidSelector();

        (, , , address destination, ) = abi.decode(
            userOp.callData[4:],
            (bytes, bytes32, bytes32, address, uint256)
        );

        //? Store the destination in the context to be used in _postOp.
        context = abi.encode(destination);
        validationData = 0;
    }

    function _postOp(
        IPaymaster.PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) internal override {
        if (mode == IPaymaster.PostOpMode.postOpReverted) return;

        address payable destination = payable(abi.decode(context, (address)));

        uint256 denomination = TORNADO_INSTANCE.denomination();
        uint256 fee = actualGasCost +
            (POST_OP_GAS_OVERHEAD * actualUserOpFeePerGas);
        if (fee > denomination) fee = denomination; // safety cap

        uint256 remainder = denomination - fee;
        (bool ok, ) = destination.call{value: remainder}("");
        if (!ok) revert ForwardFailed();
    }

    // ----- Internals -----
    function _withdrawFromTornado(
        bytes memory proof,
        bytes32 root,
        bytes32 nullifierHash,
        uint256 refund,
        bool execute
    ) internal {
        if (msg.sender != address(entryPoint())) revert CallerNotEntryPoint();
        if (refund != 0) revert NonZeroRefund();

        // Execute the withdrawal on tornado
        if (execute) {
            TORNADO_INSTANCE.withdraw(
                proof,
                root,
                nullifierHash,
                payable(address(this)), // recipient
                payable(address(0)), // relayer
                uint256(0), // fee
                refund
            );
            return;
        }

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
