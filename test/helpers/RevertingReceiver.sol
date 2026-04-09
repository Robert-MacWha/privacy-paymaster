// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @notice Always-reverting receive hook, used in the grief-path test to
/// force the first `_postOp` call to revert so EntryPoint retries with
/// `postOpReverted` and the paymaster absorbs the full denomination.
contract RevertingReceiver {
    receive() external payable {
        revert("nope");
    }
}
