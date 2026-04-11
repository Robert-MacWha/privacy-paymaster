// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {
    IEntryPoint
} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {IStaticOracle} from "../src/interfaces/IStaticOracle.sol";
import {PrivacyPaymaster} from "../src/PrivacyPaymaster.sol";

contract DeployPaymaster is Script {
    function run() external {
        address entryPointAddr = vm.envAddress("ENTRY_POINT");
        address weth = vm.envAddress("WETH");
        address staticOracle = vm.envAddress("STATIC_ORACLE");
        uint32 twapPeriod = uint32(vm.envUint("TWAP_PERIOD"));
        uint256 deployerPk = vm.envUint("DEPLOYER_PK");

        deploy(entryPointAddr, weth, staticOracle, twapPeriod, deployerPk);
    }

    function deploy(
        address entryPoint,
        address weth,
        address staticOracle,
        uint32 twapPeriod,
        uint256 deployerPk
    ) public returns (address) {
        address owner = vm.addr(deployerPk);

        vm.broadcast(deployerPk);
        PrivacyPaymaster paymaster = new PrivacyPaymaster(
            IEntryPoint(entryPoint),
            owner,
            IStaticOracle(staticOracle),
            weth,
            twapPeriod
        );
        return address(paymaster);
    }
}
