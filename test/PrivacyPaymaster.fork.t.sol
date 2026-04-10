// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {
    IEntryPoint
} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {
    PackedUserOperation
} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";

import {PrivacyPaymaster} from "../src/PrivacyPaymaster.sol";
import {BasePrivacyAccount} from "../src/accounts/BasePrivacyAccount.sol";
import {TornadoAccount} from "../src/accounts/TornadoAccount.sol";
import {IPrivacyAccount} from "../src/accounts/IPrivacyAccount.sol";
import {ITornadoInstance} from "../src/interfaces/ITornadoInstance.sol";

import {TornadoFixtures} from "./fixtures/TornadoFixtures.sol";

contract PrivacyPaymasterForkTest is Test {
    IEntryPoint internal entryPoint;
    ITornadoInstance internal tornado;
    TornadoAccount internal account;
    PrivacyPaymaster internal paymaster;
    uint256 internal denomination;

    uint128 internal constant PM_VERIFICATION_GAS = 300_000;
    uint128 internal constant PM_POST_OP_GAS = 100_000;
    address internal constant BUNDLER = address(0xB0773);

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("sepolia"), TornadoFixtures.FORK_BLOCK);

        entryPoint = IEntryPoint(TornadoFixtures.ENTRY_POINT_ADDR);
        tornado = ITornadoInstance(TornadoFixtures.TORNADO_INSTANCE_ADDR);
        denomination = tornado.denomination();
        account = new TornadoAccount(entryPoint, tornado, address(0));

        //? Paymaster must land at the exact address the snapshot proofs
        //? commit to (recipient public input). Use forge-std's
        //? `deployCodeTo` to run the constructor in-place at a fixed
        //? address — independent of bytecode changes, constructor args,
        //? or deployer nonce. This means setUp no longer exercises
        //? Deploy.s.sol; the script is instead smoke-tested separately.
        deployCodeTo(
            "PrivacyPaymaster.sol:PrivacyPaymaster",
            abi.encode(
                entryPoint,
                TornadoFixtures.PAYMASTER_OWNER,
                address(0),
                address(0),
                uint32(0)
            ),
            TornadoFixtures.PAYMASTER_EXPECTED
        );
        paymaster = PrivacyPaymaster(
            payable(TornadoFixtures.PAYMASTER_EXPECTED)
        );

        // Whitelist the account.
        vm.prank(TornadoFixtures.PAYMASTER_OWNER);
        paymaster.setApprovedSender(address(account), true);

        // Fund paymaster's EntryPoint deposit.
        vm.deal(address(this), 10 ether);
        entryPoint.depositTo{value: 1 ether}(address(paymaster));

        // Plant the known deposit matching COMMITMENT so the snapshot
        // proofs verify against the post-deposit merkle root.
        address depositor = address(0xDEADBEEF);
        vm.deal(depositor, denomination);
        vm.prank(depositor);
        tornado.deposit{value: denomination}(TornadoFixtures.COMMITMENT);
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
            address(0xC0FFEE),
            0,
            0
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

    function test_validation_wrongSender() public {
        // Asserts that the sender in the userOp is checked

        PackedUserOperation memory op = _buildUserOp(
            TornadoFixtures.PROOF_PM,
            TornadoFixtures.ROOT,
            TornadoFixtures.NULLIFIER_HASH,
            address(paymaster),
            address(0xC0FFEE),
            0,
            0
        );
        op.sender = address(0xBAD);

        vm.expectRevert(
            abi.encodeWithSelector(
                PrivacyPaymaster.SenderNotApproved.selector,
                address(0xBAD)
            )
        );

        bytes32 dummyHash = keccak256("userOpHash");
        vm.prank(address(entryPoint));
        paymaster.validatePaymasterUserOp(op, dummyHash, 0);
    }

    function test_sweep() public {
        // Fund the paymaster directly, then sweep to a fresh recipient.
        vm.deal(address(paymaster), 3 ether);

        address payable to = payable(address(0xBEEF));
        uint256 toBefore = to.balance;

        vm.prank(TornadoFixtures.PAYMASTER_OWNER);
        paymaster.sweep(to);

        assertEq(address(paymaster).balance, 0, "paymaster not drained");
        assertEq(
            to.balance - toBefore,
            3 ether,
            "recipient did not receive funds"
        );
    }

    function test_account_validateUserOp_rejectsNonEntryPoint() public {
        PackedUserOperation memory op = _buildUserOp(
            TornadoFixtures.PROOF_PM,
            TornadoFixtures.ROOT,
            TornadoFixtures.NULLIFIER_HASH,
            address(paymaster),
            address(0xC0FFEE),
            0,
            0
        );
        vm.expectRevert(BasePrivacyAccount.CallerNotEntryPoint.selector);
        account.validateUserOp(op, bytes32(0), 0);
    }

    function test_sweep_rejectsNonOwner() public {
        vm.deal(address(paymaster), 1 ether);
        vm.prank(address(0xBAD));
        vm.expectRevert(); // OZ Ownable: OwnableUnauthorizedAccount(address)
        paymaster.sweep(payable(address(0xBAD)));
    }

    // ----- Helpers -----
    function _buildUserOp(
        bytes memory proof,
        bytes32 root,
        bytes32 nullifier,
        address recipient,
        address relayer,
        uint256 fee,
        uint256 refund
    ) internal view returns (PackedUserOperation memory op) {
        op.sender = address(account);
        op.nonce = entryPoint.getNonce(address(account), 0);
        op.initCode = "";

        bytes memory unshieldCalldata = abi.encodeCall(
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
        IPrivacyAccount.Call[] memory tail = new IPrivacyAccount.Call[](0);
        op.callData = abi.encodeCall(
            IPrivacyAccount.execute,
            (unshieldCalldata, tail)
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
            PM_POST_OP_GAS
        );
        op.signature = "";
    }
}
