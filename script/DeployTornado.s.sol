// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Deployments} from "./lib/Deployments.sol";
import {Chains} from "./lib/Chains.sol";

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
        address paymasterAddr = Deployments.readAddress("paymaster", "address");
        address tornadoInstanceAddr = Chains.readAddress(
            "protocols.tornado.eth_1",
            "instance"
        );
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        address deployment = deploy(
            paymasterAddr,
            tornadoInstanceAddr,
            privateKey
        );
        console.log("Deployed TornadoAccount at:", deployment);
        Deployments.writeAddress("tornado", "tornadoAccount", deployment);
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
        paymaster.setApprovedImpl(address(tornadoAccount), true);

        return address(tornadoAccount);
    }
}
