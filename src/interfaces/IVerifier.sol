// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface IVerifier {
    function verifyProof(
        bytes memory proof,
        uint256[6] memory input
    ) external returns (bool);
}
