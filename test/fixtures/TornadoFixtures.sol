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
        hex"0e9bb6f3b90ac8e96ad7c245810b444999fdbbef94b637970e1a8df051daf9af";
    bytes32 internal constant ROOT =
        hex"26fc446de97f065fe9f0532bbae245447204a17f29f3722143a94553543eb129";
    bytes32 internal constant NULLIFIER_HASH =
        hex"2d2db46ee8293e7672c1b834a6dd0899958b990f688655ad24c4c17685b32d2a";

    // Proof with recipient = PAYMASTER_EXPECTED. TBD.
    bytes internal constant PROOF_PM =
        hex"08f609f1ae1280f33d09354ef5ded2ff5a49d28cc2ea989609b368e57d6df99a16d4f07597f3bec76b8d9f61a6b366d84a0dd59087abdc038b8d1ec218c873f222065a39432408910ee646a2319f079ceb0ddd541433c47a46bb6e636e24aaaa0ab8c5301cd0d74a5f858003ba6481d4b83616f193e12b88106544534eee7d6409eef272f7fe0eeb1c7d3cfd4532b77fd4b792f8e9e6a8819713f5520cc2cdbf2814e094d1f3f22d91c4ddef1afa44853ea7ecd12dacc6c39a6bcf583e40dc86278ba8710a672890798d37e1f185eeb8dc09dd9aee2e758f0ec6c4aa21b548582e26222c964b58154bcd125949e70439bfa50125ec278f05a7ef985627fdcf9d";

    // Proof with recipient = OTHER_RECIPIENT.
    bytes internal constant PROOF_OTHER =
        hex"0abd3c172a176b448bc3b4ab7c2b4a65e3b785817eebbf8631385ce9e758439b2ab7ca3ccd0a8106a5ae3a0a31f8379dd69e64e5ce10f35b71b9a2789effd87e10a23c58bfcf634d15eeb0f0410a10f42412d49f2a2868424dfbc50988fa71f81db14d4380f349bcef259f92bef83435ec959b5789ae676aff5aa35491b652532457d6d245754bc1d65e21d21ef350d245c79de1983785d543874b42b1883a0125964dff0d198ce7e02e407b6a2584cd5b76b14a55a61e105ba652faad1bad8314ea83b68b632ba8bcbda9537350dac45ddd50801155d6063cd953cb6c8816ec11ee8d1398b8a70a2b77ee3a666af535f1eb6c32fac9ce417f40b2621005072d";
}
