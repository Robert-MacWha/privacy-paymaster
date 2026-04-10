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
    error InvalidRelayer();
    error NonZeroFee();
    error NonZeroRefund();
    error NullifierAlreadySpent();
    error UnknownRoot();
    error InvalidProof();

    /// ----- IMMUTABLES -----
    // The token address for this TC instance, or address(0) for ETH instances.
    address public immutable FEE_TOKEN;
    ITornadoInstance immutable TORNADO_INSTANCE =
        ITornadoInstance(address(this));

    constructor(
        IEntryPoint _entryPoint,
        ITornadoInstance _tornadoInstance,
        address _feeToken
    ) BasePrivacyAccount(_entryPoint, address(_tornadoInstance)) {
        FEE_TOKEN = _feeToken;
        TORNADO_INSTANCE = _tornadoInstance;
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

    /// @dev Because we want the full unshield to be credited to the paymaster
    /// which in turn credits the user's destination, the recipient in the unshield
    /// must be the paymaster while the relayer is used as the ultimate destination.
    /// A little unorthodox, but it works.
    ///
    /// @dev We do this rather than having the user pre-compute the fee so that
    /// for fee-less protocols (IE railgun) we can use the same paymaster logic.
    function evaluateUserOperation(
        bytes calldata unshieldCalldata
    )
        external
        view
        override
        returns (address destination, address feeToken, uint256 grossAmount)
    {
        address paymaster = msg.sender;
        Decoded memory d = _decode(unshieldCalldata);

        if (d.recipient != paymaster) revert InvalidRecipient();
        if (d.relayer == address(0)) revert InvalidRelayer();
        if (d.fee != 0) revert NonZeroFee();
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

        destination = d.relayer;
        feeToken = FEE_TOKEN;
        grossAmount = TORNADO_INSTANCE.denomination();
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
