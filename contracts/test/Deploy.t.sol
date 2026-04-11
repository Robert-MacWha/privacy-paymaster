// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {DeployPaymaster} from "../script/DeployPaymaster.s.sol";
import {StakePaymaster} from "../script/StakePaymaster.s.sol";
import {DeployTornado} from "../script/DeployTornado.s.sol";
import {TornadoFixtures} from "./fixtures/TornadoFixtures.sol";

contract DeployScriptTest is Test {
    function test_deploy_script_runs() public {
        vm.createSelectFork(vm.rpcUrl("sepolia"), TornadoFixtures.FORK_BLOCK);
        vm.deal(vm.addr(TornadoFixtures.DEPLOYER_PK), 1000 ether);

        vm.setEnv("ENTRY_POINT", vm.toString(TornadoFixtures.ENTRY_POINT_ADDR));
        vm.setEnv("DEPLOYER_PK", vm.toString(TornadoFixtures.DEPLOYER_PK));
        vm.setEnv("WETH", vm.toString(address(0)));
        vm.setEnv("STATIC_ORACLE", vm.toString(address(0)));
        vm.setEnv("TWAP_PERIOD", "0");

        address paymaster = new DeployPaymaster().run();
        assertEq(
            paymaster,
            TornadoFixtures.PAYMASTER_EXPECTED,
            "wrong paymaster addr"
        );

        vm.setEnv("PAYMASTER", vm.toString(paymaster));
        vm.setEnv("STAKE_AMOUNT", "100");
        vm.setEnv("UNSTAKE_DELAY", "3600");
        vm.setEnv("DEPOSIT_AMOUNT", "100");

        new StakePaymaster().run();

        vm.setEnv(
            "TORNADO_INSTANCE",
            vm.toString(TornadoFixtures.TORNADO_INSTANCE_ADDR)
        );

        new DeployTornado().run();
    }
}
