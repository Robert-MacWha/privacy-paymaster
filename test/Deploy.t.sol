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
        vm.deal(vm.addr(TornadoFixtures.PRIVATE_KEY), 1000 ether);

        address paymaster = new DeployPaymaster().deploy(
            TornadoFixtures.ENTRY_POINT_ADDR,
            address(0),
            address(0),
            0,
            TornadoFixtures.PRIVATE_KEY
        );
        assertEq(paymaster, TornadoFixtures.PAYMASTER);

        new StakePaymaster().stake(
            paymaster,
            1 ether,
            3600,
            1 ether,
            TornadoFixtures.PRIVATE_KEY
        );

        new DeployTornado().deploy(
            paymaster,
            TornadoFixtures.TORNADO_INSTANCE_ADDR,
            TornadoFixtures.PRIVATE_KEY
        );
    }
}
