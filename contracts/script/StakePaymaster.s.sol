// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {
    IEntryPoint
} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {PrivacyPaymaster} from "../src/PrivacyPaymaster.sol";

contract StakePaymaster is Script {
    function run() external {
        address paymasterAddr = vm.envAddress("PAYMASTER");
        uint256 stakeAmount = vm.envUint("STAKE_AMOUNT");
        uint32 unstakeDelay = uint32(vm.envUint("UNSTAKE_DELAY"));
        uint256 depositAmount = vm.envUint("DEPOSIT_AMOUNT");
        uint256 deployerPk = vm.envUint("DEPLOYER_PK");

        PrivacyPaymaster paymaster = PrivacyPaymaster(payable(paymasterAddr));
        IEntryPoint entryPoint = paymaster.entryPoint();

        vm.startBroadcast(deployerPk);

        paymaster.addStake{value: stakeAmount}(unstakeDelay);
        entryPoint.depositTo{value: depositAmount}(paymasterAddr);

        vm.stopBroadcast();
    }
}
