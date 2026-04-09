// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Deploy} from "../script/Deploy.s.sol";
import {TornadoFixtures} from "./fixtures/TornadoFixtures.sol";

/// Smoke test for `script/Deploy.s.sol`. The main fork suite plants the
/// paymaster at a fixed address via `deployCodeTo` and does NOT exercise
/// the deployment script, so this test exists purely to catch bit-rot in
/// the real-broadcast path.
contract DeployScriptTest is Test {
    function test_deploy_script_runs() public {
        vm.createSelectFork(vm.rpcUrl("sepolia"), TornadoFixtures.FORK_BLOCK);

        vm.setEnv("ENTRY_POINT", vm.toString(TornadoFixtures.ENTRY_POINT_ADDR));
        vm.setEnv(
            "TORNADO_INSTANCE",
            vm.toString(TornadoFixtures.TORNADO_INSTANCE_ADDR)
        );
        vm.setEnv(
            "PAYMASTER_OWNER",
            vm.toString(TornadoFixtures.PAYMASTER_OWNER)
        );
        vm.setEnv("DEPLOYER_PK", vm.toString(TornadoFixtures.DEPLOYER_PK));

        Deploy.Deployed memory d = new Deploy().run();
        assertTrue(address(d.account).code.length > 0, "account not deployed");
        assertTrue(
            address(d.paymaster).code.length > 0,
            "paymaster not deployed"
        );
        assertEq(
            address(d.paymaster.TORNADO_ACCOUNT()),
            address(d.account),
            "paymaster wired to wrong account"
        );
    }
}
