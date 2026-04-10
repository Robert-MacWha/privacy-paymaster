// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {
    IEntryPoint
} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";

import {TornadoAccount} from "../src/accounts/TornadoAccount.sol";
import {ITornadoInstance} from "../src/interfaces/ITornadoInstance.sol";

import {TornadoFixtures} from "./fixtures/TornadoFixtures.sol";

/// Unit tests for TornadoAccount.evaluateUserOperation.
/// No paymaster deployment or EntryPoint funding needed — just the fork,
/// the tornado instance, and the account. msg.sender is spoofed to simulate
/// the paymaster calling in.
contract TornadoAccountForkTest is Test {
    ITornadoInstance internal tornado;
    TornadoAccount internal account;
    address payable internal paymaster =
        payable(TornadoFixtures.PAYMASTER_EXPECTED);
    uint256 internal denomination;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("sepolia"), TornadoFixtures.FORK_BLOCK);

        tornado = ITornadoInstance(TornadoFixtures.TORNADO_INSTANCE_ADDR);
        denomination = tornado.denomination();
        account = new TornadoAccount(
            IEntryPoint(TornadoFixtures.ENTRY_POINT_ADDR),
            tornado,
            address(0)
        );

        address depositor = address(0xDEADBEEF);
        vm.deal(depositor, denomination);
        vm.prank(depositor);
        tornado.deposit{value: denomination}(TornadoFixtures.COMMITMENT);
    }

    // ----- Helpers -----

    function _evaluate(
        bytes memory proof,
        bytes32 root,
        bytes32 nullifier,
        address recipient,
        address relayer,
        uint256 fee,
        uint256 refund
    ) internal {
        bytes memory cd = abi.encodeCall(
            ITornadoInstance.withdraw,
            (
                proof,
                root,
                nullifier,
                payable(recipient),
                payable(relayer),
                fee,
                refund
            )
        );
        vm.prank(paymaster);
        account.evaluateUserOperation(cd);
    }

    // ----- Tests -----

    function test_valid() public {
        _evaluate(
            TornadoFixtures.PROOF_PM,
            TornadoFixtures.ROOT,
            TornadoFixtures.NULLIFIER_HASH,
            paymaster,
            address(0xC0FFEE),
            0,
            0
        );
    }

    function test_invalidSelector() public {
        bytes memory cd = abi.encodeCall(
            ITornadoInstance.withdraw,
            (
                TornadoFixtures.PROOF_PM,
                TornadoFixtures.ROOT,
                TornadoFixtures.NULLIFIER_HASH,
                paymaster,
                payable(address(1)),
                0,
                0
            )
        );
        cd[0] = 0xde;
        cd[1] = 0xad;
        cd[2] = 0xbe;
        cd[3] = 0xef;
        vm.expectRevert(TornadoAccount.InvalidSelector.selector);
        vm.prank(paymaster);
        account.evaluateUserOperation(cd);
    }

    function test_invalidRecipient() public {
        vm.expectRevert(TornadoAccount.InvalidRecipient.selector);
        _evaluate(
            TornadoFixtures.PROOF_PM,
            TornadoFixtures.ROOT,
            TornadoFixtures.NULLIFIER_HASH,
            payable(address(1)),
            payable(address(1)),
            0,
            0
        );
    }

    function test_invalidRelayer() public {
        vm.expectRevert(TornadoAccount.InvalidRelayer.selector);
        _evaluate(
            TornadoFixtures.PROOF_PM,
            TornadoFixtures.ROOT,
            TornadoFixtures.NULLIFIER_HASH,
            paymaster,
            payable(address(0)),
            0,
            0
        );
    }

    function test_nonZeroFee() public {
        vm.expectRevert(TornadoAccount.NonZeroFee.selector);
        _evaluate(
            TornadoFixtures.PROOF_PM,
            TornadoFixtures.ROOT,
            TornadoFixtures.NULLIFIER_HASH,
            paymaster,
            payable(address(0xC0FFEE)),
            1,
            0
        );
    }

    function test_nonZeroRefund() public {
        vm.expectRevert(TornadoAccount.NonZeroRefund.selector);
        _evaluate(
            TornadoFixtures.PROOF_PM,
            TornadoFixtures.ROOT,
            TornadoFixtures.NULLIFIER_HASH,
            paymaster,
            payable(address(1)),
            0,
            1
        );
    }

    function test_spentNullifier() public {
        tornado.withdraw(
            TornadoFixtures.PROOF_PM,
            TornadoFixtures.ROOT,
            TornadoFixtures.NULLIFIER_HASH,
            paymaster,
            payable(address(0xC0FFEE)),
            0,
            0
        );
        vm.expectRevert(TornadoAccount.NullifierAlreadySpent.selector);
        _evaluate(
            TornadoFixtures.PROOF_PM,
            TornadoFixtures.ROOT,
            TornadoFixtures.NULLIFIER_HASH,
            paymaster,
            payable(address(0xC0FFEE)),
            0,
            0
        );
    }

    function test_unknownRoot() public {
        vm.expectRevert(TornadoAccount.UnknownRoot.selector);
        _evaluate(
            TornadoFixtures.PROOF_PM,
            bytes32(uint256(0xBEEF)),
            TornadoFixtures.NULLIFIER_HASH,
            paymaster,
            payable(address(0xC0FFEE)),
            0,
            0
        );
    }

    function test_invalidProof() public {
        bytes memory tampered = bytes.concat(TornadoFixtures.PROOF_PM);
        tampered[tampered.length / 2] ^= 0x01;
        vm.expectRevert(TornadoAccount.InvalidProof.selector);
        _evaluate(
            tampered,
            TornadoFixtures.ROOT,
            TornadoFixtures.NULLIFIER_HASH,
            paymaster,
            payable(address(0xC0FFEE)),
            0,
            0
        );
    }

    function test_proofForDifferentRecipient() public {
        // PROOF_OTHER is valid but bound to OTHER_RECIPIENT. Submitting it
        // with recipient=paymaster passes the early recipient check and must
        // be rejected by the verifier (public inputs no longer match).
        vm.expectRevert(TornadoAccount.InvalidProof.selector);
        _evaluate(
            TornadoFixtures.PROOF_OTHER,
            TornadoFixtures.ROOT,
            TornadoFixtures.NULLIFIER_HASH,
            paymaster,
            payable(address(0xC0FFEE)),
            0,
            0
        );
    }
}
