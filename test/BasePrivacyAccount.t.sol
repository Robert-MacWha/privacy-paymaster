// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {
    IEntryPoint
} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {
    PackedUserOperation
} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";

import {IPrivacyAccount} from "../contracts/interfaces/IPrivacyAccount.sol";
import {BasePrivacyAccount} from "../contracts/accounts/BasePrivacyAccount.sol";

contract BasePrivacyAccountTest is Test {
    address internal succeeder;
    address internal reverter;
    address internal entryPointAddr = address(0x4337);
    BasicPrivacyAccount internal account;

    function setUp() public {
        succeeder = address(new Succeeder());
        reverter = address(new Reverter());
        account = new BasicPrivacyAccount(
            IEntryPoint(entryPointAddr),
            succeeder
        );
    }

    // ----- Helpers -----

    function _noTail() internal pure returns (IPrivacyAccount.Call[] memory) {
        return new IPrivacyAccount.Call[](0);
    }

    function _tail(
        address target,
        bytes memory data
    ) internal pure returns (IPrivacyAccount.Call[] memory calls) {
        calls = new IPrivacyAccount.Call[](1);
        calls[0] = IPrivacyAccount.Call({target: target, data: data});
    }

    function _tail2(
        address t1,
        address t2
    ) internal pure returns (IPrivacyAccount.Call[] memory calls) {
        calls = new IPrivacyAccount.Call[](2);
        calls[0] = IPrivacyAccount.Call({target: t1, data: ""});
        calls[1] = IPrivacyAccount.Call({target: t2, data: ""});
    }

    // ----- Tests -----

    function test_rejectsNonEntryPoint() public {
        vm.expectRevert(BasePrivacyAccount.CallerNotEntryPoint.selector);
        account.execute(new bytes(0), _noTail());
    }

    function test_validateUserOp_rejectsNonEntryPoint() public {
        PackedUserOperation memory userOp;
        vm.expectRevert(BasePrivacyAccount.CallerNotEntryPoint.selector);
        account.validateUserOp(userOp, bytes32(0), 0);
    }

    function test_validateUserOp_returnsZero() public {
        PackedUserOperation memory userOp;
        vm.prank(entryPointAddr);
        uint256 result = account.validateUserOp(userOp, bytes32(0), 0);
        assertEq(result, 0);
    }

    function test_unshieldSucceeds_noTail() public {
        vm.prank(entryPointAddr);
        account.execute(new bytes(0), _noTail());
    }

    function test_feeFailed() public {
        BasicPrivacyAccount bad = new BasicPrivacyAccount(
            IEntryPoint(entryPointAddr),
            reverter
        );
        vm.prank(entryPointAddr);
        vm.expectRevert(
            abi.encodeWithSelector(BasePrivacyAccount.FeeFailed.selector, "")
        );
        bad.execute(new bytes(0), _noTail());
    }

    function test_tailCallSucceeds_emitsEvent() public {
        vm.expectEmit(true, false, false, false);
        emit BasePrivacyAccount.TailCallsExecuted();
        vm.prank(entryPointAddr);
        account.execute(new bytes(0), _tail(succeeder, ""));
    }

    function test_tailCallReverts_emitsEvent() public {
        vm.expectEmit(true, true, false, false);
        emit BasePrivacyAccount.TailCallFailed("");
        vm.prank(entryPointAddr);
        account.execute(new bytes(0), _tail(reverter, ""));
    }

    function test_tailCallReverts_doesNotRevert() public {
        vm.prank(entryPointAddr);
        account.execute(new bytes(0), _tail(reverter, ""));
    }

    function test_tailCalls_partialFailure() public {
        vm.expectEmit(true, true, false, false);
        emit BasePrivacyAccount.TailCallFailed("");
        vm.prank(entryPointAddr);
        account.execute(new bytes(0), _tail2(succeeder, reverter));
    }

    function test_executeTailCalls_rejectsNonSelf() public {
        vm.expectRevert(BasePrivacyAccount.OnlySelf.selector);
        account._executeTailCalls(_noTail());
    }
}

contract BasicPrivacyAccount is BasePrivacyAccount {
    constructor(
        IEntryPoint _entryPoint,
        address _protocolTarget
    ) BasePrivacyAccount(_entryPoint, _protocolTarget) {}

    function previewFee(
        bytes calldata,
        bytes calldata
    ) external pure override returns (address, uint256) {
        return (address(0), 0);
    }

    function test() public {}
}

contract Succeeder {
    fallback() external payable {}
    receive() external payable {}
    function test() external {}
}

contract Reverter {
    fallback() external payable {
        revert();
    }
    receive() external payable {
        revert();
    }
    function test() external {}
}
