// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";

library Deployments {
    Vm constant vm = Vm(address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D));

    function path() internal view returns (string memory) {
        string memory env = vm.envOr("DEPLOY_ENV", string("sepolia"));
        return string.concat("config/deployments/", env, ".json");
    }

    function writeAddress(
        string memory section,
        string memory field,
        address value
    ) internal {
        string memory json = vm.serializeAddress(section, field, value);
        vm.writeJson(json, path(), string.concat(".", section));
    }

    function readAddress(
        string memory section,
        string memory field
    ) internal view returns (address) {
        string memory p = path();
        require(vm.exists(p), string.concat("no deployment file", p));

        string memory json = vm.readFile(p);
        return
            vm.parseJsonAddress(json, string.concat(".", section, ".", field));
    }

    //? Ignore in forge coverage
    function test() public {}
}
