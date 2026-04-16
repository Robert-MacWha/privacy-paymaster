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
import {IPrivacyAccount} from "../src/interfaces/IPrivacyAccount.sol";
import {TornadoAccount} from "../src/accounts/tornadocash/TornadoAccount.sol";
import {
    ITornadoInstance
} from "../src/accounts/tornadocash/interfaces/ITornadoInstance.sol";

import {TornadoFixtures} from "./fixtures/TornadoFixtures.sol";
import {DeployPaymaster} from "../script/DeployPaymaster.s.sol";
import {StakePaymaster} from "../script/StakePaymaster.s.sol";
import {DeployTornado} from "../script/DeployTornado.s.sol";

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
        vm.deal(vm.addr(TornadoFixtures.PRIVATE_KEY), 1000 ether);

        entryPoint = IEntryPoint(TornadoFixtures.ENTRY_POINT_ADDR);
        tornado = ITornadoInstance(TornadoFixtures.TORNADO_INSTANCE_ADDR);
        denomination = tornado.denomination();

        address paymasterAddr = new DeployPaymaster().deploy(
            TornadoFixtures.ENTRY_POINT_ADDR,
            address(0),
            address(0),
            0,
            TornadoFixtures.PRIVATE_KEY
        );
        paymaster = PrivacyPaymaster(payable(paymasterAddr));

        new StakePaymaster().stake(
            paymasterAddr,
            1 ether,
            3600,
            1 ether,
            TornadoFixtures.PRIVATE_KEY
        );

        address tornadoAccountAddr = new DeployTornado().deploy(
            paymasterAddr,
            TornadoFixtures.TORNADO_INSTANCE_ADDR,
            TornadoFixtures.PRIVATE_KEY
        );
        account = TornadoAccount(tornadoAccountAddr);

        // Deposit snapshot note into tc instance for tests
        address depositor = address(0xDEADBEEF);
        vm.deal(depositor, denomination);
        vm.prank(depositor);
        tornado.deposit{value: denomination}(TornadoFixtures.COMMITMENT);
    }

    // ----- Tests -----

    function test_happyPath() public {
        assertEq(TornadoFixtures.RECIPIENT.balance, 0);

        PackedUserOperation memory op = _buildUserOp(
            TornadoFixtures.PROOF_VALID,
            TornadoFixtures.ROOT,
            TornadoFixtures.NULLIFIER_HASH,
            TornadoFixtures.RECIPIENT,
            TornadoFixtures.PAYMASTER,
            TornadoFixtures.FEE,
            0
        );

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;

        //? EntryPoint's nonReentrant guard requires the sender to be an EOA.
        vm.prank(BUNDLER, BUNDLER);
        entryPoint.handleOps(ops, payable(BUNDLER));

        // The nullifier is spent.
        assertTrue(
            tornado.nullifierHashes(TornadoFixtures.NULLIFIER_HASH),
            "nullifier not spent"
        );

        // Destination got funds minus fee.
        assertEq(
            TornadoFixtures.RECIPIENT.balance,
            denomination - TornadoFixtures.FEE,
            "Fee not paid"
        );

        // Paymaster got fee.
        assertEq(
            TornadoFixtures.PAYMASTER.balance,
            TornadoFixtures.FEE,
            "Fee not kept"
        );
    }

    function test_invalidSelector() public {
        bytes memory cd = abi.encodeCall(
            ITornadoInstance.withdraw,
            (
                TornadoFixtures.PROOF_VALID,
                TornadoFixtures.ROOT,
                TornadoFixtures.NULLIFIER_HASH,
                payable(TornadoFixtures.RECIPIENT),
                payable(TornadoFixtures.PAYMASTER),
                TornadoFixtures.FEE,
                0
            )
        );
        // Corrupt the selector to make it invalid.
        cd[0] = 0xde;
        cd[1] = 0xad;
        cd[2] = 0xbe;
        cd[3] = 0xef;
        vm.expectRevert(
            abi.encodeWithSelector(
                PrivacyPaymaster.InvalidSelector.selector,
                bytes4(0xDEADBEEF)
            )
        );
        vm.prank(TornadoFixtures.PAYMASTER);
        account.previewUnshield(cd);
    }

    function test_sweep() public {
        // Fund the paymaster directly, then sweep to a fresh recipient.
        vm.deal(address(paymaster), 3 ether);

        address payable to = payable(address(0xBEEF));
        uint256 toBefore = to.balance;

        vm.prank(vm.addr(TornadoFixtures.PRIVATE_KEY));
        paymaster.sweep(to);

        assertEq(address(paymaster).balance, 0, "paymaster not drained");
        assertEq(
            to.balance - toBefore,
            3 ether,
            "recipient did not receive funds"
        );
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
