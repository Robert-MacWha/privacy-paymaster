// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {
    IEntryPoint
} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";

import {BasePrivacyAccount} from "./BasePrivacyAccount.sol";

contract RailgunAccount is BasePrivacyAccount {
    constructor(
        IEntryPoint _entryPoint,
        address _railgun
    ) BasePrivacyAccount(_entryPoint, _railgun) {}

    function previewUnshield(
        bytes calldata /* unshieldCalldata */
    ) external view override returns (address feeToken, uint256 feeAmount) {
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
