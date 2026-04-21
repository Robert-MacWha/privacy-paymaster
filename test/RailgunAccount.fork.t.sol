// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {
    IEntryPoint
} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";

import {RailgunAccount} from "../contracts/accounts/railgun/RailgunAccount.sol";
import {
    IRailgunSmartWallet
} from "../contracts/accounts/railgun/interfaces/IRailgunSmartWallet.sol";

import {RailgunFixtures} from "./fixtures/RailgunFixtures.sol";

contract RailgunAccountForkTest is Test {
    IRailgunSmartWallet internal railgun;
    RailgunAccount internal account;
    uint256 internal denomination;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("sepolia"), RailgunFixtures.FORK_BLOCK);

        railgun = IRailgunSmartWallet(
            RailgunFixtures.RAILGUN_SMART_WALLET_ADDR
        );
        account = new RailgunAccount(
            IEntryPoint(RailgunFixtures.ENTRY_POINT_ADDR),
            railgun,
            RailgunFixtures.MASTER_PUBLIC_KEY
        );

        address depositor = address(0xDEADBEEF);
        vm.deal(depositor, 100 ether);
        // vm.prank(depositor);
        // tornado.deposit{value: denomination}(TornadoFixtures.COMMITMENT);
    }

    // ----- Tests -----
}
