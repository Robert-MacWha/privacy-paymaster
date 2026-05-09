// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Chains} from "../script/lib/Chains.sol";

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
    address internal paymaster;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("sepolia"), TornadoFixtures.FORK_BLOCK);

        address tornadoAddr = Chains.readAddress(
            "protocols.tornado.eth_1",
            "instance"
        );
        address entryPointAddr = Chains.readAddress(
            "protocols.erc4337",
            "entry_point"
        );
        paymaster = TornadoFixtures.loadRelayer();

        tornado = ITornadoInstance(tornadoAddr);
        IEntryPoint entryPoint = IEntryPoint(entryPointAddr);
        denomination = tornado.denomination();
        account = new TornadoAccount(entryPoint, tornado, address(0));

        address depositor = address(0xDEADBEEF);
        vm.deal(depositor, denomination);
        vm.prank(depositor);
        tornado.deposit{value: denomination}(TornadoFixtures.loadCommitment());
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
        account.previewFee(cd, "");
    }

    // ----- Tests -----

    function test_valid() public {
        _evaluate(
            TornadoFixtures.loadProof(),
            TornadoFixtures.loadRoot(),
            TornadoFixtures.loadNullifierHash(),
            TornadoFixtures.loadRecipient(),
            TornadoFixtures.loadRelayer(),
            TornadoFixtures.loadFee(),
            0
        );
    }

    function test_invalidSelector() public {
        bytes memory cd = abi.encodeCall(
            ITornadoInstance.withdraw,
            (
                TornadoFixtures.loadProof(),
                TornadoFixtures.loadRoot(),
                TornadoFixtures.loadNullifierHash(),
                TornadoFixtures.loadRecipient(),
                TornadoFixtures.loadRelayer(),
                TornadoFixtures.loadFee(),
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
        vm.prank(paymaster);
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
            TornadoFixtures.loadProof(),
            TornadoFixtures.loadRoot(),
            TornadoFixtures.loadNullifierHash(),
            payable(address(0)),
            TornadoFixtures.loadRelayer(),
            TornadoFixtures.loadFee(),
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
            TornadoFixtures.loadProof(),
            TornadoFixtures.loadRoot(),
            TornadoFixtures.loadNullifierHash(),
            TornadoFixtures.loadRecipient(),
            payable(address(0xDEAD)),
            TornadoFixtures.loadFee(),
            0
        );
    }

    function test_zeroFee() public {
        vm.expectRevert(
            abi.encodeWithSelector(TornadoAccount.InvalidFee.selector, 0)
        );
        _evaluate(
            TornadoFixtures.loadProof(),
            TornadoFixtures.loadRoot(),
            TornadoFixtures.loadNullifierHash(),
            TornadoFixtures.loadRecipient(),
            TornadoFixtures.loadRelayer(),
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
            TornadoFixtures.loadProof(),
            TornadoFixtures.loadRoot(),
            TornadoFixtures.loadNullifierHash(),
            TornadoFixtures.loadRecipient(),
            TornadoFixtures.loadRelayer(),
            100 ether,
            0
        );
    }

    function test_nonZeroRefund() public {
        vm.expectRevert(TornadoAccount.NonZeroRefund.selector);
        _evaluate(
            TornadoFixtures.loadProof(),
            TornadoFixtures.loadRoot(),
            TornadoFixtures.loadNullifierHash(),
            TornadoFixtures.loadRecipient(),
            TornadoFixtures.loadRelayer(),
            TornadoFixtures.loadFee(),
            1
        );
    }

    function test_spentNullifier() public {
        tornado.withdraw(
            TornadoFixtures.loadProof(),
            TornadoFixtures.loadRoot(),
            TornadoFixtures.loadNullifierHash(),
            TornadoFixtures.loadRecipient(),
            TornadoFixtures.loadRelayer(),
            TornadoFixtures.loadFee(),
            0
        );
        vm.expectRevert(TornadoAccount.NullifierAlreadySpent.selector);
        _evaluate(
            TornadoFixtures.loadProof(),
            TornadoFixtures.loadRoot(),
            TornadoFixtures.loadNullifierHash(),
            TornadoFixtures.loadRecipient(),
            TornadoFixtures.loadRelayer(),
            TornadoFixtures.loadFee(),
            0
        );
    }

    function test_unknownRoot() public {
        vm.expectRevert(TornadoAccount.UnknownRoot.selector);
        _evaluate(
            TornadoFixtures.loadProof(),
            bytes32(uint256(0xBEEF)),
            TornadoFixtures.loadNullifierHash(),
            TornadoFixtures.loadRecipient(),
            TornadoFixtures.loadRelayer(),
            TornadoFixtures.loadFee(),
            0
        );
    }

    function test_invalidProof() public {
        vm.expectRevert(TornadoAccount.InvalidProof.selector);
        _evaluate(
            bytes("invalid proof"),
            TornadoFixtures.loadRoot(),
            TornadoFixtures.loadNullifierHash(),
            TornadoFixtures.loadRecipient(),
            TornadoFixtures.loadRelayer(),
            TornadoFixtures.loadFee(),
            0
        );
    }
}
