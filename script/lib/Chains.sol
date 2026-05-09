// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";

library Chains {
    Vm constant vm = Vm(address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D));

    function path() internal view returns (string memory) {
        string memory env = vm.envOr("DEPLOY_ENV", string("sepolia"));
        return string.concat("config/chains/", env, ".toml");
    }

    function writeAddress(
        string memory section,
        string memory field,
        address value
    ) internal {
        string memory toml = vm.serializeAddress(section, field, value);
        vm.writeToml(toml, path(), string.concat(".", section));
    }

    function readAddress(
        string memory section,
        string memory field
    ) internal view returns (address) {
        string memory p = path();
        require(vm.exists(p), string.concat("no chain file", p));

        string memory toml = vm.readFile(p);
        return
            vm.parseTomlAddress(toml, string.concat(".", section, ".", field));
    }

    function readUint(
        string memory section,
        string memory field
    ) internal view returns (uint256) {
        string memory p = path();
        require(vm.exists(p), string.concat("no chain file", p));

        string memory toml = vm.readFile(p);
        return vm.parseTomlUint(toml, string.concat(".", section, ".", field));
    }

    function readBytes32(
        string memory section,
        string memory field
    ) internal view returns (bytes32) {
        string memory p = path();
        require(vm.exists(p), string.concat("no chain file", p));

        string memory toml = vm.readFile(p);
        return
            vm.parseTomlBytes32(toml, string.concat(".", section, ".", field));
    }

    //? Ignore in forge coverage
    function test() public {}
}
