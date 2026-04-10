// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {
    IEntryPoint
} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {IStaticOracle} from "../src/interfaces/IStaticOracle.sol";

import {PrivacyPaymaster} from "../src/PrivacyPaymaster.sol";
import {TornadoAccount} from "../src/accounts/TornadoAccount.sol";
import {ITornadoInstance} from "../src/interfaces/ITornadoInstance.sol";

/// Deterministic deployment for the multi-protocol PrivacyPaymaster stack.
///
/// Deploys, in order:
///   1. PrivacyPaymaster (uses balmy's pre-deployed IStaticOracle)
///   2. TornadoAccount (one per whitelisted tornado instance)
///
/// Wires (if deployer == owner):
///   - `paymaster.setApprovedSender(tornadoAccount, true)`
///
/// Skeleton accounts (PrivacyPoolsAccount, RailgunAccount) are NOT
/// deployed here — they ship disabled until their protocol-specific
/// validator bodies land.
contract DeployPrivacy is Script {
    struct Deployed {
        PrivacyPaymaster paymaster;
        TornadoAccount tornadoAccount;
    }

    function run() external returns (Deployed memory out) {
        address entryPoint = vm.envAddress("ENTRY_POINT");
        address owner = vm.envAddress("PAYMASTER_OWNER");
        address weth = vm.envAddress("WETH");
        address staticOracle = vm.envAddress("STATIC_ORACLE");
        uint32 twapPeriod = uint32(vm.envUint("TWAP_PERIOD"));
        address tornadoInstance = vm.envAddress("TORNADO_INSTANCE");
        uint256 deployerPk = vm.envUint("DEPLOYER_PK");
        bytes32 salt = vm.envOr("DEPLOY_SALT", bytes32(0));

        vm.startBroadcast(deployerPk);

        PrivacyPaymaster paymaster = new PrivacyPaymaster{salt: salt}(
            IEntryPoint(entryPoint),
            owner,
            IStaticOracle(staticOracle),
            weth,
            twapPeriod
        );

        TornadoAccount tornadoAccount = new TornadoAccount{salt: salt}(
            IEntryPoint(entryPoint),
            ITornadoInstance(tornadoInstance),
            address(0) // fee token, address(0) for ETH instances
        );

        //? Wiring only runs when the deployer key is also the owner.
        //? In a multisig deploy this is done separately via
        //? SetupPaymaster.s.sol.
        if (vm.addr(deployerPk) == owner) {
            paymaster.setApprovedSender(address(tornadoAccount), true);
        }

        vm.stopBroadcast();

        out = Deployed({paymaster: paymaster, tornadoAccount: tornadoAccount});
    }
}
