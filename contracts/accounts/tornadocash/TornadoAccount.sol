// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {
    IEntryPoint
} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";

import {BasePrivacyAccount} from "../BasePrivacyAccount.sol";
import {ITornadoInstance} from "./interfaces/ITornadoInstance.sol";
import {IVerifier} from "./interfaces/IVerifier.sol";

contract TornadoAccount is BasePrivacyAccount {
    // ----- ERRORS -----
    error InvalidSelector(bytes4 selector);
    error InvalidRecipient(address recipient);
    error InvalidRelayer(address relayer);
    error InvalidFee(uint256 fee);
    error NonZeroRefund();
    error NullifierAlreadySpent();
    error UnknownRoot();
    error InvalidProof();

    /// ----- IMMUTABLES -----
    // The token address for this TC instance, or address(0) for ETH instances.
    address public immutable FEE_TOKEN;
    ITornadoInstance immutable TORNADO_INSTANCE;
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

    function previewFee(
        bytes calldata feeCalldata,
        bytes calldata
    ) external view override returns (address feeToken, uint256 feeAmount) {
        address paymaster = msg.sender;
        Decoded memory d = _decode(feeCalldata);

        if (d.recipient == address(0)) revert InvalidRecipient(d.recipient);
        if (d.relayer != paymaster) revert InvalidRelayer(d.relayer);
        if (d.fee == 0) revert InvalidFee(d.fee);
        if (d.fee > TORNADO_INSTANCE_DENOMINATION) revert InvalidFee(d.fee);
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
        bytes calldata feeCalldata
    ) internal pure returns (Decoded memory d) {
        if (bytes4(feeCalldata[:4]) != ITornadoInstance.withdraw.selector)
            revert InvalidSelector(bytes4(feeCalldata[:4]));

        (
            d.proof,
            d.root,
            d.nullifierHash,
            d.recipient,
            d.relayer,
            d.fee,
            d.refund
        ) = abi.decode(
            feeCalldata[4:],
            (bytes, bytes32, bytes32, address, address, uint256, uint256)
        );
    }

    function _verifyProof(
        bytes memory proof,
        bytes32 root,
        bytes32 nullifierHash,
        address recipient,
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
                    uint256(uint160(recipient)),
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
