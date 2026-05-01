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

contract RailgunAccount is BasePrivacyAccount {
    // ----- ERRORS -----
    error InvalidSelector(bytes4 selector);
    error InvalidTransactionsLength(uint256 length);
    error InvalidCommitmentsLength(uint256 length);
    error InvalidCommitment(bytes32 commitment);
    error InvalidTransaction(string reason);
    error PaymasterConfigLengthInvalid(uint256 length);

    IRailgunSmartWallet immutable RAILGUN_SMART_WALLET;
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
        if (transaction.commitments.length == 0)
            revert InvalidCommitmentsLength(0);

        (
            bytes32 random,
            address asset,
            uint256 value
        ) = _decodePaymasterAndData(paymasterAndData);
        bytes32 commitment = _hashCommitment(
            MASTER_PUBLIC_KEY,
            random,
            asset,
            value
        );

        if (transaction.commitments[0] != commitment)
            revert InvalidCommitment(transaction.commitments[0]);

        (bool valid, string memory reason) = RAILGUN_SMART_WALLET
            .validateTransaction(transaction);
        if (!valid) revert InvalidTransaction(reason);

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
    ) internal pure returns (bytes32 random, address asset, uint256 value) {
        if (paymasterAndData.length < PAYMASTER_AND_DATA_LENGTH) {
            revert PaymasterConfigLengthInvalid(paymasterAndData.length);
        }

        bytes memory data = paymasterAndData[
            UserOperationLib.PAYMASTER_DATA_OFFSET:
        ];
        (random, asset, value) = abi.decode(data, (bytes32, address, uint256));
    }

    function _hashCommitment(
        bytes32 master_public_key,
        bytes32 random,
        address asset,
        uint256 value
    ) internal view returns (bytes32) {
        bytes32 npk = RAILGUN_SMART_WALLET.hashLeftRight(
            master_public_key,
            random
        );

        CommitmentPreimage memory commitmentPreimage = CommitmentPreimage({
            npk: npk,
            token: TokenData({
                tokenType: TokenType.ERC20,
                tokenAddress: asset,
                tokenSubID: 0
            }),
            value: uint120(value)
        });

        return RAILGUN_SMART_WALLET.hashCommitment(commitmentPreimage);
    }
}
