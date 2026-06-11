// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {
    PackedUserOperation
} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";

import {PaymasterLib} from "../../libraries/PaymasterLib.sol";
import {IFeeAdapter} from "../../interfaces/IFeeAdapter.sol";
import {IRailgunSmartWallet} from "./interfaces/IRailgunSmartWallet.sol";
import {
    Transaction,
    CommitmentPreimage,
    TokenData,
    TokenType
} from "./Globals.sol";

contract RailgunFeeAdapter is IFeeAdapter {
    struct AdapterData {
        bytes16 random;
        address asset;
        uint120 value;
        Transaction[] transactions;
    }

    // ----- ERRORS -----
    error MalformedAdapterData();
    error AdaptParamsAreNotSender(bytes32 adaptParams, bytes32 sender);
    error MissingFee(
        bytes32 master_public_key,
        bytes16 random,
        address asset,
        uint120 value
    );
    error RailgunTransactionFailed(bytes reason);

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
    )
        external
        returns (address feeToken, uint256 feePaid, address refundRecipient)
    {
        AdapterData memory d;
        try this.decodeAdapterData(userOp.paymasterAndData) returns (
            AdapterData memory decoded
        ) {
            d = decoded;
        } catch {
            revert MalformedAdapterData();
        }
        feeToken = d.asset;
        feePaid = d.value;
        // TODO: Add an optional refund recipient in the AdapterData struct
        refundRecipient = address(0);

        _verifyTransactions(userOp.sender, d);
        try RAILGUN_SMART_WALLET.transact(d.transactions) {} catch (
            bytes memory reason
        ) {
            revert RailgunTransactionFailed(reason);
        }
    }

    function decodeAdapterData(
        bytes calldata paymasterAndData
    ) external pure returns (AdapterData memory) {
        PaymasterLib.PaymasterData memory pd = PaymasterLib
            .decodePaymasterAndData(paymasterAndData);
        return abi.decode(pd.adapterData, (AdapterData));
    }

    /// Verifies the provided railgun transactions
    ///
    /// All transactions must have their boundParams.adaptParams set to the paymaster's address to
    /// prevent griefing attacks against users.
    ///
    /// At least one transaction must include a commitment matching the expected commitment for the fee transfer.
    function _verifyTransactions(
        address sender,
        AdapterData memory adapterData
    ) internal view {
        bytes32 expectedCommitment = _hashCommitment(
            MASTER_PUBLIC_KEY,
            adapterData.random,
            adapterData.asset,
            adapterData.value
        );

        bool commitmentFound = false;
        for (uint256 i = 0; i < adapterData.transactions.length; i++) {
            Transaction memory t = adapterData.transactions[i];
            if (t.boundParams.adaptParams != bytes32(uint256(uint160(sender))))
                revert AdaptParamsAreNotSender(
                    t.boundParams.adaptParams,
                    bytes32(uint256(uint160(sender)))
                );

            for (uint256 j = 0; j < t.commitments.length; j++) {
                if (t.commitments[j] == expectedCommitment) {
                    commitmentFound = true;
                }
            }
        }

        if (!commitmentFound)
            revert MissingFee(
                MASTER_PUBLIC_KEY,
                adapterData.random,
                adapterData.asset,
                adapterData.value
            );
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
