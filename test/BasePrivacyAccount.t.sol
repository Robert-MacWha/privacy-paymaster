// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test, Vm} from "forge-std/Test.sol";

import {
    IEntryPoint
} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";

import {IPrivacyAccount} from "../contracts/interfaces/IPrivacyAccount.sol";
import {BasePrivacyAccount} from "../contracts/accounts/BasePrivacyAccount.sol";
import {
    TornadoAccount
} from "../contracts/accounts/tornadocash/TornadoAccount.sol";
import {
    ITornadoInstance
} from "../contracts/accounts/tornadocash/interfaces/ITornadoInstance.sol";

contract BasePrivacyAccountTest is Test {
    // Stub that accepts any call without reverting.
    address internal succeeder;

    // Stub that reverts on any call.
    address internal reverter;

    TornadoAccount internal account;

    // Arbitrary address pranked as the EntryPoint.
    address internal constant ENTRY_POINT = address(0xE3);

    function setUp() public {
        succeeder = address(new Succeeder());
        reverter = address(new CallReverter());
        account = new TornadoAccount(
            IEntryPoint(ENTRY_POINT),
            ITornadoInstance(succeeder),
            address(0)
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

    function test_unshieldSucceeds_noTail() public {
        vm.prank(ENTRY_POINT);
        account.execute(new bytes(0), _noTail());
    }

    function test_feeFailed() public {
        TornadoAccount bad = new TornadoAccount(
            IEntryPoint(ENTRY_POINT),
            ITornadoInstance(reverter),
            address(0)
        );
        vm.prank(ENTRY_POINT);
        vm.expectRevert(
            abi.encodeWithSelector(BasePrivacyAccount.FeeFailed.selector, "")
        );
        bad.execute(new bytes(0), _noTail());
    }

    function test_tailCallSucceeds() public {
        // No TailCallFailed event should be emitted.
        vm.recordLogs();
        vm.prank(ENTRY_POINT);
        account.execute(new bytes(0), _tail(succeeder, ""));
        // Filter for TailCallFailed — there should be none.
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sig = keccak256("TailCallFailed(uint256,address,bytes)");
        for (uint256 i = 0; i < logs.length; i++) {
            assertNotEq(logs[i].topics[0], sig, "unexpected TailCallFailed");
        }
    }

    function test_tailCallReverts_emitsEvent() public {
        vm.expectEmit(true, true, false, false);
        emit BasePrivacyAccount.TailCallFailed("");
        vm.prank(ENTRY_POINT);
        account.execute(new bytes(0), _tail(reverter, ""));
    }

    function test_tailCallReverts_doesNotRevert() public {
        // A reverting tail call must NOT bubble up — unshield must stay committed.
        vm.prank(ENTRY_POINT);
        account.execute(new bytes(0), _tail(reverter, ""));
    }

    function test_tailCalls_partialFailure() public {
        // First call succeeds, second reverts — only index 1 should emit.
        vm.expectEmit(true, true, false, false);
        emit BasePrivacyAccount.TailCallFailed("");
        vm.prank(ENTRY_POINT);
        account.execute(new bytes(0), _tail2(succeeder, reverter));
    }
}

/// ITornadoInstance stub — denomination returns 1 ether, all other calls succeed.
contract Succeeder is ITornadoInstance {
    function denomination() external pure override returns (uint256) {
        return 1 ether;
    }
    function verifier() external pure override returns (address) {
        return address(0);
    }
    function deposit(bytes32) external payable override {}
    function isKnownRoot(bytes32) external pure override returns (bool) {
        return true;
    }
    function nullifierHashes(bytes32) external pure override returns (bool) {
        return false;
    }
    function withdraw(
        bytes calldata,
        bytes32,
        bytes32,
        address payable,
        address payable,
        uint256,
        uint256
    ) external override {}
    receive() external payable {}
    fallback() external payable {}

    function test() external {}
}

/// ITornadoInstance stub — denomination returns 1 ether, all other calls revert.
contract CallReverter is ITornadoInstance {
    function denomination() external pure override returns (uint256) {
        return 1 ether;
    }
    function verifier() external pure override returns (address) {
        return address(0);
    }
    function deposit(bytes32) external payable override {
        assembly {
            revert(0, 0)
        }
    }
    function isKnownRoot(bytes32) external pure override returns (bool) {
        return false;
    }
    function nullifierHashes(bytes32) external pure override returns (bool) {
        return false;
    }
    function withdraw(
        bytes calldata,
        bytes32,
        bytes32,
        address payable,
        address payable,
        uint256,
        uint256
    ) external pure override {
        assembly {
            revert(0, 0)
        }
    }
    receive() external payable {
        assembly {
            revert(0, 0)
        }
    }
    fallback() external payable {
        assembly {
            revert(0, 0)
        }
    }

    function test() external {}
}
