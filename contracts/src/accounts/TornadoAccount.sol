// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {
    IEntryPoint
} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";

import {BasePrivacyAccount} from "./BasePrivacyAccount.sol";
import {ITornadoInstance} from "../interfaces/ITornadoInstance.sol";
import {IVerifier} from "../interfaces/IVerifier.sol";

contract TornadoAccount is BasePrivacyAccount {
    // ----- ERRORS -----
    error InvalidSelector();
    error InvalidRecipient();
    error InvalidRelayer();
    error InvalidFee();
    error NonZeroRefund();
    error NullifierAlreadySpent();
    error UnknownRoot();
    error InvalidProof();

    /// ----- IMMUTABLES -----
    // The token address for this TC instance, or address(0) for ETH instances.
    address public immutable FEE_TOKEN;
    ITornadoInstance immutable TORNADO_INSTANCE =
        ITornadoInstance(address(this));
    uint256 public immutable TORNADO_INSTANCE_DENOMINATION;

    constructor(
        IEntryPoint _entryPoint,
        ITornadoInstance _tornadoInstance,
        address _feeToken
    ) BasePrivacyAccount(_entryPoint, address(_tornadoInstance)) {
        FEE_TOKEN = _feeToken;
        TORNADO_INSTANCE = _tornadoInstance;
        TORNADO_INSTANCE_DENOMINATION = _tornadoInstance.denomination();
    }

    // ----- IPrivacyAccount -----
    struct Decoded {
        bytes proof;
        bytes32 root;
        bytes32 nullifierHash;
        address recipient;
        address relayer;
        uint256 fee;
        uint256 refund;
    }

    function previewUnshield(
        bytes calldata unshieldCalldata
    ) external view override returns (address feeToken, uint256 feeAmount) {
        address paymaster = msg.sender;
        Decoded memory d = _decode(unshieldCalldata);

        if (d.recipient == address(0)) revert InvalidRecipient();
        if (d.relayer != paymaster) revert InvalidRelayer();
        if (d.fee == 0) revert InvalidFee();
        if (d.fee > TORNADO_INSTANCE_DENOMINATION) revert InvalidFee();
        if (d.refund != 0) revert NonZeroRefund();

        if (TORNADO_INSTANCE.nullifierHashes(d.nullifierHash))
            revert NullifierAlreadySpent();
        if (!TORNADO_INSTANCE.isKnownRoot(d.root)) revert UnknownRoot();

        _verifyProof(
            d.proof,
            d.root,
            d.nullifierHash,
            d.recipient,
            d.relayer,
            d.fee,
            d.refund
        );

        feeToken = FEE_TOKEN;
        feeAmount = d.fee;
    }

    // ----- Internals -----
    function _decode(
        bytes calldata unshieldCalldata
    ) internal pure returns (Decoded memory d) {
        if (bytes4(unshieldCalldata[:4]) != ITornadoInstance.withdraw.selector)
            revert InvalidSelector();

        (
            d.proof,
            d.root,
            d.nullifierHash,
            d.recipient,
            d.relayer,
            d.fee,
            d.refund
        ) = abi.decode(
            unshieldCalldata[4:],
            (bytes, bytes32, bytes32, address, address, uint256, uint256)
        );
    }

    function _verifyProof(
        bytes memory proof,
        bytes32 root,
        bytes32 nullifierHash,
        address paymaster,
        address relayer,
        uint256 fee,
        uint256 refund
    ) internal view {
        IVerifier verifier = IVerifier(TORNADO_INSTANCE.verifier());
        try
            verifier.verifyProof(
                proof,
                [
                    uint256(root),
                    uint256(nullifierHash),
                    uint256(uint160(paymaster)),
                    uint256(uint160(relayer)),
                    fee,
                    refund
                ]
            )
        returns (bool valid) {
            if (!valid) revert InvalidProof();
        } catch {
            revert InvalidProof();
        }
    }
}
