// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {
    IEntryPoint
} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";

import {
    TornadoAccount
} from "../contracts/accounts/tornadocash/TornadoAccount.sol";
import {
    ITornadoInstance
} from "../contracts/accounts/tornadocash/interfaces/ITornadoInstance.sol";

import {TornadoFixtures} from "./fixtures/TornadoFixtures.sol";

contract TornadoAccountForkTest is Test {
    ITornadoInstance internal tornado;
    TornadoAccount internal account;
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
        vm.prank(TornadoFixtures.PAYMASTER);
        account.previewFee(cd, "");
    }

    // ----- Tests -----

    function test_valid() public {
        _evaluate(
            TornadoFixtures.PROOF_VALID,
            TornadoFixtures.ROOT,
            TornadoFixtures.NULLIFIER_HASH,
            TornadoFixtures.RECIPIENT,
            TornadoFixtures.PAYMASTER,
            TornadoFixtures.FEE,
            0
        );
    }

    function test_invalidSelector() public {
        bytes memory cd = abi.encodeCall(
            ITornadoInstance.withdraw,
            (
                TornadoFixtures.PROOF_VALID,
                TornadoFixtures.ROOT,
                TornadoFixtures.NULLIFIER_HASH,
                TornadoFixtures.RECIPIENT,
                TornadoFixtures.PAYMASTER,
                TornadoFixtures.FEE,
                0
            )
        );
        cd[0] = 0xde;
        cd[1] = 0xad;
        cd[2] = 0xbe;
        cd[3] = 0xef;
        vm.expectRevert(
            abi.encodeWithSelector(
                TornadoAccount.InvalidSelector.selector,
                bytes4(0xDEADBEEF)
            )
        );
        vm.prank(TornadoFixtures.PAYMASTER);
        account.previewFee(cd, "");
    }

    function test_invalidRecipient() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                TornadoAccount.InvalidRecipient.selector,
                address(0)
            )
        );
        _evaluate(
            TornadoFixtures.PROOF_VALID,
            TornadoFixtures.ROOT,
            TornadoFixtures.NULLIFIER_HASH,
            payable(address(0)),
            TornadoFixtures.PAYMASTER,
            TornadoFixtures.FEE,
            0
        );
    }

    function test_invalidRelayer() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                TornadoAccount.InvalidRelayer.selector,
                address(0xDEAD)
            )
        );
        _evaluate(
            TornadoFixtures.PROOF_VALID,
            TornadoFixtures.ROOT,
            TornadoFixtures.NULLIFIER_HASH,
            TornadoFixtures.RECIPIENT,
            payable(address(0xDEAD)),
            TornadoFixtures.FEE,
            0
        );
    }

    function test_zeroFee() public {
        vm.expectRevert(
            abi.encodeWithSelector(TornadoAccount.InvalidFee.selector, 0)
        );
        _evaluate(
            TornadoFixtures.PROOF_VALID,
            TornadoFixtures.ROOT,
            TornadoFixtures.NULLIFIER_HASH,
            TornadoFixtures.RECIPIENT,
            TornadoFixtures.PAYMASTER,
            0,
            0
        );
    }

    function test_largeFee() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                TornadoAccount.InvalidFee.selector,
                100 ether
            )
        );
        _evaluate(
            TornadoFixtures.PROOF_VALID,
            TornadoFixtures.ROOT,
            TornadoFixtures.NULLIFIER_HASH,
            TornadoFixtures.RECIPIENT,
            TornadoFixtures.PAYMASTER,
            100 ether,
            0
        );
    }

    function test_nonZeroRefund() public {
        vm.expectRevert(TornadoAccount.NonZeroRefund.selector);
        _evaluate(
            TornadoFixtures.PROOF_VALID,
            TornadoFixtures.ROOT,
            TornadoFixtures.NULLIFIER_HASH,
            TornadoFixtures.RECIPIENT,
            TornadoFixtures.PAYMASTER,
            TornadoFixtures.FEE,
            1
        );
    }

    function test_spentNullifier() public {
        tornado.withdraw(
            TornadoFixtures.PROOF_VALID,
            TornadoFixtures.ROOT,
            TornadoFixtures.NULLIFIER_HASH,
            TornadoFixtures.RECIPIENT,
            TornadoFixtures.PAYMASTER,
            TornadoFixtures.FEE,
            0
        );
        vm.expectRevert(TornadoAccount.NullifierAlreadySpent.selector);
        _evaluate(
            TornadoFixtures.PROOF_VALID,
            TornadoFixtures.ROOT,
            TornadoFixtures.NULLIFIER_HASH,
            TornadoFixtures.RECIPIENT,
            TornadoFixtures.PAYMASTER,
            TornadoFixtures.FEE,
            0
        );
    }

    function test_unknownRoot() public {
        vm.expectRevert(TornadoAccount.UnknownRoot.selector);
        _evaluate(
            TornadoFixtures.PROOF_VALID,
            bytes32(uint256(0xBEEF)),
            TornadoFixtures.NULLIFIER_HASH,
            TornadoFixtures.RECIPIENT,
            TornadoFixtures.PAYMASTER,
            TornadoFixtures.FEE,
            0
        );
    }

    function test_invalidProof() public {
        vm.expectRevert(TornadoAccount.InvalidProof.selector);
        _evaluate(
            TornadoFixtures.PROOF_INVALID_PAYMASTER,
            TornadoFixtures.ROOT,
            TornadoFixtures.NULLIFIER_HASH,
            TornadoFixtures.RECIPIENT,
            TornadoFixtures.PAYMASTER,
            TornadoFixtures.FEE,
            0
        );
    }

    function test_invalidProofReverts() public {
        vm.expectRevert(TornadoAccount.InvalidProof.selector);
        _evaluate(
            bytes("invalid proof"),
            TornadoFixtures.ROOT,
            TornadoFixtures.NULLIFIER_HASH,
            TornadoFixtures.RECIPIENT,
            TornadoFixtures.PAYMASTER,
            TornadoFixtures.FEE,
            0
        );
    }
}
