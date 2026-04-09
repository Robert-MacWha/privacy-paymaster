// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {DeployPrivacy} from "../script/DeployPrivacy.s.sol";
import {TornadoFixtures} from "./fixtures/TornadoFixtures.sol";

/// Smoke test for `script/DeployPrivacy.s.sol`. The main fork suite plants
/// the paymaster at a fixed address via `deployCodeTo` and does NOT exercise
/// the deployment script, so this test exists purely to catch bit-rot in
/// the real-broadcast path.
contract DeployScriptTest is Test {
    function test_deploy_script_runs() public {
        vm.createSelectFork(vm.rpcUrl("sepolia"), TornadoFixtures.FORK_BLOCK);

        // Set deployer == owner so wiring runs inside DeployPrivacy.run().
        address owner = vm.addr(TornadoFixtures.DEPLOYER_PK);

        vm.setEnv("ENTRY_POINT", vm.toString(TornadoFixtures.ENTRY_POINT_ADDR));
        vm.setEnv(
            "TORNADO_INSTANCE",
            vm.toString(TornadoFixtures.TORNADO_INSTANCE_ADDR)
        );
        vm.setEnv("PAYMASTER_OWNER", vm.toString(owner));
        vm.setEnv("DEPLOYER_PK", vm.toString(TornadoFixtures.DEPLOYER_PK));
        vm.setEnv("WETH", vm.toString(address(0xAA)));
        vm.setEnv("STATIC_ORACLE", vm.toString(address(0xBB)));
        vm.setEnv("TWAP_PERIOD", "300");

        DeployPrivacy.Deployed memory d = new DeployPrivacy().run();
        assertTrue(address(d.tornadoAccount).code.length > 0, "account not deployed");
        assertTrue(
            address(d.paymaster).code.length > 0,
            "paymaster not deployed"
        );
        assertTrue(
            d.paymaster.approvedSenders(address(d.tornadoAccount)),
            "tornadoAccount not approved"
        );
    }
}
