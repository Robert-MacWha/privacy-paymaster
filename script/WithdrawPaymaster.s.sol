// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {Deployments} from "./lib/Deployments.sol";
import {Chains} from "./lib/Chains.sol";

import {PrivacyPaymaster} from "../contracts/PrivacyPaymaster.sol";

contract WithdrawPaymaster is Script {
    function run() external {
        address paymasterAddr = Deployments.readAddress("paymaster", "address");
        uint256 withdrawAmount = vm.envOr("WITHDRAW_AMOUNT", uint256(0));
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        withdraw(paymasterAddr, withdrawAmount, privateKey);
    }

    function withdraw(
        address paymasterAddr,
        uint256 withdrawAmount,
        uint256 privateKey
    ) public {
        PrivacyPaymaster paymaster = PrivacyPaymaster(payable(paymasterAddr));

        vm.broadcast(privateKey);
        address payable to = payable(vm.addr(privateKey));
        paymaster.withdrawTo(to, withdrawAmount);
    }
}
