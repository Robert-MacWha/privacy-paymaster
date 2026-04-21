// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Transaction, CommitmentPreimage} from "../Globals.sol";

interface IRailgunSmartWallet {
    function hashLeftRight(
        bytes32 _left,
        bytes32 _right
    ) external pure returns (bytes32);
    function hashCommitment(
        CommitmentPreimage memory _commitmentPreimage
    ) external pure returns (bytes32);

    // Commitment nullifiers (tree number -> nullifier -> seen)
    function nullifiers(
        uint256 treeNumber,
        bytes32 nullifier
    ) external view returns (bool);

    function validateTransaction(
        Transaction calldata _transaction
    ) external view returns (bool, string memory);

    function transact(Transaction[] calldata _transactions) external;
}
