// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {
    IEntryPoint
} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {PrivacyPaymaster} from "../src/PrivacyPaymaster.sol";
import {
    IUniswapV3Factory
} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

contract DeployPaymaster is Script {
    function run() external {
        address entryPointAddr = vm.envAddress("ENTRY_POINT");
        address factory = vm.envAddress("FACTORY");
        address weth = vm.envAddress("WETH");
        uint32 twapPeriod = uint32(vm.envUint("TWAP_PERIOD"));
        uint256 deployerPk = vm.envUint("DEPLOYER_PK");

        deploy(entryPointAddr, factory, weth, twapPeriod, deployerPk);
    }

    function deploy(
        address entryPoint,
        address factory,
        address weth,
        uint32 twapPeriod,
        uint256 deployerPk
    ) public returns (address) {
        address owner = vm.addr(deployerPk);

        vm.broadcast(deployerPk);
        PrivacyPaymaster paymaster = new PrivacyPaymaster(
            IEntryPoint(entryPoint),
            owner,
            IUniswapV3Factory(factory),
            weth,
            twapPeriod
        );
        return address(paymaster);
    }

    //? Ignore in forge coverage
    function test() public {}
}
