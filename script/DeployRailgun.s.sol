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
import {RailgunAccount} from "../contracts/accounts/railgun/RailgunAccount.sol";
import {
    IRailgunSmartWallet
} from "../contracts/accounts/railgun/interfaces/IRailgunSmartWallet.sol";

contract DeployRailgun is Script {
    function run() external {
        address paymasterAddr = Deployments.readAddress("paymaster", "address");
        address railgunSmartWalletAddr = Chains.readAddress(
            "protocols.railgun",
            "smart_wallet"
        );
        bytes32 masterPublicKey = Chains.readBytes32(
            "protocols.railgun",
            "master_public_key"
        );
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        address deployment = deploy(
            paymasterAddr,
            railgunSmartWalletAddr,
            privateKey,
            masterPublicKey
        );
        console.log("Deployed RailgunAccount at:", deployment);
        Deployments.writeAddress("railgun", "railgunAccount", deployment);
    }

    function deploy(
        address paymasterAddr,
        address railgunSmartWalletAddr,
        uint256 privateKey,
        bytes32 masterPublicKey
    ) public returns (address) {
        PrivacyPaymaster paymaster = PrivacyPaymaster(payable(paymasterAddr));
        IEntryPoint entryPoint = paymaster.entryPoint();
        IRailgunSmartWallet railgunSmartWallet = IRailgunSmartWallet(
            railgunSmartWalletAddr
        );

        vm.broadcast(privateKey);
        RailgunAccount railgunAccount = new RailgunAccount(
            entryPoint,
            railgunSmartWallet,
            masterPublicKey
        );
        vm.broadcast(privateKey);
        paymaster.setApprovedImpl(address(railgunAccount), true);
        return address(railgunAccount);
    }
}
