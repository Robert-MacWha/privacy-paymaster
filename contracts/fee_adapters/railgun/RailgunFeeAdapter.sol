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
import {IRailgunSmartWallet} from "./interfaces/IRailgunSmartWallet.sol";
import {
    Transaction,
    CommitmentPreimage,
    TokenData,
    TokenType
} from "./Globals.sol";

struct RailgunFeeData {
    bytes16 random;
    address asset;
    uint120 value;
    Transaction transaction;
}

contract RailgunFeeAdapter is IFeeAdapter {
    // ----- ERRORS -----
    error MissingFee(
        bytes32 master_public_key,
        bytes16 random,
        address asset,
        uint120 value
    );
    error AdaptParamsAreNotSender(bytes32 adaptParams, address sender);

    /// ----- IMMUTABLES -----
    IRailgunSmartWallet public immutable RAILGUN_SMART_WALLET;
    /// The MPK for the paymaster's zk-wallet.
    bytes32 immutable MASTER_PUBLIC_KEY;

    constructor(
        IRailgunSmartWallet _railgunSmartWallet,
        bytes32 _masterPublicKey
    ) {
        RAILGUN_SMART_WALLET = _railgunSmartWallet;
        MASTER_PUBLIC_KEY = _masterPublicKey;
    }

    function collectFee(
        PackedUserOperation calldata userOp
    ) external returns (address feeToken, uint256 feePaid) {
        (, bytes calldata adapterData) = PaymasterLib.decodePaymasterAndData(
            userOp.paymasterAndData
        );
        RailgunFeeData memory d = abi.decode(adapterData, (RailgunFeeData));

        feeToken = d.asset;
        feePaid = d.value;

        //? Verify that the railgun transaction is cryptographically bound to
        //? this UserOp's sender
        if (
            d.transaction.boundParams.adaptParams !=
            bytes32(bytes20(userOp.sender))
        )
            revert AdaptParamsAreNotSender(
                d.transaction.boundParams.adaptParams,
                userOp.sender
            );

        //? Verify that the fee transfer is included in the transaction's commitments
        bytes32 expectedCommitment = _hashCommitment(
            MASTER_PUBLIC_KEY,
            d.random,
            d.asset,
            d.value
        );

        bool commitmentFound = false;
        for (uint256 i = 0; i < d.transaction.commitments.length; i++) {
            if (d.transaction.commitments[i] == expectedCommitment) {
                commitmentFound = true;
            }
        }
        if (!commitmentFound)
            revert MissingFee(MASTER_PUBLIC_KEY, d.random, d.asset, d.value);

        Transaction[] memory transactions = new Transaction[](1);
        transactions[0] = d.transaction;
        RAILGUN_SMART_WALLET.transact(transactions);
    }

    /// Calculate the commitment hash for the fee transfer based on the MPK, random, asset, and value.
    function _hashCommitment(
        bytes32 master_public_key,
        bytes16 random,
        address asset,
        uint120 value
    ) internal view returns (bytes32) {
        bytes32 npk = RAILGUN_SMART_WALLET.hashLeftRight(
            master_public_key,
            bytes32(uint256(uint128(random)))
        );

        CommitmentPreimage memory commitmentPreimage = CommitmentPreimage({
            npk: npk,
            token: TokenData({
                tokenType: TokenType.ERC20,
                tokenAddress: asset,
                tokenSubID: 0
            }),
            value: value
        });

        return RAILGUN_SMART_WALLET.hashCommitment(commitmentPreimage);
    }
}
