// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

// Hardcoded fixtures for TornadoAccount tests.
library TornadoFixtures {
    // ----- Network / fork config -----
    uint256 internal constant FORK_BLOCK = 10_000_000;

    // Sepolia EntryPoint v0.8.0.
    address internal constant ENTRY_POINT_ADDR =
        0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108;

    // Sepolia TC 1 ETH instance.
    address internal constant TORNADO_INSTANCE_ADDR =
        address(0x8cc930096B4Df705A007c4A039BDFA1320Ed2508);

    // Forge account testing PK.
    uint256 internal constant PRIVATE_KEY =
        uint256(
            0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6
        );

    // ----- Note / proof snapshots -----
    // These values should be generated using client code and be valid notes
    // and proofs for the above Tornado instance.

    // Arbitrary fields proof snapshot must commit to for tests.
    address payable internal constant RECIPIENT = payable(address(0xC0FFEE));
    address payable internal constant PAYMASTER =
        payable(address(0x2C6ddd76DD36CDdE9CB967a8ae66767b456EB1Ba));
    address payable internal constant TORNADO_ACCOUNT =
        payable(address(0xdD14776222FeF5FfAF9F8f4c62653d011CE63A1F));
    uint256 internal constant FEE = 50000000000000000;

    // Proof snapshot
    bytes32 internal constant COMMITMENT =
        hex"132fa39bc9676c0c89d567ff63a45dd862858f8f75cf8768130c5aa62dae2a5b";
    bytes32 internal constant ROOT =
        hex"187ee16dba9869f6319ffd06cc5d7dc0d6b20b66735362bb30bb0b3fe62667bc";
    bytes32 internal constant NULLIFIER_HASH =
        hex"08f0366544886c7bb64a8cedd2ec9c78043c69b4c8de426de82b5702c6f5a1e2";

    // Proof with recipient == RECIPIENT, relayer == PAYMASTER, and fee == FEE.
    bytes internal constant PROOF_VALID =
        hex"216d0abb7a01ca6b27b698a3c8071c73d01753bf6e4fb60d9c3e7578624df9c20c5aafbebf3338aa9981cc421a0cc97b3cfe48aff4ad9e8d081b7d1a3715fb0521abfb49e30d5b82de52a37992b204a642a8adfe89e0c8e7f1b13ca84e034a1e1a3302fd6ce746f4688eae970ead8dc728cafa84de6ab2af51bcd1d4bf70e058197d081399eb8759fcbf97d6beb5f15a599c9edb3cc13884ebfe082a87f94bcd1afddca40c3ba493fa7807c3d031ab8a3b70437cd0a2651bf2a29d73753776612928c8c8836949883a0f86e4606a2873ab0abc4660159c8f6ee2c2100f01226e269ae5b493d4744009e26a349ed7de832ec6b2a86416f31b3fee5f473c41341c";

    // Proof with recipient == RECIPIENT, relayer != PAYMASTER, and fee == FEE.
    bytes internal constant PROOF_INVALID_PAYMASTER =
        hex"1e9002cb0f96d956ce2a43ae7eaffb8de8f0f6969dce95fa8606e5a17dce24fa2071b9bbb261990b226a78dacedd24d498aa0565ba1f9e9e6c515d357053e7d3001ed2c6892ffada51cf5efbf0d98f5a16c890e5f2add286fa6fc325a4b9901e0715872ed4deef1b7721822179314a71f3ab56f0cf17cdbc8dccdc992497d8c60758ab3a515259b70b409f2e0790ae293f8598a7508397ad6ff549b737b0eda60446d0596c02043b195c8394365cba007b2a2a28ffcc84b830d012d8a552d5b810fddff0f57c01c39dec425142f40ad974b31a824e5b8bbf5844a8338e23cecf2c4856c4108f320a30594c1a2f9bf6464d520c80209d3c4b48c55c51cdb81a35";
}
