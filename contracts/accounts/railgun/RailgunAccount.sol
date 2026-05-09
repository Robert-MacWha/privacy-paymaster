// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {
    IEntryPoint
} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {
    UserOperationLib
} from "@account-abstraction/contracts/core/UserOperationLib.sol";

import {BasePrivacyAccount} from "../BasePrivacyAccount.sol";
import {IRailgunSmartWallet} from "./interfaces/IRailgunSmartWallet.sol";
import {
    Transaction,
    CommitmentPreimage,
    TokenData,
    TokenType
} from "./Globals.sol";

/// RailgunAccount is a BasePrivacyAccount impl for Railgun. It relies on a similar
/// mechanism for fee payment as Railgun's native relayer, in which the fee is paid
/// via an shielded transfer from the user's zk-wallet to the paymaster.
///
/// When sending a UserOp, the user must include the fee transaction's commitment
/// information in the paymasterAndData (random, asset, value). Using this and
/// the paymaster's hardcoded MASTER_PUBLIC_KEY,the paymaster can compute a
/// noteHash for the fee transfer and verify that it is included in the transaction's
/// commitments.
///
/// IMPORTANTLY, this means for RailgunAccount fees are received not by the paymaster,
/// but by the RAILGUN_SMART_WALLET zk-wallet.
contract RailgunAccount is BasePrivacyAccount {
    // ----- ERRORS -----
    error InvalidSelector(bytes4 selector);
    error InvalidTransactionsLength(uint256 length);
    error MissingFee(
        bytes32 master_public_key,
        bytes16 random,
        address asset,
        uint256 value
    );
    error NullifierAlreadyUsed(uint256 treeNumber, bytes32 nullifier);
    error InvalidTransaction(string reason);
    error PaymasterConfigLengthInvalid(uint256 length);

    IRailgunSmartWallet immutable RAILGUN_SMART_WALLET;
    /// The MPK for the paymaster's zk-wallet.
    bytes32 immutable MASTER_PUBLIC_KEY;

    uint256 constant PAYMASTER_AND_DATA_LENGTH =
        UserOperationLib.PAYMASTER_DATA_OFFSET + 32 * 3; // random | asset | value

    constructor(
        IEntryPoint _entryPoint,
        IRailgunSmartWallet _railgunSmartWallet,
        bytes32 _masterPublicKey
    ) BasePrivacyAccount(_entryPoint, address(_railgunSmartWallet)) {
        RAILGUN_SMART_WALLET = _railgunSmartWallet;
        MASTER_PUBLIC_KEY = _masterPublicKey;
    }

    function previewFee(
        bytes calldata feeCalldata,
        bytes calldata paymasterAndData
    ) external view override returns (address feeToken, uint256 feeAmount) {
        Transaction[] memory transactions = _decode(feeCalldata);

        if (transactions.length != 1)
            revert InvalidTransactionsLength(transactions.length);
        Transaction memory transaction = transactions[0];

        //? Extract the noteHash inputs from paymasterAndData
        (
            bytes16 random,
            address asset,
            uint120 value
        ) = _decodePaymasterAndData(paymasterAndData);

        //? Compute the noteHash for the fee transfer
        bytes32 commitment = _hashCommitment(
            MASTER_PUBLIC_KEY,
            random,
            asset,
            value
        );

        //? Verify that the fee transfer is included in the transaction's commitments
        bool commitmentFound = false;
        for (uint256 i = 0; i < transaction.commitments.length; i++) {
            if (transaction.commitments[i] == commitment) {
                commitmentFound = true;
            }
        }
        if (!commitmentFound)
            revert MissingFee(MASTER_PUBLIC_KEY, random, asset, value);

        //? Verify that the transaction is valid according to railgun's rules
        _validateTransaction(transaction);

        return (asset, value);
    }

    // ----- Internals -----
    function _decode(
        bytes calldata feeCalldata
    ) internal pure returns (Transaction[] memory transactions) {
        if (bytes4(feeCalldata[:4]) != IRailgunSmartWallet.transact.selector)
            revert InvalidSelector(bytes4(feeCalldata[:4]));

        transactions = abi.decode(feeCalldata[4:], (Transaction[]));
    }

    function _decodePaymasterAndData(
        bytes calldata paymasterAndData
    ) internal pure returns (bytes16 random, address asset, uint120 value) {
        if (paymasterAndData.length < PAYMASTER_AND_DATA_LENGTH) {
            revert PaymasterConfigLengthInvalid(paymasterAndData.length);
        }

        bytes memory data = paymasterAndData[
            UserOperationLib.PAYMASTER_DATA_OFFSET:
        ];
        (random, asset, value) = abi.decode(data, (bytes16, address, uint120));
    }

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

    function _validateTransaction(
        Transaction memory transaction
    ) internal view {
        // Check nullifiers
        uint256 treeNumber = transaction.boundParams.treeNumber;
        for (uint256 i = 0; i < transaction.nullifiers.length; ++i) {
            bytes32 nullifier = transaction.nullifiers[i];
            if (RAILGUN_SMART_WALLET.nullifiers(treeNumber, nullifier)) {
                revert NullifierAlreadyUsed(treeNumber, nullifier);
            }
        }

        (bool valid, string memory reason) = RAILGUN_SMART_WALLET
            .validateTransaction(transaction);
        if (!valid) revert InvalidTransaction(reason);
    }
}
