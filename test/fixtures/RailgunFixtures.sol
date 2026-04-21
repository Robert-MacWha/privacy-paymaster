// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

// Hardcoded fixtures for RailgunAccount tests.
library RailgunFixtures {
    // ----- Network / fork config -----
    uint256 internal constant FORK_BLOCK = 10_000_000;

    // Sepolia EntryPoint v0.8.0.
    address internal constant ENTRY_POINT_ADDR =
        0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108;

    address internal constant RAILGUN_SMART_WALLET_ADDR =
        0xeCFCf3b4eC647c4Ca6D49108b311b7a7C9543fea;

    address payable internal constant PAYMASTER =
        payable(address(0x2C6ddd76DD36CDdE9CB967a8ae66767b456EB1Ba));

    bytes32 internal constant MASTER_PUBLIC_KEY = hex"01";
}
