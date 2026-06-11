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
    IPaymaster
} from "@account-abstraction/contracts/interfaces/IPaymaster.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {
    IUniswapV3Factory
} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

import {PaymasterLib} from "../contracts/libraries/PaymasterLib.sol";
import {PrivacyPaymaster} from "../contracts/PrivacyPaymaster.sol";
import {IFeeAdapter} from "../contracts/interfaces/IFeeAdapter.sol";

contract PrivacyPaymasterTest is Test {
    uint256 internal constant FORK_BLOCK = 10_100_000;

    address internal entryPointAddr;
    address internal weth;

    MockFactory internal factory;
    MockFeeAdapter internal adapter;
    PrivacyPaymaster internal paymaster;

    address internal sender = address(0x5EDE2);

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("sepolia"), FORK_BLOCK);

        entryPointAddr = Chains.readAddress("protocols.erc4337", "entry_point");
        weth = Chains.readAddress("tokens", "weth");
        uint32 twapPeriod = uint32(
            Chains.readUint("protocols.uniswap_v3", "twap_period")
        );

        factory = new MockFactory();
        adapter = new MockFeeAdapter();
        paymaster = new PrivacyPaymaster(
            IEntryPoint(entryPointAddr),
            IUniswapV3Factory(address(factory)),
            weth,
            twapPeriod
        );

        // Give sender EIP-7702 delegation code pointing to approvedAdapter.
        vm.etch(sender, abi.encodePacked(bytes3(0xef0100), address(adapter)));
        paymaster.setApprovedAdapter(address(adapter), true);
    }

    // ----- Helpers -----

    function _buildUserOp(
        address _adapter
    ) internal view returns (PackedUserOperation memory op) {
        bytes memory paymasterData = abi.encode(
            PaymasterLib.PaymasterData({adapter: _adapter, adapterData: ""})
        );

        op.sender = sender;
        op.paymasterAndData = abi.encodePacked(
            address(paymaster),
            uint128(100_000),
            uint128(50_000),
            paymasterData
        );
    }

    // ----- Constructor -----

    function test_constructor_defaultTokensAllowed() public view {
        (bool ethAllowed, ) = paymaster.feeTokens(address(0));
        (bool wethAllowed, ) = paymaster.feeTokens(weth);
        assertTrue(ethAllowed);
        assertTrue(wethAllowed);
    }

    // ----- setApprovedAdapter -----

    function test_setApprovedAdapter() public {
        vm.expectEmit(true, false, false, true);
        emit PrivacyPaymaster.AdapterApproved(address(0xABCD), true);
        paymaster.setApprovedAdapter(address(0xABCD), true);
        assertTrue(paymaster.approvedAdapters(address(0xABCD)));
    }

    function test_setApprovedAdapter_rejectsNonOwner() public {
        vm.prank(address(0xBAD));
        vm.expectRevert();
        paymaster.setApprovedAdapter(address(0xABCD), true);
    }

    // ----- setFeeToken -----

    function test_setFeeToken_erc20() public {
        address token = address(0x1234);
        address pool = address(0xBEEF1);
        factory.setPool(token, weth, 3000, pool);

        vm.expectEmit(true, false, false, true);
        emit PrivacyPaymaster.FeeTokenSet(token, true);
        paymaster.setFeeToken(token, 3000, true);

        (bool allowed, address returnedPool) = paymaster.feeTokens(token);
        assertTrue(allowed);
        assertEq(returnedPool, pool);
    }

    function test_setFeeToken_revertsIfPoolMissing() public {
        vm.expectRevert("pool not supported");
        paymaster.setFeeToken(address(0x1234), 3000, true);
    }

    function test_setFeeToken_disabledSkipsPoolLookup() public {
        paymaster.setFeeToken(address(0x1234), 3000, false);
        (bool allowed, ) = paymaster.feeTokens(address(0x1234));
        assertFalse(allowed);
    }

    function test_setFeeToken_rejectsNonOwner() public {
        vm.prank(address(0xBAD));
        vm.expectRevert();
        paymaster.setFeeToken(address(0), 0, false);
    }

    // ----- sweep -----

    function test_sweep() public {
        vm.deal(address(paymaster), 3 ether);
        address payable to = payable(address(0xBEEF));
        uint256 before = to.balance;
        paymaster.sweep(to);
        assertEq(address(paymaster).balance, 0);
        assertEq(to.balance - before, 3 ether);
    }

    function test_sweep_rejectsNonOwner() public {
        vm.prank(address(0xBAD));
        vm.expectRevert();
        paymaster.sweep(payable(address(0xBEEF)));
    }

    // ----- sweepERC20 -----

    function test_sweepERC20() public {
        MockERC20 token = new MockERC20();
        token.mint(address(paymaster), 5 ether);
        address to = address(0xBEEF);
        paymaster.sweepERC20(IERC20(address(token)), to);
        assertEq(token.balanceOf(to), 5 ether);
        assertEq(token.balanceOf(address(paymaster)), 0);
    }

    function test_sweepERC20_rejectsNonOwner() public {
        vm.prank(address(0xBAD));
        vm.expectRevert();
        paymaster.sweepERC20(IERC20(address(0)), address(0));
    }

    // ----- quoteWeiInToken -----

    function test_quoteWeiInToken_eth() public view {
        assertEq(paymaster.quoteWeiInToken(address(0), 1 ether), 1 ether);
    }

    function test_quoteWeiInToken_weth() public view {
        assertEq(paymaster.quoteWeiInToken(weth, 1 ether), 1 ether);
    }

    // ----- _validatePaymasterUserOp -----

    function test_validate_adapterNotApproved() public {
        PackedUserOperation memory op = _buildUserOp(address(0xDEAD));
        vm.prank(entryPointAddr);
        vm.expectRevert(
            abi.encodeWithSelector(
                PrivacyPaymaster.AdapterNotApproved.selector,
                address(0xDEAD)
            )
        );
        paymaster.validatePaymasterUserOp(op, bytes32(0), 0);
    }

    function test_validate_feeTokenNotAllowed() public {
        PackedUserOperation memory op = _buildUserOp(address(adapter));
        adapter.setFeeToken(address(0xBAAD));
        vm.prank(entryPointAddr);
        vm.expectRevert(
            abi.encodeWithSelector(
                PrivacyPaymaster.FeeTokenNotAllowed.selector,
                address(0xBAAD)
            )
        );
        paymaster.validatePaymasterUserOp(op, bytes32(0), 0);
    }

    function test_validate_insufficientFee() public {
        PackedUserOperation memory op = _buildUserOp(address(adapter));
        adapter.setFeeAmount(0 ether);
        vm.prank(entryPointAddr);
        vm.expectRevert(
            abi.encodeWithSelector(
                PrivacyPaymaster.InsufficientFee.selector,
                1 ether,
                0
            )
        );
        paymaster.validatePaymasterUserOp(op, bytes32(0), 1 ether);
    }

    function test_validate_success() public {
        PackedUserOperation memory op = _buildUserOp(address(adapter));
        vm.prank(entryPointAddr);
        (bytes memory context, uint256 validationData) = paymaster
            .validatePaymasterUserOp(op, bytes32(0), 0);
        assertEq(context, "");
        assertEq(validationData, 0);
    }

    function test_validate_malformedPaymasterData() public {
        PackedUserOperation memory op;
        op.sender = sender;
        op.paymasterAndData = abi.encodePacked(
            address(paymaster),
            uint128(100_000),
            uint128(50_000),
            bytes32(uint256(0xdead))
        );
        vm.prank(entryPointAddr);
        vm.expectRevert(PrivacyPaymaster.MalformedPaymasterData.selector);
        paymaster.validatePaymasterUserOp(op, bytes32(0), 0);
    }

    // ----- _postOp refund -----

    address internal recipient = address(0xECE1);

    function _validateForContext(
        uint256 maxCost
    ) internal returns (bytes memory ctx) {
        PackedUserOperation memory op = _buildUserOp(address(adapter));
        vm.prank(entryPointAddr);
        (ctx, ) = paymaster.validatePaymasterUserOp(op, bytes32(0), maxCost);
    }

    function test_validate_returnsContextWhenRefundRecipientSet() public {
        adapter.setRefundRecipient(recipient);
        bytes memory ctx = _validateForContext(0.5 ether);
        assertGt(ctx.length, 0);
    }

    function test_postOp_refundsExcessEth() public {
        adapter.setRefundRecipient(recipient);
        vm.deal(address(paymaster), 1 ether);
        bytes memory ctx = _validateForContext(0.5 ether);

        vm.prank(entryPointAddr);
        paymaster.postOp(IPaymaster.PostOpMode.opSucceeded, ctx, 0.2 ether, 0);

        assertEq(recipient.balance, 0.8 ether);
        assertEq(address(paymaster).balance, 0.2 ether);
    }

    function test_postOp_refundsExcessWeth() public {
        adapter.setFeeToken(weth);
        adapter.setRefundRecipient(recipient);
        deal(weth, address(paymaster), 1 ether);
        bytes memory ctx = _validateForContext(0.5 ether);

        vm.prank(entryPointAddr);
        paymaster.postOp(IPaymaster.PostOpMode.opSucceeded, ctx, 0.2 ether, 0);

        assertEq(IERC20(weth).balanceOf(recipient), 0.8 ether);
        assertEq(IERC20(weth).balanceOf(address(paymaster)), 0.2 ether);
    }

    function test_postOp_noRefundWhenCostEqualsFee() public {
        adapter.setRefundRecipient(recipient);
        vm.deal(address(paymaster), 1 ether);
        bytes memory ctx = _validateForContext(1 ether);

        vm.prank(entryPointAddr);
        paymaster.postOp(IPaymaster.PostOpMode.opSucceeded, ctx, 1 ether, 0);

        assertEq(recipient.balance, 0);
        assertEq(address(paymaster).balance, 1 ether);
    }

    function test_postOp_emptyContextNoop() public {
        vm.deal(address(paymaster), 1 ether);
        vm.prank(entryPointAddr);
        paymaster.postOp(IPaymaster.PostOpMode.opSucceeded, "", 1 ether, 0);
        assertEq(address(paymaster).balance, 1 ether);
    }

    function test_postOp_refundFailureEmitsEvent() public {
        RejectEther rejecter = new RejectEther();
        adapter.setRefundRecipient(address(rejecter));
        vm.deal(address(paymaster), 1 ether);
        bytes memory ctx = _validateForContext(0.5 ether);

        vm.expectEmit(true, true, false, true);
        emit PrivacyPaymaster.RefundFailed(
            address(rejecter),
            address(0),
            0.8 ether
        );

        vm.prank(entryPointAddr);
        paymaster.postOp(IPaymaster.PostOpMode.opSucceeded, ctx, 0.2 ether, 0);

        assertEq(address(rejecter).balance, 0);
        assertEq(address(paymaster).balance, 1 ether);
    }
}

contract MockFeeAdapter is IFeeAdapter {
    address feeToken = address(0);
    uint256 feeAmount = 1 ether;
    address refundRecipient = address(0);

    function setFeeToken(address _token) external {
        feeToken = _token;
    }

    function setFeeAmount(uint256 _amount) external {
        feeAmount = _amount;
    }

    function setRefundRecipient(address _r) external {
        refundRecipient = _r;
    }

    function collectFee(
        PackedUserOperation calldata
    )
        external
        view
        returns (address _feeToken, uint256 _feePaid, address _refundRecipient)
    {
        _feeToken = feeToken;
        _feePaid = feeAmount;
        _refundRecipient = refundRecipient;
    }
    function test() public {}
}

contract MockFactory {
    mapping(bytes32 => address) private _pools;

    function setPool(
        address tokenA,
        address tokenB,
        uint24 fee,
        address pool
    ) external {
        _pools[keccak256(abi.encode(tokenA, tokenB, fee))] = pool;
    }

    function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external view returns (address) {
        return _pools[keccak256(abi.encode(tokenA, tokenB, fee))];
    }
    function test() public {}
}

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock", "MCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    function test() public {}
}

contract RejectEther {
    receive() external payable {
        revert("no");
    }
    function test() public {}
}
