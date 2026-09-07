// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @title IPrivacyPool
/// @notice Minimal interface for a Privacy Pools protocol pool (0xbow /
///         `privacy-pools-core`), sufficient for the fee adapter to
///         trigger a withdrawal and read the pool's asset.
///
/// @dev Verified against `0xbow-io/privacy-pools-core` (main, commit pushed
///      2026-08-31): `packages/contracts/src/interfaces/IPrivacyPool.sol`,
///      `contracts/PrivacyPool.sol`, `contracts/lib/ProofLib.sol`.
///      Kept self-contained (no upstream imports); struct field order is
///      positional and must match the deployed pool's ABI. Re-verify against
///      the pinned version actually deployed on the target chain before
///      mainnet. Native pools report the sentinel
///      `0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE` from `ASSET()`.
interface IPrivacyPool {
    /// @notice A withdrawal request.
    /// @param processooor The only address permitted to process this withdrawal.
    ///        The pool enforces `msg.sender == processooor` inside `withdraw`.
    /// @param data Opaque, caller-defined bytes. Hashed into the proof's `context`
    ///        public signal, so anything encoded here is bound by the zk proof.
    struct Withdrawal {
        address processooor;
        bytes data;
    }

    /// @notice A Groth16 proof plus its public signals.
    /// @dev Public signal ordering:
    ///        [0] newCommitmentHash
    ///        [1] existingNullifierHash
    ///        [2] withdrawnValue
    ///        [3] stateRoot
    ///        [4] stateTreeDepth
    ///        [5] ASPRoot
    ///        [6] ASPTreeDepth
    ///        [7] context = keccak256(abi.encode(withdrawal, SCOPE)) % SNARK_SCALAR_FIELD
    struct WithdrawProof {
        uint256[2] pA;
        uint256[2][2] pB;
        uint256[2] pC;
        uint256[8] pubSignals;
    }

    /// @notice Spends a note and pushes `withdrawnValue` of `ASSET()` to `msg.sender`.
    /// @dev Reverts unless `msg.sender == _withdrawal.processooor`, the proof verifies,
    ///      the state/ASP roots are known, the nullifier is unspent, and the proof's
    ///      `context` signal matches `keccak256(abi.encode(_withdrawal, SCOPE))`.
    function withdraw(Withdrawal memory _withdrawal, WithdrawProof memory _proof) external;

    /// @notice The asset held by this pool, or the native sentinel for the ETH pool.
    function ASSET() external view returns (address);

    /// @notice The pool's scope; bound into the proof `context`. Not needed by the
    ///         adapter (the pool checks context itself) but useful for SDK/tests.
    function SCOPE() external view returns (uint256);
}
