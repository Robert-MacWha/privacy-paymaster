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

import {PaymasterLib} from "../contracts/libraries/PaymasterLib.sol";
import {
    PrivacyPaymaster,
    PostOpContext
} from "../contracts/PrivacyPaymaster.sol";
import {
    ITornadoInstance
} from "../contracts/fee_adapters/tornadocash/interfaces/ITornadoInstance.sol";
import {
    TornadoFeeAdapter
} from "../contracts/fee_adapters/tornadocash/TornadoFeeAdapter.sol";
import {TornadoFixtures} from "./fixtures/TornadoFixtures.sol";

contract TornadoFeeAdapterForkTest is Test {
    ITornadoInstance internal tornado;
    TornadoFeeAdapter internal adapter;
    PrivacyPaymaster internal paymaster;
    address internal entryPointAddr;

    function setUp() public {
        vm.createSelectFork(
            vm.rpcUrl("sepolia"),
            TornadoFixtures.loadForkBlock()
        );

        entryPointAddr = Chains.readAddress("protocols.erc4337", "entry_point");
        address factory = Chains.readAddress("protocols.uniswap_v3", "factory");
        address weth = Chains.readAddress("tokens", "weth");
        uint32 twapPeriod = uint32(
            Chains.readUint("protocols.uniswap_v3", "twap_period")
        );

        tornado = ITornadoInstance(
            Chains.readAddress("protocols.tornado.eth_1", "instance")
        );
        adapter = new TornadoFeeAdapter(tornado);

        // Deploy the paymaster at the fixture relayer address so the proof's
        // committed relayer matches msg.sender when collectFee() is called.
        address paymasterAddr = TornadoFixtures.loadRelayer();
        deployCodeTo(
            "PrivacyPaymaster.sol:PrivacyPaymaster",
            abi.encode(
                IEntryPoint(entryPointAddr),
                IUniswapV3Factory(factory),
                weth,
                twapPeriod
            ),
            paymasterAddr
        );
        paymaster = PrivacyPaymaster(payable(paymasterAddr));
        paymaster.setApprovedAdapter(address(adapter), true);

        address depositor = address(0xDEADBEEF);
        vm.deal(depositor, tornado.denomination());
        vm.prank(depositor);
        tornado.deposit{value: tornado.denomination()}(
            TornadoFixtures.loadCommitment()
        );
    }

    // ----- Helpers -----

    function _buildUserOp(
        address payable relayer
    ) internal view returns (PackedUserOperation memory op) {
        bytes memory adapterData = abi.encode(
            TornadoFeeAdapter.AdapterData({
                proof: TornadoFixtures.loadProof(),
                root: TornadoFixtures.loadRoot(),
                nullifierHash: TornadoFixtures.loadNullifierHash(),
                recipient: TornadoFixtures.loadRecipient(),
                relayer: relayer,
                fee: TornadoFixtures.loadFee(),
                refund: uint256(0)
            })
        );
        bytes memory paymasterData = abi.encode(
            PaymasterLib.PaymasterData({
                adapter: address(adapter),
                adapterData: adapterData
            })
        );
        op.sender = address(0x5EDE2);
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
            TornadoFixtures.loadRelayer()
        );
        vm.prank(entryPointAddr);
        (bytes memory context, uint256 validationData) = paymaster
            .validatePaymasterUserOp(op, bytes32(0), TornadoFixtures.loadFee());

        PostOpContext memory ctx = abi.decode(context, (PostOpContext));
        assertEq(ctx.feeToken, address(0));
        assertEq(ctx.feePaid, TornadoFixtures.loadFee());
        assertEq(ctx.refundRecipient, TornadoFixtures.loadRecipient());
        assertEq(ctx.maxCost, TornadoFixtures.loadFee());
        assertEq(ctx.maxCostInToken, TornadoFixtures.loadFee());

        assertEq(validationData, 0);
    }

    function test_invalidRelayer() public {
        PackedUserOperation memory op = _buildUserOp(payable(address(0xDEAD)));
        vm.expectRevert(
            abi.encodeWithSelector(
                TornadoFeeAdapter.InvalidRelayer.selector,
                address(paymaster),
                address(0xDEAD)
            )
        );
        vm.prank(entryPointAddr);
        paymaster.validatePaymasterUserOp(
            op,
            bytes32(0),
            TornadoFixtures.loadFee()
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
        op.sender = address(0x5EDE2);
        op.paymasterAndData = abi.encodePacked(
            address(paymaster),
            uint128(500_000),
            uint128(50_000),
            paymasterData
        );
        vm.expectRevert(TornadoFeeAdapter.MalformedAdapterData.selector);
        vm.prank(entryPointAddr);
        paymaster.validatePaymasterUserOp(
            op,
            bytes32(0),
            TornadoFixtures.loadFee()
        );
    }

    function test_callGasLimitNotZero() public {
        PackedUserOperation memory op = _buildUserOp(
            TornadoFixtures.loadRelayer()
        );
        op.sender = address(0xDEAD);
        op.accountGasLimits = bytes32(uint256(1_000_000));
        vm.expectRevert(
            abi.encodeWithSelector(
                TornadoFeeAdapter.CallGasLimitNonZero.selector,
                1_000_000
            )
        );
        vm.prank(entryPointAddr);
        paymaster.validatePaymasterUserOp(
            op,
            bytes32(0),
            TornadoFixtures.loadFee()
        );
    }
}
