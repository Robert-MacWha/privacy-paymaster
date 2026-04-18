// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {
    BasePaymaster
} from "@account-abstraction/contracts/core/BasePaymaster.sol";
import {
    PackedUserOperation
} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {
    IEntryPoint
} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    IUniswapV3Factory
} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {
    OracleLibrary
} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";

import {IPrivacyAccount} from "./interfaces/IPrivacyAccount.sol";

struct FeeToken {
    bool allowed;
    address pool;
}

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
    error FeeTokenNotAllowed(address feeToken);
    error InvalidSelector(bytes4 selector);
    error InsufficientFee(uint256 required, uint256 fee);

    // ----- IMMUTABLES -----
    IUniswapV3Factory public immutable FACTORY;
    address public immutable WETH;
    uint32 public immutable TWAP_PERIOD;

    // ----- STATE -----
    mapping(address => bool) public approvedSenders;
    mapping(address => FeeToken) public feeTokens;

    // ----- EVENTS -----
    event SenderApproved(address indexed sender, bool approved);
    event FeeTokenSet(address indexed token, bool allowed);

    // ----- CONSTRUCTOR -----
    constructor(
        IEntryPoint _entryPoint,
        IUniswapV3Factory _factory,
        address _weth,
        uint32 _twapPeriod
    ) BasePaymaster(_entryPoint) {
        FACTORY = _factory;
        WETH = _weth;
        TWAP_PERIOD = _twapPeriod;

        // Native ETH is always allowed
        feeTokens[address(0)] = FeeToken({allowed: true, pool: address(0)});
    }

    receive() external payable {}

    // ----- ADMIN -----
    function setApprovedSender(
        address sender,
        bool approved
        // aderyn-ignore-next-line(centralization-risk)
    ) external onlyOwner {
        approvedSenders[sender] = approved;
        emit SenderApproved(sender, approved);
    }

    function setFeeToken(
        address token,
        uint24 uniswapFee,
        bool allowed
        // aderyn-ignore-next-line(centralization-risk)
    ) external onlyOwner {
        address pool;
        if (allowed && token != address(0) && token != WETH) {
            pool = FACTORY.getPool(token, WETH, uniswapFee);
            require(pool != address(0), "pool not supported");
        }
        feeTokens[token] = FeeToken({allowed: allowed, pool: pool});
        emit FeeTokenSet(token, allowed);
    }

    // aderyn-ignore-next-line(centralization-risk)
    function sweep(address payable to) external onlyOwner {
        (bool ok, ) = to.call{value: address(this).balance}("");
        require(ok, "sweep failed");
    }

    // aderyn-ignore-next-line(centralization-risk)
    function sweepERC20(IERC20 token, address to) external onlyOwner {
        uint256 balance = token.balanceOf(address(this));
        token.safeTransfer(to, balance);
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
        if (!approvedSenders[userOp.sender]) {
            revert SenderNotApproved(userOp.sender);
        }

        bool isValidSelector = bytes4(userOp.callData[:4]) ==
            IPrivacyAccount.execute.selector;
        if (!isValidSelector)
            revert InvalidSelector(bytes4(userOp.callData[:4]));

        (bytes memory unshieldCalldata, ) = abi.decode(
            userOp.callData[4:],
            (bytes, IPrivacyAccount.Call[])
        );

        (address feeToken, uint256 feeAmount) = IPrivacyAccount(userOp.sender)
            .previewUnshield(unshieldCalldata);
        if (!feeTokens[feeToken].allowed) {
            revert FeeTokenNotAllowed(feeToken);
        }

        uint256 requiredInToken = _quoteWeiInToken(feeToken, maxCost);
        if (feeAmount < requiredInToken) {
            revert InsufficientFee(requiredInToken, feeAmount);
        }

        context = "";
        validationData = 0;
    }

    // ----- Internals -----
    function _quoteWeiInToken(
        address feeToken,
        uint256 weiAmount
    ) internal view returns (uint256 tokenAmount) {
        if (feeToken == WETH) return weiAmount;
        if (feeToken == address(0)) return weiAmount; // Native ETH

        uint128 weiAmount128 = uint128(weiAmount);

        address pool = feeTokens[feeToken].pool;
        (int24 meanTick, ) = OracleLibrary.consult(pool, TWAP_PERIOD);
        return
            OracleLibrary.getQuoteAtTick(
                meanTick,
                weiAmount128,
                feeToken,
                WETH
            );
    }
}
