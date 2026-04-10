// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// Always reverts on any call (not just ETH receives), used to test
/// execute() unshield-failure and tail-call-failure paths.
contract CallReverter {
    fallback() external payable {
        revert("CallReverter: nope");
    }
}
