// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

// Hardcoded fixtures for the fork tests. These are snapshots captured once
// from an offline note/proof generation run; the fork is pinned to FORK_BLOCK
// so they remain valid across runs.
//
// PAYMASTER_EXPECTED is a FREELY CHOSEN constant — the test suite uses
// `deployCodeTo` to plant the paymaster at this exact address, so it is
// independent of bytecode changes, constructor args, or deployer state.
// Only regenerate proofs if PAYMASTER_EXPECTED, FORK_BLOCK, or
// TORNADO_INSTANCE_ADDR changes.
//
// Procedure:
//   1. Pick FORK_BLOCK (recent, stable).
//   2. Run the note/proof tooling in the sibling repo with:
//      - instance   = TORNADO_INSTANCE_ADDR at FORK_BLOCK
//      - recipient1 = PAYMASTER_EXPECTED (pick any address, just keep it)
//      - recipient2 = OTHER_RECIPIENT
//      - relayer=0, fee=0, refund=0
//   3. Tool outputs: commitment, nullifierHash, post-deposit root, proof1, proof2.
//      Paste below.

library TornadoFixtures {
    // ----- Network / fork config -----
    uint256 internal constant FORK_BLOCK = 10_000_000;

    // Sepolia TC 1 ETH instance.
    address internal constant TORNADO_INSTANCE_ADDR =
        address(0x8cc930096B4Df705A007c4A039BDFA1320Ed2508);

    // Sepolia EntryPoint v0.9.0. Canonical deterministic address.
    address internal constant ENTRY_POINT_ADDR =
        0x433709009B8330FDa32311DF1C2AFA402eD8D009;

    // Deployer key for the smoke test of Deploy.s.sol (see
    // test_deploy_script_smoke). Not used by the main fork tests, which
    // plant the paymaster at a fixed address via deployCodeTo.
    uint256 internal constant DEPLOYER_PK = uint256(0xA11CE);

    address internal constant PAYMASTER_OWNER = address(uint160(0xB0B0));

    // Freely chosen fixed paymaster address. The proofs commit to this as
    // the recipient public input; keep it stable across proof regenerations.
    address internal constant PAYMASTER_EXPECTED =
        address(0x50682657f150704c8D43aC6537CBd7E859832694);

    address internal constant OTHER_RECIPIENT =
        0x0000000000000000000000000000000000001234;

    // ----- Note / proof snapshots -----
    bytes32 internal constant COMMITMENT =
        hex"1291259ce38518ac740a92829a0c40c0928398db467fa1f2a90776d360cab1ee";
    bytes32 internal constant ROOT =
        hex"1e199a665f91de139e4c5962d3b31baf8967f7576616a27856048fd1d0a1126f";
    bytes32 internal constant NULLIFIER_HASH =
        hex"1e8f3b936b467eb40879f124a156eede9aa5376a0d070e484da270a2a4d1f64e";

    // Proof with recipient = PAYMASTER_EXPECTED. TBD.
    bytes internal constant PROOF_PM =
        hex"1b9ec53cee699564a03425760dde645b9efd762c19316dbc20de0319c01445b22d491c87aad3ef66e5f5789c1016eb804ebe116bf8a6aaff35ffafed8c079a510128c3f930d2060fdfaf7214a4a404eb509ea776a3d83bb3c13a2e2c9569e30c2acde37825b0b7cfb678a98800ce143f35989264773899f683c215a2501075a523f309c8baf30a558f36da78cd5ee77e510b526437e6b30a0dd2fa8332057c7b176da03cdab5977a46f65dc902b683e367d34e6fcb0e3f8f577ade4c0ed959332d53dd82c338f3acf30a0e796bc5d03a037ebe1e97b5ef8b1a2ba6a8932d0624164f483e71b02bc52ecb3c89ffedb111ccabc50c606c4d8bd765fece7734600f";

    // Proof with recipient = OTHER_RECIPIENT.
    bytes internal constant PROOF_OTHER =
        hex"202ede39dbe4c77b82d987ff81e6c6ab53a66ba8b8229c356a9b5b04a12712cb1537879d89a27fdcdbaf322a1d8d98fb30b5dd3ea534b20548fc5ecc417318b329f4ed74ef219972a50f719faf33b7129fe68ed14a15fec757ceb0566854aa3f180b820619d870e5aecdbaad83fc2d4f319e4145afe2c0afcf5a368adfd271c2134a614c7a6ae9a1c2477d99da8b921ef704a9576cb1d4da6ce13844418569f60bfd8afb77727edfcad8a68a46158bb32a29ef1209a4954a279883357be7b64a1bd6744692301e5f8848491f534b03df31885098f866ca9f5c1277bab8984e1e256ac533641541f17ba032aa3038d75a36a2aff614fad9c3d7930fffc127c574";
}
