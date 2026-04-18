// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {
    IEntryPoint
} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {PrivacyPaymaster} from "../contracts/PrivacyPaymaster.sol";
import {
    TornadoAccount
} from "../contracts/accounts/tornadocash/TornadoAccount.sol";
import {
    ITornadoInstance
} from "../contracts/accounts/tornadocash/interfaces/ITornadoInstance.sol";

contract DeployTornado is Script {
    function run() external {
        address paymasterAddr = vm.envAddress("PAYMASTER");
        address tornadoInstanceAddr = vm.envAddress("TORNADO_INSTANCE");
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        deploy(paymasterAddr, tornadoInstanceAddr, privateKey);
    }

    function deploy(
        address paymasterAddr,
        address tornadoInstanceAddr,
        uint256 privateKey
    ) public returns (address) {
        PrivacyPaymaster paymaster = PrivacyPaymaster(payable(paymasterAddr));
        IEntryPoint entryPoint = paymaster.entryPoint();
        ITornadoInstance tornadoInstance = ITornadoInstance(
            tornadoInstanceAddr
        );

        vm.broadcast(privateKey);
        TornadoAccount tornadoAccount = new TornadoAccount(
            entryPoint,
            tornadoInstance,
            address(0)
        );
        vm.broadcast(privateKey);
        paymaster.setApprovedSender(address(tornadoAccount), true);

        return address(tornadoAccount);
    }

    //? Ignore in forge coverage
    function test() public {}
}
