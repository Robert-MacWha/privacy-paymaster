// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {
    IEntryPoint
} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";

import {BasePrivacyAccount} from "./BasePrivacyAccount.sol";
import {ITornadoInstance} from "../interfaces/ITornadoInstance.sol";
import {IVerifier} from "../interfaces/IVerifier.sol";

/// Singleton 4337 account bound to a single Tornado Cash ETH instance.
///
/// All protocol-specific validation lives in `evaluateUserOperation`:
/// selector, zero relayer/fee/refund, paymaster recipient, nullifier,
/// root, and proof. Execution and tail handling come from
/// `BasePrivacyAccount`.
contract TornadoAccount is BasePrivacyAccount {
    // ----- ERRORS -----
    error InvalidSelector();
    error InvalidRecipient();
    error NonZeroRelayerOrFee();
    error NonZeroRefund();
    error NullifierAlreadySpent();
    error UnknownRoot();
    error InvalidProof();

    constructor(
        IEntryPoint _entryPoint,
        ITornadoInstance _tornadoInstance
    ) BasePrivacyAccount(_entryPoint, address(_tornadoInstance)) {}

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
        bytes calldata unshieldCalldata,
        address paymaster
    )
        external
        view
        override
        returns (address expectedSender, address feeToken, uint256 grossAmount)
    {
        Decoded memory d = _decode(unshieldCalldata);

        if (d.recipient != paymaster) revert InvalidRecipient();
        if (d.relayer != address(0) || d.fee != 0) revert NonZeroRelayerOrFee();
        // Eth-specific requirement
        if (d.refund != 0) revert NonZeroRefund();

        ITornadoInstance tc = ITornadoInstance(PROTOCOL_TARGET);
        if (tc.nullifierHashes(d.nullifierHash)) revert NullifierAlreadySpent();
        if (!tc.isKnownRoot(d.root)) revert UnknownRoot();

        _verifyProof(tc, d.proof, d.root, d.nullifierHash, paymaster);

        expectedSender = address(this);
        feeToken = address(0); // classic TC ETH pool
        grossAmount = tc.denomination();
    }

    // ----- Internals -----
    /// Split out to keep `evaluateUserOperation`'s stack under the EVM's
    /// 16-slot limit.
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

    /// Verifier call is pure; safe under 4337 staked storage rules.
    function _verifyProof(
        ITornadoInstance tc,
        bytes memory proof,
        bytes32 root,
        bytes32 nullifierHash,
        address paymaster
    ) internal view {
        IVerifier verifier = IVerifier(tc.verifier());
        try
            verifier.verifyProof(
                proof,
                [
                    uint256(root),
                    uint256(nullifierHash),
                    uint256(uint160(paymaster)),
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
