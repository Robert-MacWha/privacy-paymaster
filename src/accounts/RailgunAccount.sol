// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {
    IEntryPoint
} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";

import {BasePrivacyAccount} from "./BasePrivacyAccount.sol";

/// Singleton 4337 account bound to a Railgun SmartWallet (or RelayAdapt).
///
/// SKELETON: `evaluateUserOperation` is a disabled placeholder — see
/// the TODO block in the body. Critically, its production version
/// REJECTS `transact([tx1, tx2, ...])` calls with `txs.length > 1`:
/// users who want batched Railgun ops put the extras in the uniform
/// account's `tail: Call[]` array instead, so the paymaster never has
/// to reason about multi-unshield gas accounting or partial-failure
/// modes.
contract RailgunAccount is BasePrivacyAccount {
    constructor(
        IEntryPoint _entryPoint,
        address _railgun
    ) BasePrivacyAccount(_entryPoint, _railgun) {}

    function evaluateUserOperation(
        bytes calldata /* unshieldCalldata */,
        address /* paymaster */
    )
        external
        view
        override
        returns (address expectedSender, address feeToken, uint256 grossAmount)
    {
        // TODO: once the Railgun Transaction struct is vendored:
        //   - require selector == IRailgunSmartWallet.transact.selector
        //   - decode Transaction[] txs; require txs.length == 1
        //     (batching goes in the uniform account's `tail` array)
        //   - require txs[0].boundParams.unshield != NONE
        //   - require txs[0].boundParams.adaptContract == paymaster
        //   - require txs[0].boundParams.chainID == block.chainid
        //   - resolve TokenData -> feeToken
        //   - require recipient derived from npk == paymaster
        //   - grossAmount = unshieldPreimage.value
        //                 - (unshieldPreimage.value * live unshieldFee()) / 10_000
        //     reading the live fee from RailgunSmartWallet so governance
        //     fee updates don't silently break pricing
        //   - expectedSender = address(this)
        revert("RailgunAccount: not yet production-ready");
    }
}
