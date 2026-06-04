// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Deployments} from "./lib/Deployments.sol";
import {Chains} from "./lib/Chains.sol";

import {PrivacyPaymaster} from "../contracts/PrivacyPaymaster.sol";
import {
    RailgunFeeAdapter
} from "../contracts/fee_adapters/railgun/RailgunFeeAdapter.sol";
import {
    IRailgunSmartWallet
} from "../contracts/fee_adapters/railgun/interfaces/IRailgunSmartWallet.sol";

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
            masterPublicKey,
            privateKey
        );
        console.log("Deployed RailgunFeeAdapter at:", deployment);
        Deployments.writeAddress("railgun", "railgunAdapter", deployment);
    }

    function deploy(
        address paymasterAddr,
        address railgunSmartWalletAddr,
        bytes32 masterPublicKey,
        uint256 privateKey
    ) public returns (address) {
        PrivacyPaymaster paymaster = PrivacyPaymaster(payable(paymasterAddr));
        IRailgunSmartWallet railgunSmartWallet = IRailgunSmartWallet(
            railgunSmartWalletAddr
        );

        vm.broadcast(privateKey);
        RailgunFeeAdapter adapter = new RailgunFeeAdapter(
            railgunSmartWallet,
            masterPublicKey
        );
        vm.broadcast(privateKey);
        paymaster.setApprovedAdapter(address(adapter), true);
        return address(adapter);
    }
}
