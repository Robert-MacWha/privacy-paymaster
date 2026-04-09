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

    // ----- STATE -----
    ITornadoInstance public immutable TORNADO_INSTANCE;
    bytes4 public constant WITHDRAW_FUNCTION_SELECTOR =
        ITornadoInstance.withdraw.selector;

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
        PackedUserOperation calldata userOp,
        bytes32 /* userOpHash */,
        uint256 /* missingAccountFunds */
    ) external virtual override returns (uint256 validationData) {
        _requireFromEntryPoint();
        _withdrawFromTornado(userOp.callData, false);
        validationData = 0;
    }

    fallback() external {
        _withdrawFromTornado(msg.data, true);
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

        context = "";
        validationData = 0;
    }

    function _postOp(
        IPaymaster.PostOpMode,
        bytes calldata,
        uint256,
        uint256
    ) internal override {}

    // ----- Internals -----
    function _withdrawFromTornado(
        bytes calldata callData,
        bool execute
    ) internal {
        if (msg.sender != address(entryPoint())) revert CallerNotEntryPoint();
        if (bytes4(callData[:4]) != WITHDRAW_FUNCTION_SELECTOR)
            revert InvalidSelector();

        (
            bytes memory proof,
            bytes32 root,
            bytes32 nullifierHash,
            address payable recipient,
            uint256 refund
        ) = abi.decode(
                callData[4:],
                (bytes, bytes32, bytes32, address, uint256)
            );

        if (refund != 0) revert NonZeroRefund();

        // Execute the withdrawal on tornado
        if (execute) {
            TORNADO_INSTANCE.withdraw(
                proof,
                root,
                nullifierHash,
                recipient,
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
                uint256(uint160(address(recipient))),
                uint256(0), // relayer
                uint256(0), // fee
                uint256(0) // refund
            ]
        );
        if (!valid) revert InvalidProof();
    }

    receive() external payable {}
}
