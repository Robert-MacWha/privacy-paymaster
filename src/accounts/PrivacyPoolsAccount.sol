// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {
    IEntryPoint
} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";

import {BasePrivacyAccount} from "./BasePrivacyAccount.sol";

/// Singleton 4337 account bound to a Privacy Pools v2 Entrypoint.
///
/// SKELETON: `evaluateUserOperation` is a disabled placeholder — the
/// full 0xbow Withdrawal/RelayData/WithdrawProof struct layouts and
/// public-input indexing are not yet vendored into the repo, so the
/// account MUST NOT be added to the paymaster's `approvedSenders`
/// whitelist until that validator body lands.
contract PrivacyPoolsAccount is BasePrivacyAccount {
    constructor(
        IEntryPoint _entryPoint,
        address _entrypoint
    ) BasePrivacyAccount(_entryPoint, _entrypoint) {}

    function evaluateUserOperation(
        bytes calldata /* unshieldCalldata */,
        address /* paymaster */
    )
        external
        view
        override
        returns (address expectedSender, address feeToken, uint256 grossAmount)
    {
        // TODO: once the Privacy Pools struct layout is vendored:
        //   - require selector == IEntrypoint.relay.selector
        //   - decode (Withdrawal w, WithdrawProof proof, uint256 sigScope)
        //   - require knownScope[sigScope] and asset == pool.asset
        //   - require w.processooor == address(entrypoint)
        //   - require RelayData.feeRecipient == paymaster
        //   - require relayFeeBPS <= pool.maxRelayFeeBPS
        //   - feeToken    = pool.asset
        //   - grossAmount = withdrawnValue * relayFeeBPS / 10_000 - vettingFee
        //   - expectedSender = address(this)
        revert("PrivacyPoolsAccount: not yet production-ready");
    }
}
