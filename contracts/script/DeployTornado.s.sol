// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {
    IEntryPoint
} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {PrivacyPaymaster} from "../src/PrivacyPaymaster.sol";
import {TornadoAccount} from "../src/accounts/TornadoAccount.sol";
import {ITornadoInstance} from "../src/interfaces/ITornadoInstance.sol";

contract DeployTornado is Script {
    function run() external {
        address paymasterAddr = vm.envAddress("PAYMASTER");
        address tornadoInstanceAddr = vm.envAddress("TORNADO_INSTANCE");
        uint256 deployerPk = vm.envUint("DEPLOYER_PK");

        deploy(paymasterAddr, tornadoInstanceAddr, deployerPk);
    }

    function deploy(
        address paymasterAddr,
        address tornadoInstanceAddr,
        uint256 deployerPk
    ) public returns (address) {
        PrivacyPaymaster paymaster = PrivacyPaymaster(payable(paymasterAddr));
        IEntryPoint entryPoint = paymaster.entryPoint();
        ITornadoInstance tornadoInstance = ITornadoInstance(
            tornadoInstanceAddr
        );

        vm.broadcast(deployerPk);
        TornadoAccount tornadoAccount = new TornadoAccount(
            entryPoint,
            tornadoInstance,
            address(0)
        );
        vm.broadcast(deployerPk);
        paymaster.setApprovedSender(address(tornadoAccount), true);

        return address(tornadoAccount);
    }

    //? Ignore in forge coverage
    function test() public {}
}
