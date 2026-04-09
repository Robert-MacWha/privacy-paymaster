// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {ITornadoInstance} from "../src/interfaces/ITornadoInstance.sol";
import {TornadoAccount} from "../src/TornadoAccount.sol";
import {TornadoPaymaster} from "../src/TornadoPaymaster.sol";

/// @notice Deterministic deployment script for TornadoAccount + TornadoPaymaster.
/// Reused by fork tests (via `new Deploy().run()`) and by real broadcasts.
///
/// Uses CREATE2 (`new Foo{salt: s}(...)`) so the deployed addresses depend
/// only on (deployer, salt, initcode) and NOT on the deployer's nonce. This
/// is required because the test suite's hardcoded proofs commit to the
/// paymaster address as the `recipient` public input and the fork has
/// arbitrary prior activity for the deployer key.
///
/// Post-deploy wiring (stake, EntryPoint deposit) is in SetupPaymaster.s.sol.
contract Deploy is Script {
    struct Deployed {
        TornadoAccount account;
        TornadoPaymaster paymaster;
    }

    function run() external returns (Deployed memory) {
        address entryPoint = vm.envAddress("ENTRY_POINT");
        address tornadoInstance = vm.envAddress("TORNADO_INSTANCE");
        address owner = vm.envAddress("PAYMASTER_OWNER");
        uint256 deployerPk = vm.envUint("DEPLOYER_PK");
        bytes32 salt = vm.envOr("DEPLOY_SALT", bytes32(0));

        vm.startBroadcast(deployerPk);

        TornadoAccount account = new TornadoAccount{salt: salt}(
            IEntryPoint(entryPoint),
            ITornadoInstance(tornadoInstance)
        );
        TornadoPaymaster paymaster = new TornadoPaymaster{salt: salt}(
            IEntryPoint(entryPoint),
            owner,
            ITornadoInstance(tornadoInstance),
            account
        );

        vm.stopBroadcast();
        return Deployed(account, paymaster);
    }
}
