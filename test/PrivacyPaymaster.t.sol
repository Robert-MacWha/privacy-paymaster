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
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {
    IUniswapV3Factory
} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

import {PrivacyPaymaster} from "../contracts/PrivacyPaymaster.sol";
import {IPrivacyAccount} from "../contracts/interfaces/IPrivacyAccount.sol";
import {BasePrivacyAccount} from "../contracts/accounts/BasePrivacyAccount.sol";

contract PrivacyPaymasterTest is Test {
    uint256 internal constant FORK_BLOCK = 10_100_000;

    address internal entryPointAddr;
    address internal weth;

    PrivacyPaymaster internal paymaster;
    MockFactory internal factory;

    // Sender for _validatePaymasterUserOp tests — etched with EIP-7702 delegation.
    address internal approvedImpl;
    address internal sender = address(0x5EDE2);

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("sepolia"), FORK_BLOCK);

        entryPointAddr = Chains.readAddress("protocols.erc4337", "entry_point");
        weth = Chains.readAddress("tokens", "weth");
        uint32 twapPeriod = uint32(
            Chains.readUint("protocols.uniswap_v3", "twap_period")
        );

        factory = new MockFactory();
        paymaster = new PrivacyPaymaster(
            IEntryPoint(entryPointAddr),
            IUniswapV3Factory(address(factory)),
            weth,
            twapPeriod
        );

        approvedImpl = address(
            new MockPrivacyAccount(IEntryPoint(entryPointAddr), address(0))
        );
        // Give sender EIP-7702 delegation code pointing to approvedImpl.
        vm.etch(sender, abi.encodePacked(bytes3(0xef0100), approvedImpl));
        paymaster.setApprovedImpl(approvedImpl, true);
    }

    // ----- Helpers -----

    function _buildUserOp(
        bytes memory feeCalldata
    ) internal view returns (PackedUserOperation memory op) {
        op.sender = sender;
        IPrivacyAccount.Call[] memory tail = new IPrivacyAccount.Call[](0);
        op.callData = abi.encodeCall(
            IPrivacyAccount.execute,
            (feeCalldata, tail)
        );
        op.paymasterAndData = abi.encodePacked(
            address(paymaster),
            uint128(100_000),
            uint128(50_000)
        );
    }

    function _mockPreviewFee(address token, uint256 amount) internal {
        vm.mockCall(
            sender,
            abi.encodeWithSelector(IPrivacyAccount.previewFee.selector),
            abi.encode(token, amount)
        );
    }

    function _validate(
        PackedUserOperation memory op,
        uint256 maxCost
    ) internal returns (bytes memory context, uint256 validationData) {
        vm.prank(entryPointAddr);
        return paymaster.validatePaymasterUserOp(op, bytes32(0), maxCost);
    }

    // ----- Constructor -----

    function test_constructor_defaultTokensAllowed() public view {
        (bool ethAllowed, ) = paymaster.feeTokens(address(0));
        (bool wethAllowed, ) = paymaster.feeTokens(weth);
        assertTrue(ethAllowed);
        assertTrue(wethAllowed);
    }

    // ----- setApprovedImpl -----

    function test_setApprovedImpl() public {
        address impl = address(0xABCD);
        vm.expectEmit(true, false, false, true);
        emit PrivacyPaymaster.ImplApproved(impl, true);
        paymaster.setApprovedImpl(impl, true);
        assertTrue(paymaster.approvedImpls(impl));
    }

    function test_setApprovedImpl_rejectsNonOwner() public {
        vm.prank(address(0xBAD));
        vm.expectRevert();
        paymaster.setApprovedImpl(address(0xABCD), true);
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

    function test_sweep_failedSend() public {
        vm.deal(address(paymaster), 1 ether);
        address payable to = payable(address(new ReceiveReverter()));
        vm.expectRevert("sweep failed");
        paymaster.sweep(to);
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

    function test_validate_senderNotApproved() public {
        PackedUserOperation memory op = _buildUserOp("");
        op.sender = address(0xDEAD);
        vm.prank(entryPointAddr);
        vm.expectRevert(
            abi.encodeWithSelector(
                PrivacyPaymaster.SenderNotApproved.selector,
                address(0xDEAD)
            )
        );
        paymaster.validatePaymasterUserOp(op, bytes32(0), 0);
    }

    function test_validate_invalidSelector() public {
        PackedUserOperation memory op = _buildUserOp("");
        op.callData = hex"deadbeef";
        vm.prank(entryPointAddr);
        vm.expectRevert(
            abi.encodeWithSelector(
                PrivacyPaymaster.InvalidSelector.selector,
                bytes4(0xdeadbeef)
            )
        );
        paymaster.validatePaymasterUserOp(op, bytes32(0), 0);
    }

    function test_validate_feeTokenNotAllowed() public {
        address badToken = address(0xBAD);
        _mockPreviewFee(badToken, 1 ether);
        vm.prank(entryPointAddr);
        vm.expectRevert(
            abi.encodeWithSelector(
                PrivacyPaymaster.FeeTokenNotAllowed.selector,
                badToken
            )
        );
        paymaster.validatePaymasterUserOp(_buildUserOp(""), bytes32(0), 0);
    }

    function test_validate_insufficientFee() public {
        _mockPreviewFee(address(0), 0);
        vm.prank(entryPointAddr);
        vm.expectRevert(
            abi.encodeWithSelector(
                PrivacyPaymaster.InsufficientFee.selector,
                1 ether,
                0
            )
        );
        paymaster.validatePaymasterUserOp(
            _buildUserOp(""),
            bytes32(0),
            1 ether
        );
    }

    function test_validate_success() public {
        _mockPreviewFee(address(0), 2 ether);
        (bytes memory context, uint256 validationData) = _validate(
            _buildUserOp(""),
            1 ether
        );
        assertEq(context, "");
        assertEq(validationData, 0);
    }
}

contract MockPrivacyAccount is BasePrivacyAccount {
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

contract ReceiveReverter {
    receive() external payable {
        revert();
    }
    function test() public {}
}
