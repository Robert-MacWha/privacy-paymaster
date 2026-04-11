// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

// Hardcoded fixtures for the fork tests. These are snapshots captured once
// from an offline note/proof generation run; the fork is pinned to FORK_BLOCK
// so they remain valid across runs.
//
// PAYMASTER_EXPECTED is derived from CREATE(vm.addr(DEPLOYER_PK), 0) — the
// address the paymaster lands at when deployed normally from DEPLOYER_PK at
// nonce 0. The proofs commit to this address as the recipient public input.
// Because CREATE addresses depend only on deployer + nonce (not bytecode),
// this address is stable across contract changes.
//
// Only regenerate proofs if PAYMASTER_EXPECTED, FORK_BLOCK, or
// TORNADO_INSTANCE_ADDR changes.
//
// Procedure:
//   1. Pick FORK_BLOCK (recent, stable).
//   2. Compute PAYMASTER_EXPECTED:
//      cast compute-address --nonce 0 $(cast wallet address --private-key 0xA11CE)
//   3. Run the note/proof tooling in the sibling repo with:
//      - instance   = TORNADO_INSTANCE_ADDR at FORK_BLOCK
//      - recipient1 = PAYMASTER_EXPECTED
//      - recipient2 = OTHER_RECIPIENT
//      - relayer=0, fee=0, refund=0
//   4. Tool outputs: commitment, nullifierHash, post-deposit root, proof1, proof2.
//      Paste below.

library TornadoFixtures {
    // ----- Network / fork config -----
    uint256 internal constant FORK_BLOCK = 10_000_000;

    // Sepolia EntryPoint v0.9.0. Canonical deterministic address.
    address internal constant ENTRY_POINT_ADDR =
        0x433709009B8330FDa32311DF1C2AFA402eD8D009;

    // Sepolia TC 1 ETH instance.
    address internal constant TORNADO_INSTANCE_ADDR =
        address(0x8cc930096B4Df705A007c4A039BDFA1320Ed2508);

    // Deployer key used by the fork tests and Deploy.s.sol smoke test.
    uint256 internal constant DEPLOYER_PK =
        uint256(
            0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6
        );

    address internal constant PAYMASTER_OWNER =
        address(uint160(0xa0Ee7A142d267C1f36714E4a8F75612F20a79720));

    address internal constant PAYMASTER_EXPECTED =
        address(0x2C6ddd76DD36CDdE9CB967a8ae66767b456EB1Ba);

    address internal constant FEE_RECIPIENT = address(0xC0FFEE);

    // ----- Note / proof snapshots -----
    bytes32 internal constant COMMITMENT =
        hex"002ca4079049b78ba6d0fa185af6fab3e5868a9c5efd9de72e38eb41d386c847";
    bytes32 internal constant ROOT =
        hex"26185ed9908360acfc552156f957705ca08c5bc81ca698c6156f28d6df5f0b25";
    bytes32 internal constant NULLIFIER_HASH =
        hex"2918dd5a43f0c8e8b04caba605f9a0707fbcefc3501d36166e2b9bdf8f43dfcf";

    // Proof with recipient == PAYMASTER_EXPECTED.
    bytes internal constant PROOF_PM =
        hex"29cd95071990e0259ae051c38d514bedc5a806499b756c41305d5e5586fea72e0c1bc67709d7e0f781fb3e1216317b9416ca67fc3ed64aa51b5385e586855a1e25f3c862335c0aeaae466fb72b434a5f1a6d923707ce56855527fff057d3b8250d19e38dd65bc6378ebf993ff4fd1188b042c9d9fcd8ee5249f322439cc47c430a6a2cece205031a96086f701fddcdc2c637a89c389fbfc3483168f33decf54411145d8b3c633422d8c1cc51c19871c825acf02d0778437e4eb7076f8d763b780f49d4e20b1981d49aa22c92ce02594805ffef68db29a14f5b47b5ac798fbb390825a8e65c0b8f07e6500dbf6cf81816826aeedeb1ada1b5281630f449e66826";

    // Proof with recipient != PAYMASTER_EXPECTED.
    bytes internal constant PROOF_OTHER =
        hex"302fb9ad3668adf46cf39111d098276b0e467b19d6f65b16c34be322bd70422c0cd86b0db3707ed4532a9e2e71dc2ca1c109dce0ede152dfbbfa200a9abbaa320811bee5ac4c2c6bff03efd4acfba9c8875969d496f4594370c3afe52e05e55f184e8d89d8ccae6450bf3adafc77430b0f594b9ee85db75434e45025c1a1ca521314e7da9f0d45d190eea359ec6abba26d959e8975fa8234d4a18abc045d663c21c5b1c29b17e3f1c9b60691ed5ee2ac217f4e0acfb82e5239a963749d36d351250a02dc8ce4da1e71fe7b863a8ba4ecfe6251c966f21d12d912e59895fc69c80d9281d4ebc88127fc8773bd7b2b4d6a1903792429727e982498ea492d451266";
}
