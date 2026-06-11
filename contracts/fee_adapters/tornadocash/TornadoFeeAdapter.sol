// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {
    PackedUserOperation
} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {
    UserOperationLib
} from "@account-abstraction/contracts/core/UserOperationLib.sol";

import {PaymasterLib} from "../../libraries/PaymasterLib.sol";
import {IFeeAdapter} from "../../interfaces/IFeeAdapter.sol";
import {ITornadoInstance} from "./interfaces/ITornadoInstance.sol";

contract TornadoFeeAdapter is IFeeAdapter {
    struct AdapterData {
        bytes proof;
        bytes32 root;
        bytes32 nullifierHash;
        address payable recipient;
        address payable relayer;
        uint256 fee;
        uint256 refund;
    }

    // ----- ERRORS -----
    error MalformedAdapterData();
    error InvalidRelayer(address expected, address actual);
    error CallGasLimitNonZero(uint256 callGasLimit);
    error TornadoWithdrawalFailed(bytes reason);

    /// ----- IMMUTABLES -----
    ITornadoInstance public immutable TORNADO_INSTANCE;
    // The token address for this TC instance, or address(0) for ETH instances.
    address public immutable FEE_TOKEN;
    uint256 public immutable TORNADO_INSTANCE_DENOMINATION;

    constructor(ITornadoInstance _tornadoInstance) {
        TORNADO_INSTANCE = _tornadoInstance;
        FEE_TOKEN = _handleToken(address(_tornadoInstance));
        TORNADO_INSTANCE_DENOMINATION = _tornadoInstance.denomination();
    }

    function collectFee(
        PackedUserOperation calldata userOp
    )
        external
        returns (address feeToken, uint256 feePaid, address refundRecipient)
    {
        address paymaster = msg.sender;
        AdapterData memory d;
        try this.decodeAdapterData(userOp.paymasterAndData) returns (
            AdapterData memory decoded
        ) {
            d = decoded;
        } catch {
            revert MalformedAdapterData();
        }
        feeToken = FEE_TOKEN;
        feePaid = d.fee;
        refundRecipient = d.recipient;

        if (d.relayer != paymaster) revert InvalidRelayer(paymaster, d.relayer);

        // Two possible cases.  Either the recipient is the userOp sender, in which
        // case we permit calls in the execution phase to allow the user to perform
        // secondary actions (IE swap on a DEX). Or the recipient is a different address,
        // in which case we limit the callGasLimit to 0 to prevent profitable griefing
        // attacks against users.
        uint256 callGasLimit = UserOperationLib.unpackCallGasLimit(userOp);
        if (d.recipient != userOp.sender && callGasLimit != 0)
            revert CallGasLimitNonZero(callGasLimit);

        try
            TORNADO_INSTANCE.withdraw(
                d.proof,
                d.root,
                d.nullifierHash,
                d.recipient,
                d.relayer,
                d.fee,
                d.refund
            )
        {} catch (bytes memory reason) {
            revert TornadoWithdrawalFailed(reason);
        }
    }

    function decodeAdapterData(
        bytes calldata paymasterAndData
    ) external pure returns (AdapterData memory) {
        PaymasterLib.PaymasterData memory pd = PaymasterLib
            .decodePaymasterAndData(paymasterAndData);
        return abi.decode(pd.adapterData, (AdapterData));
    }

    /// ERC20Tornado exposes a `token()` getter, ETHTornado does not.
    /// Returns the ERC20 address for token instances, or address(0) for ETH instances.
    function _handleToken(address tcInstance) internal view returns (address) {
        (bool ok, bytes memory ret) = tcInstance.staticcall(
            abi.encodeWithSignature("token()")
        );
        if (ok && ret.length == 32) {
            return abi.decode(ret, (address));
        }
        return address(0);
    }
}
