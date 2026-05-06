// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
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
        address paymasterAddr = vm.envAddress("PAYMASTER");
        address railgunSmartWalletAddr = vm.envAddress("RAILGUN_SMART_WALLET");
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        bytes32 masterPublicKey = vm.envBytes32("MASTER_PUBLIC_KEY");

        deploy(
            paymasterAddr,
            railgunSmartWalletAddr,
            privateKey,
            masterPublicKey
        );
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

    //? Ignore in forge coverage
    function test() public {}
}
