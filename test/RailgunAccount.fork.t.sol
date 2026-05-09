// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {
    IEntryPoint
} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {RailgunAccount} from "../contracts/accounts/railgun/RailgunAccount.sol";
import {
    IRailgunSmartWallet, Transaction, ShieldRequest
} from "../contracts/accounts/railgun/interfaces/IRailgunSmartWallet.sol";

import {
    ShieldCiphertext, TokenData, TokenType, CommitmentPreimage
} from "../contracts/accounts/railgun/Globals.sol";

import {RailgunFixtures} from "./fixtures/RailgunFixtures.sol";
import {RailgunJson} from "./utils/RailgunJson.sol";

contract RailgunAccountForkTest is Test, RailgunJson {
    IRailgunSmartWallet internal railgun;
    RailgunAccount internal account;
    uint256 internal denomination;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("sepolia"), RailgunFixtures.FORK_BLOCK);

        railgun = IRailgunSmartWallet(
            RailgunFixtures.RAILGUN_SMART_WALLET_ADDR
        );
        account = new RailgunAccount(
            IEntryPoint(RailgunFixtures.ENTRY_POINT_ADDR),
            railgun,
            RailgunFixtures.MASTER_PUBLIC_KEY
        );

        address depositor = address(0xDEADBEEF);
        vm.deal(depositor, 100 ether);
        
        vm.prank(depositor);
        (bool ok,) = RailgunFixtures.WETH.call{value: 1 ether}(abi.encodeWithSignature("deposit()"));
        require(ok, "WETH deposit failed");

        vm.prank(depositor);
        IERC20(RailgunFixtures.WETH).approve(
            RailgunFixtures.RAILGUN_SMART_WALLET_ADDR,
            1 ether
        );
        
        vm.prank(depositor);
        ShieldRequest[] memory requests = new ShieldRequest[](1);
        string memory json = vm.readFile("./test/fixtures/shield-railgun.json");
        requests[0] = super.loadShield(json);
        railgun.shield(requests);
    }

    function _evaluate(
        Transaction memory transaction,
        bytes memory paymasterAndData
    ) internal {
        Transaction[] memory transactions = new Transaction[](1);
        transactions[0] = transaction;

        bytes memory cd = abi.encodeCall(
            IRailgunSmartWallet.transact,
            transactions
        );
        vm.prank(RailgunFixtures.PAYMASTER);
        account.previewFee(cd, paymasterAndData);
    }

    // ----- Tests -----
    function test_valid() public {
        bytes memory paymasterAndDataPrefix = hex"00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
        bytes memory paymasterAndDataValue = hex"1b82476ce9817694ef807ea95459994800000000000000000000000000000000000000000000000000000000fff9976782d46cc05630d1f6ebab18b2324d6b140000000000000000000000000000000000000000000000000007ab3d8927f87a";
        bytes memory paymasterAndData = bytes.concat(paymasterAndDataPrefix, paymasterAndDataValue);

        string memory json = vm.readFile("./test/fixtures/transaction-railgun.json");
        _evaluate(super.loadTransaction(json), paymasterAndData);
    }

    function test_invalid_selector() public {
        bytes memory cd = hex"DEADBEEF";
        vm.expectRevert(abi.encodeWithSelector(RailgunAccount.InvalidSelector.selector, bytes4(0xDEADBEEF)));
        vm.prank(RailgunFixtures.PAYMASTER);
        account.previewFee(cd, "");
    }

    function test_invalid_transaction_count() public {
        string memory json = vm.readFile("./test/fixtures/transaction-railgun.json");
        Transaction memory transaction = super.loadTransaction(json);

        Transaction[] memory transactions = new Transaction[](2);
        transactions[0] = transaction;
        transactions[1] = transaction;

        bytes memory cd = abi.encodeCall(
            IRailgunSmartWallet.transact,
            transactions
        );
        
        vm.prank(RailgunFixtures.PAYMASTER);
        vm.expectRevert(abi.encodeWithSelector(RailgunAccount.InvalidTransactionsLength.selector, 2));
        account.previewFee(cd, "");
    }

    function test_invalid_paymaster_and_data() public {
        string memory json = vm.readFile("./test/fixtures/transaction-railgun.json");
        Transaction memory transaction = super.loadTransaction(json);

        vm.expectRevert(abi.encodeWithSelector(RailgunAccount.PaymasterConfigLengthInvalid.selector, 0));
        _evaluate(transaction, "");
    }

    function test_missing_fee_commitment() public {
        string memory json = vm.readFile("./test/fixtures/transaction-railgun.json");
        Transaction memory transaction = super.loadTransaction(json);
        // Zero all commitments
        for (uint256 i = 0; i < transaction.commitments.length; i ++) {
            transaction.commitments[i] = bytes32(0);
        }

        vm.expectRevert(abi.encodeWithSelector(RailgunAccount.MissingFee.selector, 0x19acdde26147205d58fd7768be7c011f08a147ef86e6b70968d09c81cef74b13, bytes16(0x1b82476ce9817694ef807ea954599948), 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14, 2158605619427450));
        _evaluate(transaction, RailgunFixtures.paymasterAndData());
    }

    function test_spent_nullifier() public {
        string memory json = vm.readFile("./test/fixtures/transaction-railgun.json");
        Transaction memory transaction = super.loadTransaction(json);
        
        Transaction[] memory transactions = new Transaction[](1);
        transactions[0] = transaction;
        railgun.transact(transactions);

        vm.expectRevert(abi.encodeWithSelector(RailgunAccount.NullifierAlreadyUsed.selector, 0, transaction.nullifiers[0]));
        _evaluate(transaction, RailgunFixtures.paymasterAndData());
    }

    function test_invalid_transaction() public {
        string memory json = vm.readFile("./test/fixtures/transaction-railgun.json");
        Transaction memory transaction = super.loadTransaction(json);

        transaction.merkleRoot = bytes32(0);

        vm.expectRevert(abi.encodeWithSelector(RailgunAccount.InvalidTransaction.selector, "Invalid Merkle Root"));
        _evaluate(transaction, RailgunFixtures.paymasterAndData());
    }
}
