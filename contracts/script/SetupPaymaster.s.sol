// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {PrivacyPaymaster} from "../src/PrivacyPaymaster.sol";

/// @notice Post-deploy wiring for a live PrivacyPaymaster: add stake and
/// fund the EntryPoint deposit. Separated from `DeployPrivacy.s.sol` so the
/// test suite (which needs neither) isn't forced through these state changes,
/// and so that re-funding can happen independently of redeploying.
///
/// Broadcasted by the paymaster owner (must match `PAYMASTER_OWNER` used at
/// deploy time) because `addStake` is `onlyOwner`.
///
/// Usage:
///   PAYMASTER=0x... \
///   ENTRY_POINT=0x... \
///   STAKE_AMOUNT=1000000000000000000 \
///   UNSTAKE_DELAY=86400 \
///   DEPOSIT_AMOUNT=1000000000000000000 \
///   OWNER_PK=0x... \
///   forge script script/SetupPaymaster.s.sol --rpc-url sepolia --broadcast
contract SetupPaymaster is Script {
    function run() external {
        address paymasterAddr = vm.envAddress("PAYMASTER");
        address entryPointAddr = vm.envAddress("ENTRY_POINT");
        uint256 stakeAmount = vm.envUint("STAKE_AMOUNT");
        uint32 unstakeDelay = uint32(vm.envUint("UNSTAKE_DELAY"));
        uint256 depositAmount = vm.envUint("DEPOSIT_AMOUNT");
        uint256 ownerPk = vm.envUint("OWNER_PK");

        PrivacyPaymaster paymaster = PrivacyPaymaster(payable(paymasterAddr));
        IEntryPoint entryPoint = IEntryPoint(entryPointAddr);

        vm.startBroadcast(ownerPk);

        // Stake goes through the paymaster (onlyOwner) and forwards into
        // the EntryPoint's stake manager.
        paymaster.addStake{value: stakeAmount}(unstakeDelay);

        // Deposit can be funded by anyone, but piggyback on the same
        // broadcast for convenience.
        entryPoint.depositTo{value: depositAmount}(paymasterAddr);

        vm.stopBroadcast();
    }
}
