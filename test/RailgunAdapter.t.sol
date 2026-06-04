// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Chains} from "../script/lib/Chains.sol";

import {
    IEntryPoint
} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {
    PackedUserOperation
} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {
    IUniswapV3Factory
} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {PaymasterLib} from "../contracts/libraries/PaymasterLib.sol";
import {PrivacyPaymaster} from "../contracts/PrivacyPaymaster.sol";
import {
    IRailgunSmartWallet
} from "../contracts/fee_adapters/railgun/interfaces/IRailgunSmartWallet.sol";
import {
    RailgunFeeAdapter
} from "../contracts/fee_adapters/railgun/RailgunFeeAdapter.sol";
import {
    Transaction,
    ShieldRequest
} from "../contracts/fee_adapters/railgun/Globals.sol";
import {RailgunFixtures} from "./fixtures/RailgunFixtures.sol";

contract RailgunFeeAdapterForkTest is Test {
    IRailgunSmartWallet internal railgun;
    RailgunFeeAdapter internal adapter;
    PrivacyPaymaster internal paymaster;
    address internal entryPointAddr;
    bytes32 internal masterPublicKey;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("sepolia"), RailgunFixtures.FORK_BLOCK);

        entryPointAddr = Chains.readAddress("protocols.erc4337", "entry_point");
        address factory = Chains.readAddress("protocols.uniswap_v3", "factory");
        address weth = Chains.readAddress("tokens", "weth");
        uint32 twapPeriod = uint32(
            Chains.readUint("protocols.uniswap_v3", "twap_period")
        );
        address smartWalletAddr = Chains.readAddress(
            "protocols.railgun",
            "smart_wallet"
        );
        masterPublicKey = Chains.readBytes32(
            "protocols.railgun",
            "master_public_key"
        );

        railgun = IRailgunSmartWallet(smartWalletAddr);

        address depositor = address(0xDEADBEEF);
        vm.deal(depositor, 1 ether);
        vm.prank(depositor);
        (bool ok, ) = weth.call{value: 1 ether}(
            abi.encodeWithSignature("deposit()")
        );
        require(ok, "WETH deposit failed");
        vm.prank(depositor);
        IERC20(weth).approve(smartWalletAddr, 1 ether);

        ShieldRequest[] memory requests = new ShieldRequest[](1);
        requests[0] = RailgunFixtures.loadShield();
        vm.prank(depositor);
        railgun.shield(requests);

        adapter = new RailgunFeeAdapter(railgun, masterPublicKey);
        paymaster = new PrivacyPaymaster(
            IEntryPoint(entryPointAddr),
            IUniswapV3Factory(factory),
            weth,
            twapPeriod
        );
        paymaster.setApprovedAdapter(address(adapter), true);
    }

    // ----- Helpers -----

    function _buildUserOp(
        Transaction memory t
    ) internal view returns (PackedUserOperation memory op) {
        Transaction[] memory transactions = new Transaction[](1);
        transactions[0] = t;

        bytes memory adapterData = abi.encode(
            RailgunFeeAdapter.AdapterData({
                random: RailgunFixtures.loadRandom(),
                asset: RailgunFixtures.loadAsset(),
                value: RailgunFixtures.loadValue(),
                transactions: transactions
            })
        );
        bytes memory paymasterData = abi.encode(
            PaymasterLib.PaymasterData({
                adapter: address(adapter),
                adapterData: adapterData
            })
        );
        op.sender = address(0); // matches fixture's adaptParams = bytes32(0)
        op.paymasterAndData = abi.encodePacked(
            address(paymaster),
            uint128(500_000),
            uint128(50_000),
            paymasterData
        );
    }

    // ----- Tests -----

    function test_valid() public {
        PackedUserOperation memory op = _buildUserOp(
            RailgunFixtures.loadTransaction()
        );
        vm.prank(entryPointAddr);
        (bytes memory context, uint256 validationData) = paymaster
            .validatePaymasterUserOp(
                op,
                bytes32(0),
                uint256(RailgunFixtures.loadValue())
            );
        assertEq(context, "");
        assertEq(validationData, 0);
    }

    function test_adaptParamsNotSender() public {
        PackedUserOperation memory op = _buildUserOp(
            RailgunFixtures.loadTransaction()
        );
        op.sender = address(0xDEAD);
        vm.expectRevert(
            abi.encodeWithSelector(
                RailgunFeeAdapter.AdaptParamsAreNotSender.selector,
                bytes32(0),
                address(0xDEAD)
            )
        );
        vm.prank(entryPointAddr);
        paymaster.validatePaymasterUserOp(
            op,
            bytes32(0),
            uint256(RailgunFixtures.loadValue())
        );
    }

    function test_malformedAdapterData() public {
        bytes memory paymasterData = abi.encode(
            PaymasterLib.PaymasterData({
                adapter: address(adapter),
                adapterData: hex"deadbeef"
            })
        );
        PackedUserOperation memory op;
        op.sender = address(0);
        op.paymasterAndData = abi.encodePacked(
            address(paymaster),
            uint128(500_000),
            uint128(50_000),
            paymasterData
        );
        vm.expectRevert(RailgunFeeAdapter.MalformedAdapterData.selector);
        vm.prank(entryPointAddr);
        paymaster.validatePaymasterUserOp(
            op,
            bytes32(0),
            uint256(RailgunFixtures.loadValue())
        );
    }

    function test_missingFee() public {
        Transaction memory t = RailgunFixtures.loadTransaction();
        for (uint256 i = 0; i < t.commitments.length; i++) {
            t.commitments[i] = bytes32(0);
        }
        PackedUserOperation memory op = _buildUserOp(t);
        vm.expectRevert(
            abi.encodeWithSelector(
                RailgunFeeAdapter.MissingFee.selector,
                masterPublicKey,
                RailgunFixtures.loadRandom(),
                RailgunFixtures.loadAsset(),
                RailgunFixtures.loadValue()
            )
        );
        vm.prank(entryPointAddr);
        paymaster.validatePaymasterUserOp(
            op,
            bytes32(0),
            uint256(RailgunFixtures.loadValue())
        );
    }
}
