// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Deployments} from "./lib/Deployments.sol";
import {Chains} from "./lib/Chains.sol";

import {PrivacyPaymaster} from "../contracts/PrivacyPaymaster.sol";
import {
    TornadoFeeAdapter
} from "../contracts/fee_adapters/tornadocash/TornadoFeeAdapter.sol";
import {
    ITornadoInstance
} from "../contracts/fee_adapters/tornadocash/interfaces/ITornadoInstance.sol";
import {
    IUniswapV3Pool
} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

contract DeployTornado is Script {
    function run() external {
        address paymasterAddr = Deployments.readAddress("paymaster", "address");

        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        string memory toml = vm.readFile(Chains.path());
        string[] memory pools = vm.parseTomlKeys(toml, ".protocols.tornado");

        for (uint256 i = 0; i < pools.length; i++) {
            string memory tomlKey = string.concat(
                "protocols.tornado.",
                pools[i]
            );
            address deployed = deploy(paymasterAddr, tomlKey, privateKey);
            console.log(
                "Deployed TornadoFeeAdapter (%s) at: %s",
                pools[i],
                deployed
            );
            Deployments.writeAddress(
                string.concat("tornado_", pools[i]),
                "tornadoAdapter",
                deployed
            );
        }
    }

    function deploy(
        address paymasterAddr,
        string memory tornadoProtocolTomlKey,
        uint256 privateKey
    ) public returns (address) {
        PrivacyPaymaster paymaster = PrivacyPaymaster(payable(paymasterAddr));
        address tornadoInstanceAddr = Chains.readAddress(
            tornadoProtocolTomlKey,
            "instance"
        );
        ITornadoInstance tornadoInstance = ITornadoInstance(
            tornadoInstanceAddr
        );

        vm.broadcast(privateKey);
        TornadoFeeAdapter adapter = new TornadoFeeAdapter(tornadoInstance);
        vm.broadcast(privateKey);
        paymaster.setApprovedAdapter(address(adapter), true);

        address feeToken = adapter.FEE_TOKEN();
        (bool allowed, ) = paymaster.feeTokens(feeToken);
        if (feeToken != address(0) && !allowed) {
            uint24 uniswapFee = uint24(
                Chains.readUint(tornadoProtocolTomlKey, "uniswap_fee")
            );
            vm.broadcast(privateKey);
            paymaster.setFeeToken(feeToken, uniswapFee, true);

            // Expand pool observation buffer to cover the TWAP period
            uint32 twapPeriod = paymaster.twapPeriod();
            uint32 blockTime = uint32(Chains.readUint("block_time"));
            uint16 requiredCardinality = uint16(twapPeriod / blockTime) + 1;
            address pool = paymaster.FACTORY().getPool(
                feeToken,
                paymaster.WETH(),
                uniswapFee
            );
            vm.broadcast(privateKey);
            IUniswapV3Pool(pool).increaseObservationCardinalityNext(
                requiredCardinality
            );
        }

        return address(adapter);
    }
}
