// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Deployments} from "./lib/Deployments.sol";
import {Chains} from "./lib/Chains.sol";

import {PrivacyPaymaster} from "../contracts/PrivacyPaymaster.sol";
import {IPrivacyPool} from "../contracts/fee_adapters/privacypools/interfaces/IPrivacyPool.sol";
import {PrivacyPoolsFeeAdapter} from "../contracts/fee_adapters/privacypools/PrivacyPoolsFeeAdapter.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

/// Deploys one `PrivacyPoolsFeeAdapter` per pool listed under
/// `[protocols.privacy_pools.<name>]` in the chain config, e.g.
///
///     [protocols.privacy_pools.simple_eth]
///     instance = "0x..."
///
///     [protocols.privacy_pools.complex_weth_3000]
///     instance = "0x..."
///     uniswap_fee = 3000
contract DeployPrivacyPools is Script {
    address internal constant NATIVE_ASSET = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    function run() external {
        address paymasterAddr = Deployments.readAddress("paymaster", "address");
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        string memory toml = vm.readFile(Chains.path());
        // Friendly error if the chain config has no privacy pools section.
        require(
            vm.keyExistsToml(toml, ".protocols.privacy_pools"),
            "add [protocols.privacy_pools.<name>] entries to the chain config first"
        );

        string[] memory pools = vm.parseTomlKeys(toml, ".protocols.privacy_pools");
        require(pools.length > 0, "no privacy pools in chain config");

        for (uint256 i = 0; i < pools.length; i++) {
            string memory tomlKey = string.concat("protocols.privacy_pools.", pools[i]);
            address deployed = deploy(paymasterAddr, tomlKey, privateKey);
            console.log("Deployed PrivacyPoolsFeeAdapter (%s) at: %s", pools[i], deployed);
            Deployments.writeAddress(string.concat("privacypools_", pools[i]), "privacyPoolsAdapter", deployed);
        }
    }

    function deploy(address paymasterAddr, string memory poolTomlKey, uint256 privateKey) public returns (address) {
        PrivacyPaymaster paymaster = PrivacyPaymaster(payable(paymasterAddr));
        address poolAddr = Chains.readAddress(poolTomlKey, "instance");

        vm.broadcast(privateKey);
        PrivacyPoolsFeeAdapter adapter = new PrivacyPoolsFeeAdapter(IPrivacyPool(poolAddr));
        vm.broadcast(privateKey);
        paymaster.setApprovedAdapter(address(adapter), true);

        // Native pools report the sentinel address; the paymaster always
        // allows address(0) (ETH), so no fee token setup is needed.
        address feeToken = adapter.ASSET();
        (bool allowed,) = paymaster.feeTokens(feeToken);
        if (feeToken != address(0) && feeToken != NATIVE_ASSET && !allowed) {
            uint24 uniswapFee = uint24(Chains.readUint(poolTomlKey, "uniswap_fee"));
            vm.broadcast(privateKey);
            paymaster.setFeeToken(feeToken, uniswapFee, true);

            // Expand pool observation buffer to cover the TWAP period
            uint32 twapPeriod = paymaster.twapPeriod();
            uint32 blockTime = uint32(Chains.readUint("block_time"));
            uint16 requiredCardinality = uint16(twapPeriod / blockTime) + 1;
            address pool = paymaster.FACTORY().getPool(feeToken, paymaster.WETH(), uniswapFee);
            vm.broadcast(privateKey);
            IUniswapV3Pool(pool).increaseObservationCardinalityNext(requiredCardinality);
        }

        return address(adapter);
    }
}
