// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {stdJson} from "forge-std/StdJson.sol";

// Hardcoded fixtures for TornadoAccount tests.
library TornadoFixtures {
    using stdJson for string;
    Vm constant vm = Vm(address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D));

    function loadForkBlock() internal view returns (uint256) {
        string memory file = "test/fixtures/tornadocash/config.json";
        string memory json = vm.readFile(file);
        return vm.parseJsonUint(json, ".forkBlockNumber");
    }

    function loadCommitment() internal view returns (bytes32) {
        string memory file = "test/fixtures/tornadocash/shield.json";
        string memory json = vm.readFile(file);
        return vm.parseJsonBytes32(json, ".commitment");
    }

    function loadProof() internal view returns (bytes memory) {
        string memory file = "test/fixtures/tornadocash/unshield.json";
        string memory json = vm.readFile(file);
        return vm.parseJsonBytes(json, ".proof");
    }

    function loadRoot() internal view returns (bytes32) {
        string memory file = "test/fixtures/tornadocash/unshield.json";
        string memory json = vm.readFile(file);
        return vm.parseJsonBytes32(json, ".root");
    }

    function loadNullifierHash() internal view returns (bytes32) {
        string memory file = "test/fixtures/tornadocash/unshield.json";
        string memory json = vm.readFile(file);
        return vm.parseJsonBytes32(json, ".nullifierHash");
    }

    function loadRecipient() internal view returns (address payable) {
        string memory file = "test/fixtures/tornadocash/unshield.json";
        string memory json = vm.readFile(file);
        return payable(vm.parseJsonAddress(json, ".recipient"));
    }

    function loadRelayer() internal view returns (address payable) {
        string memory file = "test/fixtures/tornadocash/unshield.json";
        string memory json = vm.readFile(file);
        return payable(vm.parseJsonAddress(json, ".relayer"));
    }

    function loadFee() internal view returns (uint256) {
        string memory file = "test/fixtures/tornadocash/unshield.json";
        string memory json = vm.readFile(file);
        return vm.parseJsonUint(json, ".fee");
    }

    //? Ignore in forge coverage
    function test() public {}
}
