// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Chains} from "../script/lib/Chains.sol";

import {
    IEntryPoint
} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {RailgunAccount} from "../contracts/accounts/railgun/RailgunAccount.sol";
import {
    IRailgunSmartWallet,
    Transaction,
    ShieldRequest
} from "../contracts/accounts/railgun/interfaces/IRailgunSmartWallet.sol";

import {
    ShieldCiphertext,
    TokenData,
    TokenType,
    CommitmentPreimage
} from "../contracts/accounts/railgun/Globals.sol";

import {RailgunFixtures} from "./fixtures/RailgunFixtures.sol";

contract RailgunAccountForkTest is Test {
    IRailgunSmartWallet internal railgun;
    RailgunAccount internal account;
    uint256 internal denomination;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("sepolia"), RailgunFixtures.FORK_BLOCK);
        address entryPointAddr = Chains.readAddress(
            "protocols.erc4337",
            "entry_point"
        );
        address weth = Chains.readAddress("tokens", "weth");
        address smartWalletAddr = Chains.readAddress(
            "protocols.railgun",
            "smart_wallet"
        );
        bytes32 masterPublicKey = Chains.readBytes32(
            "protocols.railgun",
            "master_public_key"
        );

        railgun = IRailgunSmartWallet(smartWalletAddr);
        IEntryPoint entryPoint = IEntryPoint(entryPointAddr);
        account = new RailgunAccount(entryPoint, railgun, masterPublicKey);

        address depositor = address(0xDEADBEEF);
        vm.deal(depositor, 100 ether);

        vm.prank(depositor);
        (bool ok, ) = weth.call{value: 1 ether}(
            abi.encodeWithSignature("deposit()")
        );
        require(ok, "WETH deposit failed");

        vm.prank(depositor);
        IERC20(weth).approve(smartWalletAddr, 1 ether);

        vm.prank(depositor);
        ShieldRequest[] memory requests = new ShieldRequest[](1);
        requests[0] = RailgunFixtures.loadShield();
        railgun.shield(requests);
    }

    function _evaluate(
        Transaction memory transaction,
        bytes memory paymasterAndData
    ) internal view {
        Transaction[] memory transactions = new Transaction[](1);
        transactions[0] = transaction;

        bytes memory cd = abi.encodeCall(
            IRailgunSmartWallet.transact,
            transactions
        );
        account.previewFee(cd, paymasterAndData);
    }

    // ----- Tests -----
    function test_valid() public view {
        _evaluate(
            RailgunFixtures.loadTransaction(),
            RailgunFixtures.loadPaymasterAndData()
        );
    }

    function test_invalid_selector() public {
        bytes memory cd = hex"DEADBEEF";
        vm.expectRevert(
            abi.encodeWithSelector(
                RailgunAccount.InvalidSelector.selector,
                bytes4(0xDEADBEEF)
            )
        );
        account.previewFee(cd, "");
    }

    function test_invalid_transaction_count() public {
        Transaction memory transaction = RailgunFixtures.loadTransaction();

        Transaction[] memory transactions = new Transaction[](2);
        transactions[0] = transaction;
        transactions[1] = transaction;

        bytes memory cd = abi.encodeCall(
            IRailgunSmartWallet.transact,
            transactions
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                RailgunAccount.InvalidTransactionsLength.selector,
                2
            )
        );
        account.previewFee(cd, "");
    }

    function test_invalid_paymaster_and_data() public {
        Transaction memory transaction = RailgunFixtures.loadTransaction();

        vm.expectRevert(
            abi.encodeWithSelector(
                RailgunAccount.PaymasterConfigLengthInvalid.selector,
                0
            )
        );
        _evaluate(transaction, "");
    }

    function test_missing_fee_commitment() public {
        Transaction memory transaction = RailgunFixtures.loadTransaction();
        // Zero all commitments
        for (uint256 i = 0; i < transaction.commitments.length; i++) {
            transaction.commitments[i] = bytes32(0);
        }

        vm.expectRevert(
            abi.encodeWithSelector(
                RailgunAccount.MissingFee.selector,
                0x19acdde26147205d58fd7768be7c011f08a147ef86e6b70968d09c81cef74b13,
                bytes16(0x1b82476ce9817694ef807ea954599948),
                0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14,
                2158605619427450
            )
        );
        _evaluate(transaction, RailgunFixtures.loadPaymasterAndData());
    }

    function test_spent_nullifier() public {
        Transaction memory transaction = RailgunFixtures.loadTransaction();

        Transaction[] memory transactions = new Transaction[](1);
        transactions[0] = transaction;
        railgun.transact(transactions);

        vm.expectRevert(
            abi.encodeWithSelector(
                RailgunAccount.NullifierAlreadyUsed.selector,
                0,
                transaction.nullifiers[0]
            )
        );
        _evaluate(transaction, RailgunFixtures.loadPaymasterAndData());
    }

    function test_invalid_transaction() public {
        Transaction memory transaction = RailgunFixtures.loadTransaction();

        transaction.merkleRoot = bytes32(0);

        vm.expectRevert(
            abi.encodeWithSelector(
                RailgunAccount.InvalidTransaction.selector,
                "Invalid Merkle Root"
            )
        );
        _evaluate(transaction, RailgunFixtures.loadPaymasterAndData());
    }
}
