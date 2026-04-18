// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {
    IEntryPoint
} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {PrivacyPaymaster} from "../contracts/PrivacyPaymaster.sol";
import {
    IUniswapV3Factory
} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

contract DeployPaymaster is Script {
    function run() external {
        address entryPointAddr = vm.envAddress("ENTRY_POINT");
        address factory = vm.envAddress("FACTORY");
        address weth = vm.envAddress("WETH");
        uint32 twapPeriod = uint32(vm.envUint("TWAP_PERIOD"));
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        deploy(entryPointAddr, factory, weth, twapPeriod, privateKey);
    }

    function deploy(
        address entryPoint,
        address factory,
        address weth,
        uint32 twapPeriod,
        uint256 privateKey
    ) public returns (address) {
        vm.broadcast(privateKey);
        PrivacyPaymaster paymaster = new PrivacyPaymaster(
            IEntryPoint(entryPoint),
            IUniswapV3Factory(factory),
            weth,
            twapPeriod
        );
        return address(paymaster);
    }

    //? Ignore in forge coverage
    function test() public {}
}
