// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {
    Transaction, BoundParams, CommitmentCiphertext, CommitmentPreimage,
    TokenData, TokenType, SnarkProof, G1Point, G2Point, UnshieldType, 
    ShieldRequest, ShieldCiphertext
} from "../../contracts/accounts/railgun/Globals.sol";

contract RailgunJson is Test {
    using stdJson for string;

    function loadShield(string memory json) internal view returns (ShieldRequest memory) {
        return ShieldRequest({
            ciphertext: ShieldCiphertext({
                encryptedBundle: [
                    vm.parseJsonBytes32(json, ".ciphertext.encryptedBundle[0]"),
                    vm.parseJsonBytes32(json, ".ciphertext.encryptedBundle[1]"),
                    vm.parseJsonBytes32(json, ".ciphertext.encryptedBundle[2]")
                ],
                shieldKey: vm.parseJsonBytes32(json, ".ciphertext.shieldKey")
            }),
            preimage: CommitmentPreimage({
                npk: vm.parseJsonBytes32(json, ".preimage.npk"),
                token: TokenData({
                    tokenType: TokenType(vm.parseJsonUint(json, ".preimage.token.tokenType")),
                    tokenAddress: vm.parseJsonAddress(json, ".preimage.token.tokenAddress"),
                    tokenSubID: vm.parseJsonUint(json, ".preimage.token.tokenSubID")
                }),
                value: uint120(vm.parseJsonUint(json, ".preimage.value"))
            })
        });
    }

    function loadTransaction(string memory json) internal pure returns (Transaction memory t) {
        t.merkleRoot = json.readBytes32(".merkleRoot");
        t.nullifiers = json.readBytes32Array(".nullifiers");
        t.commitments = json.readBytes32Array(".commitments");
        t.proof = loadProof(json, ".proof");
        t.boundParams = loadBoundParams(json, ".boundParams");
        t.unshieldPreimage = loadPreimage(json, ".unshieldPreimage");
    }

    function loadProof(string memory json, string memory prefix) internal pure returns (SnarkProof memory p) {
        p.a = G1Point({
            x: json.readUint(string.concat(prefix, ".a.x")),
            y: json.readUint(string.concat(prefix, ".a.y"))
        });
        p.b = G2Point({
            x: [json.readUint(string.concat(prefix, ".b.x[0]")), json.readUint(string.concat(prefix, ".b.x[1]"))],
            y: [json.readUint(string.concat(prefix, ".b.y[0]")), json.readUint(string.concat(prefix, ".b.y[1]"))]
        });
        p.c = G1Point({
            x: json.readUint(string.concat(prefix, ".c.x")),
            y: json.readUint(string.concat(prefix, ".c.y"))
        });
    }

    function loadBoundParams(string memory json, string memory prefix) internal pure returns (BoundParams memory bp) {
        bp.treeNumber = uint16(json.readUint(string.concat(prefix, ".treeNumber")));
        bp.minGasPrice = uint72(json.readUint(string.concat(prefix, ".minGasPrice")));
        bp.unshield = UnshieldType(json.readUint(string.concat(prefix, ".unshield")));
        bp.chainID = uint64(json.readUint(string.concat(prefix, ".chainID")));
        bp.adaptContract = json.readAddress(string.concat(prefix, ".adaptContract"));
        bp.adaptParams = json.readBytes32(string.concat(prefix, ".adaptParams"));

        uint256 len = abi.decode(vm.parseJson(json, string.concat(prefix, ".commitmentCiphertext")), (bytes[])).length;
        bp.commitmentCiphertext = new CommitmentCiphertext[](len);
        for (uint256 i = 0; i < len; i++) {
            string memory cp = string.concat(prefix, ".commitmentCiphertext[", vm.toString(i), "]");
            bp.commitmentCiphertext[i] = loadCiphertext(json, cp);
        }
    }

    function loadCiphertext(string memory json, string memory prefix) internal pure returns (CommitmentCiphertext memory c) {
        c.ciphertext = [
            json.readBytes32(string.concat(prefix, ".ciphertext[0]")),
            json.readBytes32(string.concat(prefix, ".ciphertext[1]")),
            json.readBytes32(string.concat(prefix, ".ciphertext[2]")),
            json.readBytes32(string.concat(prefix, ".ciphertext[3]"))
        ];
        c.blindedSenderViewingKey = json.readBytes32(string.concat(prefix, ".blindedSenderViewingKey"));
        c.blindedReceiverViewingKey = json.readBytes32(string.concat(prefix, ".blindedReceiverViewingKey"));
        c.annotationData = json.readBytes(string.concat(prefix, ".annotationData"));
        c.memo = json.readBytes(string.concat(prefix, ".memo"));
    }

    function loadPreimage(string memory json, string memory prefix) internal pure returns (CommitmentPreimage memory p) {
        p.npk = json.readBytes32(string.concat(prefix, ".npk"));
        p.token = TokenData({
            tokenType: TokenType(json.readUint(string.concat(prefix, ".token.tokenType"))),
            tokenAddress: json.readAddress(string.concat(prefix, ".token.tokenAddress")),
            tokenSubID: json.readUint(string.concat(prefix, ".token.tokenSubID"))
        });
        p.value = uint120(json.readUint(string.concat(prefix, ".value")));
    }

    //? Ignore in forge coverage
    function test() public {}
}