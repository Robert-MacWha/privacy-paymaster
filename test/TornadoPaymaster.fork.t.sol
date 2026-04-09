// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {
    IEntryPoint
} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {
    PackedUserOperation
} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";

import {TornadoAccount} from "../src/TornadoAccount.sol";
import {TornadoPaymaster} from "../src/TornadoPaymaster.sol";
import {ITornadoInstance} from "../src/interfaces/ITornadoInstance.sol";

import {TornadoFixtures} from "./fixtures/TornadoFixtures.sol";
import {RevertingReceiver} from "./helpers/RevertingReceiver.sol";

contract TornadoPaymasterForkTest is Test {
    // ----- State -----
    IEntryPoint internal entryPoint;
    ITornadoInstance internal tornado;
    TornadoAccount internal account;
    TornadoPaymaster internal paymaster;
    uint256 internal denomination;

    // paymasterAndData gas-limit fields. These are sized generously and
    // the tests don't stress them — they only need to be large enough for
    // validation + postOp to run in handleOps.
    uint128 internal constant PM_VERIFICATION_GAS = 300_000;
    uint128 internal constant PM_POST_OP_GAS = 100_000;

    // EntryPoint v0.9 requires `handleOps` to be called by an EOA
    // (tx.origin == msg.sender && msg.sender.code.length == 0). Prank as
    // this address on every handleOps call.
    address internal constant BUNDLER = address(0xB0773);

    // ----- setUp -----
    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("sepolia"), TornadoFixtures.FORK_BLOCK);

        entryPoint = IEntryPoint(TornadoFixtures.ENTRY_POINT_ADDR);
        tornado = ITornadoInstance(TornadoFixtures.TORNADO_INSTANCE_ADDR);
        denomination = tornado.denomination();

        // Account address is not committed to by any proof, so it can land
        // wherever — deploy normally.
        account = new TornadoAccount(entryPoint, tornado);

        //? Paymaster must land at the exact address the snapshot proofs
        //? commit to (recipient public input). Use forge-std's
        //? `deployCodeTo` to run the constructor in-place at a fixed
        //? address — independent of bytecode changes, constructor args,
        //? or deployer nonce. This means setUp no longer exercises
        //? Deploy.s.sol; the script is instead smoke-tested separately.
        deployCodeTo(
            "TornadoPaymaster.sol:TornadoPaymaster",
            abi.encode(
                entryPoint,
                TornadoFixtures.PAYMASTER_OWNER,
                tornado,
                account
            ),
            TornadoFixtures.PAYMASTER_EXPECTED
        );
        paymaster = TornadoPaymaster(
            payable(TornadoFixtures.PAYMASTER_EXPECTED)
        );

        // Fund paymaster's EntryPoint deposit (not stake — stake is only
        // enforced in the alt-mempool simulation path, not handleOps).
        vm.deal(address(this), 10 ether);
        entryPoint.depositTo{value: 1 ether}(address(paymaster));

        // Plant the known deposit matching COMMITMENT so the snapshot
        // proofs verify against the post-deposit merkle root.
        address depositor = address(0xDEADBEEF);
        vm.deal(depositor, denomination);
        vm.prank(depositor);
        tornado.deposit{value: denomination}(TornadoFixtures.COMMITMENT);
    }

    // ----- Helpers -----
    function _buildUserOp(
        bytes memory proof,
        bytes32 root,
        bytes32 nullifier,
        address recipient,
        uint256 refund,
        address destination
    ) internal view returns (PackedUserOperation memory op) {
        op.sender = address(account);
        op.nonce = entryPoint.getNonce(address(account), 0);
        op.initCode = "";
        op.callData = abi.encodeCall(
            TornadoAccount.withdraw,
            (proof, root, nullifier, payable(recipient), refund)
        );

        // accountGasLimits = verificationGasLimit(16) || callGasLimit(16)
        uint128 verificationGasLimit = 500_000;
        uint128 callGasLimit = 1_500_000;
        op.accountGasLimits = bytes32(
            (uint256(verificationGasLimit) << 128) | uint256(callGasLimit)
        );

        op.preVerificationGas = 100_000;

        // gasFees = maxPriorityFeePerGas(16) || maxFeePerGas(16)
        uint128 maxPriorityFeePerGas = 1 gwei;
        uint128 maxFeePerGas = 10 gwei;
        op.gasFees = bytes32(
            (uint256(maxPriorityFeePerGas) << 128) | uint256(maxFeePerGas)
        );

        op.paymasterAndData = abi.encodePacked(
            address(paymaster),
            PM_VERIFICATION_GAS,
            PM_POST_OP_GAS,
            destination
        );
        op.signature = "";
    }

    function _pmBuild(
        bytes memory proof,
        bytes32 root,
        bytes32 nullifier,
        address recipient,
        uint256 refund
    ) internal view returns (PackedUserOperation memory) {
        return
            _buildUserOp(
                proof,
                root,
                nullifier,
                recipient,
                refund,
                address(0xCAFE)
            );
    }

    function _callValidate(PackedUserOperation memory op) internal {
        bytes32 dummyHash = keccak256("userOpHash");
        vm.prank(address(entryPoint));
        paymaster.validatePaymasterUserOp(op, dummyHash, 0);
    }

    // ----- Tests -----

    function test_happyPath() public {
        // Tests the full happy path including 4337's handling of the operation.

        address destination = address(0xC0FFEE);
        assertEq(destination.balance, 0);

        PackedUserOperation memory op = _buildUserOp(
            TornadoFixtures.PROOF_PM,
            TornadoFixtures.ROOT,
            TornadoFixtures.NULLIFIER_HASH,
            address(paymaster),
            0,
            destination
        );

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;

        uint256 pmDepositBefore = entryPoint.balanceOf(address(paymaster));
        vm.prank(BUNDLER, BUNDLER);
        entryPoint.handleOps(ops, payable(BUNDLER));

        // The nullifier is spent.
        assertTrue(
            tornado.nullifierHashes(TornadoFixtures.NULLIFIER_HASH),
            "nullifier not spent"
        );

        // Destination got denom - fee; fee is strictly positive and less
        // than denom (otherwise either postOp math is broken or the safety
        // cap hit and destination got nothing).
        uint256 received = destination.balance;
        assertGt(received, 0, "destination received nothing (cap hit?)");
        assertLt(received, denomination, "fee was zero");

        // Paymaster contract balance is the leftover "fee" portion kept
        // for gas-cost recovery (it forwards denom - fee to destination).
        uint256 feeKept = denomination - received;
        assertEq(address(paymaster).balance, feeKept, "fee not kept");

        // Sanity: EntryPoint deposit was debited for actual gas cost.
        assertLt(
            entryPoint.balanceOf(address(paymaster)),
            pmDepositBefore,
            "deposit not debited"
        );
    }

    function test_valid_proof() public {
        // Tests just that the validation function accepts a valid proof and params.

        PackedUserOperation memory op = _pmBuild(
            TornadoFixtures.PROOF_PM,
            TornadoFixtures.ROOT,
            TornadoFixtures.NULLIFIER_HASH,
            address(paymaster),
            0
        );
        _callValidate(op);
    }

    function test_validation_wrongSender() public {
        // Asserts that the sender in the userOp is checked

        PackedUserOperation memory op = _pmBuild(
            TornadoFixtures.PROOF_PM,
            TornadoFixtures.ROOT,
            TornadoFixtures.NULLIFIER_HASH,
            address(paymaster),
            0
        );
        op.sender = address(0xBAD);

        vm.expectRevert(TornadoPaymaster.InvalidSender.selector);
        _callValidate(op);
    }

    function test_validation_wrongSelector() public {
        // Asserts that the callData selector is checked

        PackedUserOperation memory op = _pmBuild(
            TornadoFixtures.PROOF_PM,
            TornadoFixtures.ROOT,
            TornadoFixtures.NULLIFIER_HASH,
            address(paymaster),
            0
        );
        // Replace the selector only, keep the rest of the calldata intact.
        bytes memory cd = op.callData;
        cd[0] = 0xde;
        cd[1] = 0xad;
        cd[2] = 0xbe;
        cd[3] = 0xef;
        op.callData = cd;

        vm.expectRevert(TornadoPaymaster.InvalidSelector.selector);
        _callValidate(op);
    }

    function test_validation_wrongRecipient() public {
        // callData encodes OTHER_RECIPIENT - fails at recipient check before
        // any proof verification is attempted, so reusing PROOF_OTHER is fine.
        PackedUserOperation memory op = _pmBuild(
            TornadoFixtures.PROOF_OTHER,
            TornadoFixtures.ROOT,
            TornadoFixtures.NULLIFIER_HASH,
            TornadoFixtures.OTHER_RECIPIENT,
            0
        );

        vm.expectRevert(TornadoPaymaster.InvalidRecipient.selector);
        _callValidate(op);
    }

    function test_validation_nonZeroRefund() public {
        PackedUserOperation memory op = _pmBuild(
            TornadoFixtures.PROOF_PM,
            TornadoFixtures.ROOT,
            TornadoFixtures.NULLIFIER_HASH,
            address(paymaster),
            1 // non-zero refund
        );

        vm.expectRevert(TornadoPaymaster.NonZeroRefund.selector);
        _callValidate(op);
    }

    function test_validation_spentNullifier() public {
        // Pre-spend via a direct tornado.withdraw so the nullifier is
        // marked used before the paymaster validation runs.
        tornado.withdraw(
            TornadoFixtures.PROOF_PM,
            TornadoFixtures.ROOT,
            TornadoFixtures.NULLIFIER_HASH,
            payable(address(paymaster)),
            payable(address(0)),
            0,
            0
        );

        PackedUserOperation memory op = _pmBuild(
            TornadoFixtures.PROOF_PM,
            TornadoFixtures.ROOT,
            TornadoFixtures.NULLIFIER_HASH,
            address(paymaster),
            0
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                TornadoPaymaster.NullifierAlreadySpent.selector,
                TornadoFixtures.NULLIFIER_HASH
            )
        );
        _callValidate(op);
    }

    function test_validation_unknownRoot() public {
        bytes32 badRoot = bytes32(uint256(0xBEEF));
        PackedUserOperation memory op = _pmBuild(
            TornadoFixtures.PROOF_PM,
            badRoot,
            TornadoFixtures.NULLIFIER_HASH,
            address(paymaster),
            0
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                TornadoPaymaster.UnknownRoot.selector,
                badRoot
            )
        );
        _callValidate(op);
    }

    function test_validation_invalidProof() public {
        bytes memory tampered = bytes.concat(TornadoFixtures.PROOF_PM);
        // XOR a single byte in the middle of the proof.
        tampered[tampered.length / 2] ^= 0x01;

        PackedUserOperation memory op = _pmBuild(
            tampered,
            TornadoFixtures.ROOT,
            TornadoFixtures.NULLIFIER_HASH,
            address(paymaster),
            0
        );

        vm.expectRevert(TornadoPaymaster.InvalidProof.selector);
        _callValidate(op);
    }

    function test_griefPath() public {
        RevertingReceiver bad = new RevertingReceiver();

        PackedUserOperation memory op = _buildUserOp(
            TornadoFixtures.PROOF_PM,
            TornadoFixtures.ROOT,
            TornadoFixtures.NULLIFIER_HASH,
            address(paymaster),
            0,
            address(bad)
        );
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;

        uint256 depositBefore = entryPoint.balanceOf(address(paymaster));

        // handleOps must NOT revert: _postOp swallows the failed forward
        // (low-level call returns ok=false, we ignore it) so the tornado
        // withdrawal stays committed and the denom is absorbed here.
        // If we ever reintroduce a revert in _postOp, v0.7+ EntryPoint
        // will roll back the whole execution frame and this test will
        // start seeing nullifier-not-spent.
        vm.prank(BUNDLER, BUNDLER);
        entryPoint.handleOps(ops, payable(BUNDLER));

        // Nullifier is spent (the withdrawal landed).
        assertTrue(
            tornado.nullifierHashes(TornadoFixtures.NULLIFIER_HASH),
            "nullifier not spent"
        );
        // The reverting destination got nothing.
        assertEq(address(bad).balance, 0, "reverting receiver got funds");
        // Paymaster kept the whole denomination.
        assertEq(
            address(paymaster).balance,
            denomination,
            "denom not absorbed"
        );

        // Net effect on paymaster is strongly positive: deposit debited by
        // ~actualGasCost, denom gained in full.
        uint256 depositAfter = entryPoint.balanceOf(address(paymaster));
        assertLt(depositAfter, depositBefore, "deposit not debited");
        uint256 gasCost = depositBefore - depositAfter;
        assertLt(
            gasCost,
            denomination,
            "gas cost ate the whole denom - grief disincentive broken"
        );
    }

    // Allow this test contract to receive the handleOps beneficiary payout.
    receive() external payable {}
}
