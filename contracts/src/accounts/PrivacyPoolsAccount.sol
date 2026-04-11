// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {
    IEntryPoint
} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";

import {BasePrivacyAccount} from "./BasePrivacyAccount.sol";

contract PrivacyPoolsAccount is BasePrivacyAccount {
    constructor(
        IEntryPoint _entryPoint,
        address _entrypoint
    ) BasePrivacyAccount(_entryPoint, _entrypoint) {}

    function previewUnshield(
        bytes calldata /* unshieldCalldata */
    ) external view override returns (address feeToken, uint256 feeAmount) {
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
