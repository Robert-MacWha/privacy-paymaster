// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {
    IEntryPoint
} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";

import {BasePrivacyAccount} from "./BasePrivacyAccount.sol";
import {ITornadoInstance} from "../interfaces/ITornadoInstance.sol";
import {IVerifier} from "../interfaces/IVerifier.sol";

/// Singleton 4337 account bound to a single Tornado Cash instance.
contract TornadoAccount is BasePrivacyAccount {
    // ----- ERRORS -----
    error InvalidSelector();
    error InvalidRecipient();
    error NonZeroRelayer();
    error NonZeroFee();
    error NonZeroRefund();
    error NullifierAlreadySpent();
    error UnknownRoot();
    error InvalidProof();

    /// ----- IMMUTABLES -----
    // The token address for this TC instance, or address(0) for ETH instances.
    address private immutable FEE_TOKEN;

    constructor(
        IEntryPoint _entryPoint,
        ITornadoInstance _tornadoInstance,
        address _feeToken
    ) BasePrivacyAccount(_entryPoint, address(_tornadoInstance)) {
        FEE_TOKEN = _feeToken;
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

    function evaluateUserOperation(
        bytes calldata unshieldCalldata
    ) external view override returns (address feeToken, uint256 grossAmount) {
        address paymaster = msg.sender;
        Decoded memory d = _decode(unshieldCalldata);

        if (d.recipient != paymaster) revert InvalidRecipient();
        if (d.relayer != address(0)) revert NonZeroRelayer();
        if (d.fee != 0) revert NonZeroFee();
        if (d.refund != 0) revert NonZeroRefund();

        ITornadoInstance tc = ITornadoInstance(PROTOCOL_TARGET);
        if (tc.nullifierHashes(d.nullifierHash)) revert NullifierAlreadySpent();
        if (!tc.isKnownRoot(d.root)) revert UnknownRoot();

        _verifyProof(
            tc,
            d.proof,
            d.root,
            d.nullifierHash,
            d.recipient,
            d.relayer,
            d.fee,
            d.refund
        );

        feeToken = FEE_TOKEN;
        grossAmount = tc.denomination();
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
        ITornadoInstance tc,
        bytes memory proof,
        bytes32 root,
        bytes32 nullifierHash,
        address paymaster,
        address relayer,
        uint256 fee,
        uint256 refund
    ) internal view {
        IVerifier verifier = IVerifier(tc.verifier());
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
