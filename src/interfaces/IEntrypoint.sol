// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// Minimal Privacy Pools v2 (0xbow) Entrypoint surface.
///
/// Only what the paymaster adapter needs. Full types live in the 0xbow
/// repo; we decode the calldata shape directly in
/// `PrivacyPoolsAdapter.validateUnshield` so the adapter stays
/// dependency-light.
///
/// Shape of `relay(Withdrawal, WithdrawProof, uint256 scope)`:
///
///   struct Withdrawal {
///       address processooor;  // MUST equal the Entrypoint for relayed withdrawals
///       bytes   data;         // abi.encode(RelayData)
///   }
///   struct RelayData {
///       address recipient;       // end user recipient (irrelevant to paymaster)
///       address feeRecipient;    // MUST equal paymaster
///       uint256 relayFeeBPS;     // fee in bps out of withdrawnValue
///   }
///   struct WithdrawProof {
///       uint256[8] proof;        // groth16
///       uint256[]  pubSignals;   // [..., withdrawnValue, ...]
///   }
interface IEntrypoint {
    function relay(
        bytes calldata withdrawalBlob,
        bytes calldata proofBlob,
        uint256 scope
    ) external;
}
