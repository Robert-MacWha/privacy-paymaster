// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Chains} from "../script/lib/Chains.sol";
import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {IStakeManager} from "@account-abstraction/contracts/interfaces/IStakeManager.sol";
import {ISenderCreator} from "@account-abstraction/contracts/interfaces/ISenderCreator.sol";
import {IPaymaster} from "@account-abstraction/contracts/interfaces/IPaymaster.sol";
import {PackedUserOperation} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {PaymasterLib} from "../contracts/libraries/PaymasterLib.sol";
import {PrivacyPaymaster, PostOpContext} from "../contracts/PrivacyPaymaster.sol";
import {IPrivacyPool} from "../contracts/fee_adapters/privacypools/interfaces/IPrivacyPool.sol";
import {PrivacyPoolsFeeAdapter} from "../contracts/fee_adapters/privacypools/PrivacyPoolsFeeAdapter.sol";

/// Mock of a privacy-pools-core pool. Pushes `pubSignals[2]` (the
/// withdrawn value) to the withdrawal's processooor, mimicking the real
/// pool's `_push`. No Groth16 verification is performed.
contract MockPrivacyPool is IPrivacyPool {
    using SafeERC20 for IERC20;

    address internal constant NATIVE_ASSET = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    error MockRevert();

    address internal _asset;
    bool internal shouldFail;

    event Pushed(address indexed to, uint256 amount);

    constructor(address _asset_) {
        _asset = _asset_;
    }

    function ASSET() external view override returns (address) {
        return _asset;
    }

    function SCOPE() external pure override returns (uint256) {
        return 0;
    }

    function setShouldFail(bool _shouldFail) external {
        shouldFail = _shouldFail;
    }

    function withdraw(IPrivacyPool.Withdrawal memory _withdrawal, IPrivacyPool.WithdrawProof memory _proof)
        external
        override
    {
        if (msg.sender != _withdrawal.processooor) revert MockRevert();
        if (shouldFail) revert MockRevert();

        uint256 value = _proof.pubSignals[2];
        if (_asset == NATIVE_ASSET) {
            (bool ok,) = payable(_withdrawal.processooor).call{value: value}("");
            require(ok);
        } else {
            IERC20(_asset).safeTransfer(_withdrawal.processooor, value);
        }
        emit Pushed(_withdrawal.processooor, value);
    }

    function test() public {}
}

contract MockERC20 is ERC20 {
    using SafeERC20 for IERC20;

    constructor() ERC20("Mock", "MCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function test() public {}
}

contract PrivacyPoolsFeeAdapterTest is Test {
    address internal constant NATIVE_ASSET = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address internal constant PAYMASTER = address(0x5AFE);
    address internal constant RECIPIENT = address(0x5A71CE2);
    address internal constant SENDER = address(0x5EDE2);

    MockPrivacyPool internal nativePool;
    PrivacyPoolsFeeAdapter internal nativeAdapter;

    MockPrivacyPool internal erc20Pool;
    MockERC20 internal token;
    PrivacyPoolsFeeAdapter internal erc20Adapter;

    function setUp() public {
        nativePool = new MockPrivacyPool(NATIVE_ASSET);
        nativeAdapter = new PrivacyPoolsFeeAdapter(IPrivacyPool(nativePool));

        token = new MockERC20();
        erc20Pool = new MockPrivacyPool(address(token));
        erc20Adapter = new PrivacyPoolsFeeAdapter(IPrivacyPool(erc20Pool));
    }

    // ----- Helpers -----

    function _buildUserOp(
        PrivacyPoolsFeeAdapter _adapter,
        address _processooor,
        address _recipient,
        address _feeRecipient,
        uint256 _fee,
        uint256 _withdrawnValue,
        uint256 _callGasLimit,
        bytes memory _feeDataOverride
    ) internal view returns (PackedUserOperation memory op) {
        bytes memory feeData = _feeDataOverride.length == 0
            ? abi.encode(
                PrivacyPoolsFeeAdapter.FeeData({recipient: _recipient, feeRecipient: _feeRecipient, fee: _fee})
            )
            : _feeDataOverride;

        IPrivacyPool.Withdrawal memory withdrawal = IPrivacyPool.Withdrawal({processooor: _processooor, data: feeData});
        IPrivacyPool.WithdrawProof memory proof;
        proof.pubSignals[2] = _withdrawnValue;

        bytes memory adapterData =
            abi.encode(PrivacyPoolsFeeAdapter.AdapterData({withdrawal: withdrawal, proof: proof}));
        bytes memory paymasterData =
            abi.encode(PaymasterLib.PaymasterData({adapter: address(_adapter), adapterData: adapterData}));

        op.sender = SENDER;
        op.accountGasLimits = bytes32(uint256(_callGasLimit));
        op.paymasterAndData = abi.encodePacked(PAYMASTER, uint128(500_000), uint128(50_000), paymasterData);
    }

    function _collectFee(PrivacyPoolsFeeAdapter _adapter, PackedUserOperation memory op)
        internal
        returns (address feeToken, uint256 feePaid, address refundRecipient)
    {
        vm.prank(PAYMASTER);
        return _adapter.collectFee(op);
    }

    // ----- collectFee: native pool -----

    function test_valid_native() public {
        vm.deal(address(nativePool), 1 ether);
        PackedUserOperation memory op =
            _buildUserOp(nativeAdapter, address(nativeAdapter), RECIPIENT, PAYMASTER, 0.1 ether, 1 ether, 0, "");

        (address feeToken, uint256 feePaid, address refundRecipient) = _collectFee(nativeAdapter, op);

        assertEq(feeToken, address(0));
        assertEq(feePaid, 0.1 ether);
        assertEq(refundRecipient, RECIPIENT);
        assertEq(PAYMASTER.balance, 0.1 ether);
        assertEq(RECIPIENT.balance, 0.9 ether);
        assertEq(address(nativeAdapter).balance, 0);
    }

    function test_valid_native_zeroFee() public {
        vm.deal(address(nativePool), 1 ether);
        PackedUserOperation memory op =
            _buildUserOp(nativeAdapter, address(nativeAdapter), RECIPIENT, PAYMASTER, 0, 1 ether, 0, "");

        (, uint256 feePaid, address refundRecipient) = _collectFee(nativeAdapter, op);

        assertEq(feePaid, 0);
        assertEq(refundRecipient, RECIPIENT);
        assertEq(RECIPIENT.balance, 1 ether);
        assertEq(PAYMASTER.balance, 0);
    }

    function test_valid_native_fullSweep() public {
        vm.deal(address(nativePool), 1 ether);
        PackedUserOperation memory op =
            _buildUserOp(nativeAdapter, address(nativeAdapter), address(0), PAYMASTER, 1 ether, 1 ether, 0, "");

        (, uint256 feePaid, address refundRecipient) = _collectFee(nativeAdapter, op);

        assertEq(feePaid, 1 ether);
        assertEq(refundRecipient, address(0));
        assertEq(PAYMASTER.balance, 1 ether);
        assertEq(address(nativeAdapter).balance, 0);
    }

    function test_valid_native_recipientIsSenderAllowsCallGasLimit() public {
        vm.deal(address(nativePool), 1 ether);
        PackedUserOperation memory op = _buildUserOp(
            nativeAdapter,
            address(nativeAdapter),
            SENDER,
            PAYMASTER,
            0.1 ether,
            1 ether,
            100, // non-zero callGasLimit is fine when recipient == sender
            ""
        );

        (, uint256 feePaid,) = _collectFee(nativeAdapter, op);
        assertEq(feePaid, 0.1 ether);
        assertEq(SENDER.balance, 0.9 ether);
    }

    // ----- collectFee: ERC20 pool -----

    function test_valid_erc20() public {
        token.mint(address(erc20Pool), 1000e18);
        PackedUserOperation memory op =
            _buildUserOp(erc20Adapter, address(erc20Adapter), RECIPIENT, PAYMASTER, 100e18, 1000e18, 0, "");

        (address feeToken, uint256 feePaid, address refundRecipient) = _collectFee(erc20Adapter, op);

        assertEq(feeToken, address(token));
        assertEq(feePaid, 100e18);
        assertEq(refundRecipient, RECIPIENT);
        assertEq(token.balanceOf(PAYMASTER), 100e18);
        assertEq(token.balanceOf(RECIPIENT), 900e18);
        assertEq(token.balanceOf(address(erc20Adapter)), 0);
    }

    // ----- Reverts -----

    function test_processooorNotAdapter() public {
        vm.deal(address(nativePool), 1 ether);
        PackedUserOperation memory op =
            _buildUserOp(nativeAdapter, address(0xDEAD), RECIPIENT, PAYMASTER, 0.1 ether, 1 ether, 0, "");

        vm.prank(PAYMASTER);
        vm.expectRevert(
            abi.encodeWithSelector(
                PrivacyPoolsFeeAdapter.ProcessooorNotAdapter.selector, address(nativeAdapter), address(0xDEAD)
            )
        );
        nativeAdapter.collectFee(op);
    }

    function test_invalidFeeRecipient() public {
        vm.deal(address(nativePool), 1 ether);
        PackedUserOperation memory op =
            _buildUserOp(nativeAdapter, address(nativeAdapter), RECIPIENT, address(0xDEAD), 0.1 ether, 1 ether, 0, "");

        vm.prank(PAYMASTER);
        vm.expectRevert(
            abi.encodeWithSelector(PrivacyPoolsFeeAdapter.InvalidFeeRecipient.selector, PAYMASTER, address(0xDEAD))
        );
        nativeAdapter.collectFee(op);
    }

    function test_malformedAdapterData() public {
        bytes memory paymasterData =
            abi.encode(PaymasterLib.PaymasterData({adapter: address(nativeAdapter), adapterData: hex"deadbeef"}));
        PackedUserOperation memory op;
        op.sender = SENDER;
        op.paymasterAndData = abi.encodePacked(PAYMASTER, uint128(500_000), uint128(50_000), paymasterData);

        vm.prank(PAYMASTER);
        vm.expectRevert(PrivacyPoolsFeeAdapter.MalformedAdapterData.selector);
        nativeAdapter.collectFee(op);
    }

    function test_malformedFeeData() public {
        PackedUserOperation memory op = _buildUserOp(
            nativeAdapter,
            address(nativeAdapter),
            RECIPIENT,
            PAYMASTER,
            0.1 ether,
            1 ether,
            0,
            hex"1234" // not a valid FeeData encoding
        );

        vm.prank(PAYMASTER);
        vm.expectRevert(PrivacyPoolsFeeAdapter.MalformedFeeData.selector);
        nativeAdapter.collectFee(op);
    }

    function test_callGasLimitNonZero() public {
        vm.deal(address(nativePool), 1 ether);
        PackedUserOperation memory op =
            _buildUserOp(nativeAdapter, address(nativeAdapter), RECIPIENT, PAYMASTER, 0.1 ether, 1 ether, 100, "");

        vm.prank(PAYMASTER);
        vm.expectRevert(abi.encodeWithSelector(PrivacyPoolsFeeAdapter.CallGasLimitNonZero.selector, uint256(100)));
        nativeAdapter.collectFee(op);
    }

    function test_feeExceedsWithdrawal() public {
        vm.deal(address(nativePool), 1 ether);
        PackedUserOperation memory op = _buildUserOp(
            nativeAdapter,
            address(nativeAdapter),
            RECIPIENT,
            PAYMASTER,
            0.5 ether,
            0.1 ether, // fee (0.5) > withdrawn value (0.1)
            0,
            ""
        );

        vm.prank(PAYMASTER);
        vm.expectRevert(
            abi.encodeWithSelector(PrivacyPoolsFeeAdapter.FeeExceedsWithdrawal.selector, 0.5 ether, 0.1 ether)
        );
        nativeAdapter.collectFee(op);
    }

    function test_withdrawalFails() public {
        vm.deal(address(nativePool), 1 ether);
        nativePool.setShouldFail(true);
        PackedUserOperation memory op =
            _buildUserOp(nativeAdapter, address(nativeAdapter), RECIPIENT, PAYMASTER, 0.1 ether, 1 ether, 0, "");

        vm.prank(PAYMASTER);
        vm.expectRevert(
            abi.encodeWithSelector(
                PrivacyPoolsFeeAdapter.PrivacyPoolWithdrawalFailed.selector,
                abi.encodeWithSelector(MockPrivacyPool.MockRevert.selector)
            )
        );
        nativeAdapter.collectFee(op);
    }

    // ----- Asset normalization -----

    function test_normalizeAsset_native() public view {
        assertEq(nativeAdapter.ASSET(), NATIVE_ASSET);
        // feeToken normalization is asserted in test_valid_native
        // (address(0) is returned, not the NATIVE_ASSET sentinel).
    }

    function test_normalizeAsset_erc20() public view {
        assertEq(erc20Adapter.ASSET(), address(token));
    }

    function test() public {}
}

contract MockFactory {
    mapping(bytes32 => address) internal _pools;

    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address) {
        return _pools[keccak256(abi.encode(tokenA, tokenB, fee))];
    }

    function test() public {}
}

/// Minimal IEntryPoint stub: BasePaymaster's constructor requires the entry
/// point to support the IEntryPoint interface. No entry-point logic is
/// executed in these tests (BasePaymaster v0.8 does not check msg.sender).
contract MockEntryPoint is IEntryPoint {
    function supportsInterface(bytes4 _id) external pure returns (bool) {
        return true;
    }

    function handleOps(PackedUserOperation[] calldata, address payable) external pure {
        revert();
    }

    function handleAggregatedOps(IEntryPoint.UserOpsPerAggregator[] calldata, address payable) external pure {
        revert();
    }

    function getUserOpHash(PackedUserOperation calldata) external pure returns (bytes32) {
        revert();
    }

    function getSenderAddress(bytes memory) external pure {
        revert();
    }

    function delegateAndRevert(address, bytes calldata) external pure {
        revert();
    }

    function senderCreator() external pure returns (ISenderCreator) {
        revert();
    }

    function getDepositInfo(address) external pure returns (IStakeManager.DepositInfo memory) {
        revert();
    }

    function balanceOf(address) external pure returns (uint256) {
        revert();
    }

    function depositTo(address) external payable {
        revert();
    }

    function addStake(uint32) external payable {
        revert();
    }

    function unlockStake() external pure {
        revert();
    }

    function withdrawStake(address payable) external pure {
        revert();
    }

    function withdrawTo(address payable, uint256) external pure {
        revert();
    }

    function getNonce(address, uint192) external pure returns (uint256) {
        revert();
    }

    function incrementNonce(uint192) external pure {
        revert();
    }

    function test() public {}
}

/// End-to-end flow through the real `PrivacyPaymaster` (no fork needed:
/// the native pool, factory and entry point are mocked, chain config is
/// read from toml).
contract PrivacyPoolsPaymasterFlowTest is Test {
    address internal constant NATIVE_ASSET = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address internal constant RECIPIENT = address(0x5A71CE2);
    address internal constant SENDER = address(0x5EDE2);

    MockPrivacyPool internal pool;
    PrivacyPoolsFeeAdapter internal adapter;
    PrivacyPaymaster internal paymaster;
    MockEntryPoint internal entryPoint;

    function setUp() public {
        entryPoint = new MockEntryPoint();
        address weth = Chains.readAddress("tokens", "weth");
        uint32 twapPeriod = uint32(Chains.readUint("protocols.uniswap_v3", "twap_period"));

        pool = new MockPrivacyPool(NATIVE_ASSET);
        adapter = new PrivacyPoolsFeeAdapter(IPrivacyPool(pool));

        paymaster = new PrivacyPaymaster(
            IEntryPoint(address(entryPoint)), IUniswapV3Factory(address(new MockFactory())), weth, twapPeriod
        );
        paymaster.setApprovedAdapter(address(adapter), true);
    }

    function _buildUserOp(uint256 _fee, uint256 _withdrawnValue) internal view returns (PackedUserOperation memory op) {
        bytes memory feeData = abi.encode(
            PrivacyPoolsFeeAdapter.FeeData({recipient: RECIPIENT, feeRecipient: address(paymaster), fee: _fee})
        );
        IPrivacyPool.Withdrawal memory withdrawal =
            IPrivacyPool.Withdrawal({processooor: address(adapter), data: feeData});
        IPrivacyPool.WithdrawProof memory proof;
        proof.pubSignals[2] = _withdrawnValue;

        bytes memory adapterData =
            abi.encode(PrivacyPoolsFeeAdapter.AdapterData({withdrawal: withdrawal, proof: proof}));
        bytes memory paymasterData =
            abi.encode(PaymasterLib.PaymasterData({adapter: address(adapter), adapterData: adapterData}));

        op.sender = SENDER;
        op.paymasterAndData = abi.encodePacked(address(paymaster), uint128(500_000), uint128(50_000), paymasterData);
    }

    function test_validatePaymasterUserOp_success() public {
        vm.deal(address(pool), 1 ether);
        PackedUserOperation memory op = _buildUserOp(0.1 ether, 1 ether);

        vm.prank(address(entryPoint));
        (bytes memory context, uint256 validationData) = paymaster.validatePaymasterUserOp(op, bytes32(0), 0.05 ether);

        PostOpContext memory ctx = abi.decode(context, (PostOpContext));
        assertEq(ctx.feeToken, address(0));
        assertEq(ctx.feePaid, 0.1 ether);
        assertEq(ctx.refundRecipient, RECIPIENT);
        assertEq(ctx.maxCost, 0.05 ether);
        assertEq(ctx.maxCostInToken, 0.05 ether);
        assertEq(validationData, 0);

        assertEq(address(paymaster).balance, 0.1 ether);
        assertEq(RECIPIENT.balance, 0.9 ether);
        assertEq(address(adapter).balance, 0);
    }

    function test_postOp_refundsExcess() public {
        vm.deal(address(pool), 1 ether);
        PackedUserOperation memory op = _buildUserOp(0.1 ether, 1 ether);

        vm.prank(address(entryPoint));
        (bytes memory context,) = paymaster.validatePaymasterUserOp(op, bytes32(0), 0.1 ether);

        vm.prank(address(entryPoint));
        paymaster.postOp(IPaymaster.PostOpMode.opSucceeded, context, 0.05 ether, 0);

        // Recipient nets the withdrawal minus the actual gas cost.
        assertEq(RECIPIENT.balance, 0.95 ether);
        assertEq(address(paymaster).balance, 0.05 ether);
    }

    function test_validatePaymasterUserOp_insufficientFee() public {
        vm.deal(address(pool), 1 ether);
        PackedUserOperation memory op = _buildUserOp(0.01 ether, 1 ether);

        vm.prank(address(entryPoint));
        vm.expectRevert(abi.encodeWithSelector(PrivacyPaymaster.InsufficientFee.selector, 0.1 ether, 0.01 ether));
        paymaster.validatePaymasterUserOp(op, bytes32(0), 0.1 ether);
    }

    function test() public {}
}
