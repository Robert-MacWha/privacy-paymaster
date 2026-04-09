// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {
    BasePaymaster
} from "@account-abstraction/contracts/core/BasePaymaster.sol";
import {
    PackedUserOperation
} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {
    IPaymaster
} from "@account-abstraction/contracts/interfaces/IPaymaster.sol";
import {
    IEntryPoint
} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPrivacyAccount} from "./accounts/IPrivacyAccount.sol";
import {IStaticOracle} from "./interfaces/IStaticOracle.sol";

/// Singleton multi-protocol privacy paymaster.
///
/// A single staked paymaster that sponsors unshields from multiple
/// privacy protocols via a whitelist of trusted per-protocol 4337
/// accounts. Each approved account is responsible for protocol-specific
/// validation (proof, recipient, nullifier, ...) and for reporting —
/// via `IPrivacyAccount.evaluateUserOperation` — what fee token it will
/// credit to the paymaster and how much.
///
/// The paymaster itself only enforces two things:
///   1. `userOp.sender` is in `approvedSenders`
///   2. `grossAmount >= maxCost + markup`, priced through the TWAP oracle
///      and gated by `feeTokenAllowed`.
contract PrivacyPaymaster is BasePaymaster {
    using SafeERC20 for IERC20;

    // ----- ERRORS -----
    error SenderNotApproved(address sender);
    error SenderMismatch(address expected, address actual);
    error FeeTokenNotAllowed(address feeToken);
    error InvalidSelector();
    error InsufficientGross(uint256 required, uint256 gross);
    error PaymasterAndDataTooShort();
    error OnlySelf();

    // ----- CONSTANTS -----

    /// Safety markup on top of worst-case gas cost at validation time.
    /// Covers oracle slippage, tail gas envelope, postOp overhead. 15%.
    uint16 public constant FEE_MARKUP_BPS = 1500;

    /// Gas units added on top of `actualGasCost` in postOp to reimburse
    /// the paymaster's own postOp work. Matches the legacy constant.
    uint256 public constant POST_OP_GAS_OVERHEAD = 1e5;

    /// Hard cap on gas forwarded to a native-ETH destination during
    /// settlement. Prevents hostile destinations from griefing.
    uint256 public constant FORWARD_GAS_BUDGET = 1e4;

    /// Offset where the user-controlled `paymasterAndData` tail begins
    /// (after the EntryPoint-mandated prefix:
    /// paymaster(20) || verificationGasLimit(16) || postOpGasLimit(16)).
    /// The tail is `abi.encode(address destination)` = 32 bytes.
    uint256 private constant HEADER_OFFSET = 20 + 16 + 16;

    // ----- IMMUTABLES -----
    IStaticOracle public immutable ORACLE;
    address public immutable WETH;
    uint32 public immutable TWAP_PERIOD;

    // ----- STATE -----
    mapping(address => bool) public approvedSenders;
    mapping(address => bool) public feeTokenAllowed;

    // ----- EVENTS -----
    event SenderApproved(address indexed sender, bool approved);
    event FeeTokenSet(address indexed token, bool allowed);

    // ----- CONSTRUCTOR -----
    constructor(
        IEntryPoint __entryPoint,
        address owner,
        IStaticOracle _oracle,
        address _weth,
        uint32 _twapPeriod
    ) BasePaymaster(__entryPoint, owner) {
        ORACLE = _oracle;
        WETH = _weth;
        TWAP_PERIOD = _twapPeriod;
        // Native ETH is always an allowed fee "token".
        feeTokenAllowed[address(0)] = true;
    }

    receive() external payable {}

    // ----- ADMIN -----
    // aderyn-ignore-next-line(centralization-risk)
    function setApprovedSender(
        address sender,
        bool approved
    ) external onlyOwner {
        approvedSenders[sender] = approved;
        emit SenderApproved(sender, approved);
    }

    // aderyn-ignore-next-line(centralization-risk)
    function setFeeToken(address token, bool allowed) external onlyOwner {
        if (allowed && token != address(0) && token != WETH) {
            require(ORACLE.isPairSupported(token, WETH), "pair not supported");
        }
        feeTokenAllowed[token] = allowed;
        emit FeeTokenSet(token, allowed);
    }

    // aderyn-ignore-next-line(centralization-risk)
    function sweep(address payable to) external onlyOwner {
        (bool ok, ) = to.call{value: address(this).balance}("");
        require(ok, "sweep failed");
    }

    // ----- BasePaymaster -----
    function _validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32,
        uint256 maxCost
    )
        internal
        virtual
        override
        returns (bytes memory context, uint256 validationData)
    {
        // Gate 1: sender must be an explicitly whitelisted PrivacyAccount.
        if (!approvedSenders[userOp.sender]) {
            revert SenderNotApproved(userOp.sender);
        }

        // Enforce uniform account shape.
        if (
            bytes4(userOp.callData[:4]) != IPrivacyAccount.execute.selector
        ) {
            revert InvalidSelector();
        }
        (bytes memory unshieldCalldata, ) = abi.decode(
            userOp.callData[4:],
            (bytes, IPrivacyAccount.Call[])
        );

        // Delegate protocol-specific validation + value extraction to
        // the account itself. It reverts on any malformed unshield.
        (
            address expectedSender,
            address feeToken,
            uint256 grossAmount
        ) = IPrivacyAccount(userOp.sender).evaluateUserOperation(
                unshieldCalldata,
                address(this)
            );

        //? Sanity: the account should only ever approve ops sent from
        //? itself. Cheap defense-in-depth against a buggy account.
        if (expectedSender != userOp.sender) {
            revert SenderMismatch(expectedSender, userOp.sender);
        }

        // Gate 2: fee token must be allowlisted.
        if (!feeTokenAllowed[feeToken]) {
            revert FeeTokenNotAllowed(feeToken);
        }

        // Economic check priced via the TWAP oracle + safety markup.
        uint256 weiBudget = (maxCost * (10_000 + FEE_MARKUP_BPS)) / 10_000;
        uint256 requiredInToken = (feeToken == address(0) || feeToken == WETH)
            ? weiBudget
            : _quoteWeiInToken(feeToken, weiBudget);
        if (grossAmount < requiredInToken) {
            revert InsufficientGross(requiredInToken, grossAmount);
        }

        address destination = _readDestination(userOp.paymasterAndData);

        context = abi.encode(feeToken, destination, grossAmount);
        validationData = 0;
    }

    function _postOp(
        IPaymaster.PostOpMode,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) internal override {
        (address feeToken, address destination, uint256 gross) = abi.decode(
            context,
            (address, address, uint256)
        );

        uint256 weiCost = actualGasCost +
            (POST_OP_GAS_OVERHEAD * actualUserOpFeePerGas);
        uint256 feeInToken = (feeToken == address(0) || feeToken == WETH)
            ? weiCost
            : _quoteWeiInToken(feeToken, weiCost);
        if (feeInToken > gross) feeInToken = gross; // safety cap

        uint256 remainder = gross - feeInToken;

        //? Best-effort forward. Reverting here would roll back the
        //? unshield inside the EntryPoint frame while the paymaster
        //? stays charged for gas — a grief vector. Hostile destinations
        //? cause the paymaster to silently absorb the remainder.
        if (feeToken == address(0)) {
            // aderyn-ignore-next-line(unchecked-low-level-call)
            (bool ok, ) = payable(destination).call{
                value: remainder,
                gas: FORWARD_GAS_BUDGET
            }("");
            ok; // swallow
        } else {
            // SafeERC20 reverts on failure; wrap in an external self-call
            // + try/catch so the no-revert-in-postOp invariant holds.
            try this.safeTransferSelf(feeToken, destination, remainder) {
                // ok
            } catch {
                // swallow — paymaster absorbs the remainder
            }
        }
    }

    /// Self-only reentry used by `_postOp` to run SafeERC20.safeTransfer
    /// inside a try/catch frame. `onlySelf` makes this unreachable to
    /// anyone but the paymaster itself.
    function safeTransferSelf(
        address token,
        address to,
        uint256 amount
    ) external {
        if (msg.sender != address(this)) revert OnlySelf();
        IERC20(token).safeTransfer(to, amount);
    }

    // ----- Internals -----
    function _quoteWeiInToken(
        address feeToken,
        uint256 weiAmount
    ) internal view returns (uint256 tokenAmount) {
        (tokenAmount, ) = ORACLE.quoteAllAvailablePoolsWithTimePeriod(
            uint128(weiAmount),
            WETH,
            feeToken,
            TWAP_PERIOD
        );
    }

    /// `paymasterAndData` tail is `abi.encode(address destination)`.
    /// Using abi.decode avoids the pitfall of manual byte offsets
    /// drifting if the layout changes.
    function _readDestination(
        bytes calldata paymasterAndData
    ) internal pure returns (address destination) {
        if (paymasterAndData.length < HEADER_OFFSET + 32) {
            revert PaymasterAndDataTooShort();
        }
        destination = abi.decode(
            paymasterAndData[HEADER_OFFSET:],
            (address)
        );
    }
}
