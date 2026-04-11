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
    function run() external returns (address) {
        address paymasterAddr = vm.envAddress("PAYMASTER");
        address tornadoInstanceAddr = vm.envAddress("TORNADO_INSTANCE");
        uint256 deployerPk = vm.envUint("DEPLOYER_PK");

        PrivacyPaymaster paymaster = PrivacyPaymaster(payable(paymasterAddr));
        IEntryPoint entryPoint = paymaster.entryPoint();
        ITornadoInstance tornadoInstance = ITornadoInstance(
            tornadoInstanceAddr
        );

        vm.startBroadcast(deployerPk);

        TornadoAccount tornadoAccount = new TornadoAccount(
            entryPoint,
            tornadoInstance,
            address(0)
        );
        paymaster.setApprovedSender(address(tornadoAccount), true);

        vm.stopBroadcast();

        return address(tornadoAccount);
    }
}
