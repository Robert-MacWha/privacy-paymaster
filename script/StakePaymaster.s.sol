// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {Deployments} from "./lib/Deployments.sol";
import {Chains} from "./lib/Chains.sol";

import {
    IEntryPoint
} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {PrivacyPaymaster} from "../contracts/PrivacyPaymaster.sol";

contract StakePaymaster is Script {
    function run() external {
        address paymasterAddr = Deployments.readAddress("paymaster", "address");
        uint256 stakeAmount = vm.envOr("STAKE_AMOUNT", uint256(0));
        uint32 unstakeDelay = uint32(vm.envOr("UNSTAKE_DELAY", uint32(0)));
        uint256 depositAmount = vm.envOr("DEPOSIT_AMOUNT", uint256(0));
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        stake(
            paymasterAddr,
            stakeAmount,
            unstakeDelay,
            depositAmount,
            privateKey
        );
    }

    function stake(
        address paymasterAddr,
        uint256 stakeAmount,
        uint32 unstakeDelay,
        uint256 depositAmount,
        uint256 privateKey
    ) public {
        PrivacyPaymaster paymaster = PrivacyPaymaster(payable(paymasterAddr));
        IEntryPoint entryPoint = paymaster.entryPoint();

        if (stakeAmount > 0) {
            require(unstakeDelay > 0, "Unstake delay must be greater than 0");
            vm.broadcast(privateKey);
            paymaster.addStake{value: stakeAmount}(unstakeDelay);
        }

        if (depositAmount > 0) {
            vm.broadcast(privateKey);
            entryPoint.depositTo{value: depositAmount}(paymasterAddr);
        }
    }
}
