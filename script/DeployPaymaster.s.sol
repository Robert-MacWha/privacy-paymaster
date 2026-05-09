// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {PrivacyPaymaster} from "../contracts/PrivacyPaymaster.sol";

import {Deployments} from "./lib/Deployments.sol";
import {Chains} from "./lib/Chains.sol";

import {
    IEntryPoint
} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {PrivacyPaymaster} from "../contracts/PrivacyPaymaster.sol";
import {
    IUniswapV3Factory
} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

contract DeployPaymaster is Script {
    using stdJson for string;

    function run() external {
        address entryPointAddr = Chains.readAddress(
            "protocols.erc4337",
            "entry_point"
        );
        address factory = Chains.readAddress("protocols.uniswap_v3", "factory");
        address weth = Chains.readAddress("tokens", "weth");
        uint32 twapPeriod = uint32(
            Chains.readUint("protocols.uniswap_v3", "twap_period")
        );
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        address deployment = deploy(
            entryPointAddr,
            factory,
            weth,
            twapPeriod,
            privateKey
        );
        console.log("Deployed Paymaster at:", deployment);
        Deployments.writeAddress("paymaster", "address", deployment);
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
}
