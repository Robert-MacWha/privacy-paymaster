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

import {PaymasterLib} from "./libraries/PaymasterLib.sol";
import {IFeeAdapter} from "./interfaces/IFeeAdapter.sol";

struct FeeToken {
    bool allowed;
    address pool;
}

/// Singleton multi-protocol privacy paymaster.
///
/// A single staked paymaster that can sponsor private transactions
/// interacting with multiple privacy protocols. Transactions are paid
/// for by the user's shielded funds, which are transferred to the paymaster's
/// control in the validation phase.
///
/// Protocol-specific logic is handled by adapter contracts that impl IFeeAdapter.
contract PrivacyPaymaster is BasePaymaster {
    using SafeERC20 for IERC20;

    // ----- ERRORS -----
    error AdapterNotApproved(address adapter);
    error FeeTokenNotAllowed(address feeToken);
    error InsufficientFee(uint256 required, uint256 fee);
    error OracleFailure(bytes reason);

    // ----- IMMUTABLES -----
    IUniswapV3Factory public immutable FACTORY;
    address public immutable WETH;

    // ----- STATE -----
    uint32 public twapPeriod;
    mapping(address => bool) public approvedAdapters;
    mapping(address => FeeToken) public feeTokens;

    // ----- EVENTS -----
    event AdapterApproved(address indexed adapter, bool approved);
    event FeeTokenSet(address indexed token, bool allowed);
    event TwapPeriodSet(uint32 twapPeriod);

    // ----- CONSTRUCTOR -----
    constructor(
        IEntryPoint _entryPoint,
        IUniswapV3Factory _factory,
        address _weth,
        uint32 _twapPeriod
    ) BasePaymaster(_entryPoint) {
        FACTORY = _factory;
        WETH = _weth;
        twapPeriod = _twapPeriod;

        // Native ETH is always allowed
        feeTokens[address(0)] = FeeToken({allowed: true, pool: address(0)});
        feeTokens[_weth] = FeeToken({allowed: true, pool: address(0)});
    }

    receive() external payable {}

    // ----- ADMIN -----
    function setApprovedAdapter(
        address adapter,
        bool approved
        // aderyn-ignore-next-line(centralization-risk)
    ) external onlyOwner {
        approvedAdapters[adapter] = approved;
        emit AdapterApproved(adapter, approved);
    }

    function setTwapPeriod(
        uint32 _twapPeriod
        // aderyn-ignore-next-line(centralization-risk)
    ) external onlyOwner {
        twapPeriod = _twapPeriod;
        emit TwapPeriodSet(_twapPeriod);
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
        PaymasterLib.PaymasterData memory data = PaymasterLib
            .decodePaymasterAndData(userOp.paymasterAndData);
        if (!approvedAdapters[data.adapter]) {
            revert AdapterNotApproved(data.adapter);
        }

        (address feeToken, uint256 feePaid) = IFeeAdapter(data.adapter)
            .collectFee(userOp);
        if (!feeTokens[feeToken].allowed) {
            revert FeeTokenNotAllowed(feeToken);
        }

        try this.quoteWeiInToken(feeToken, maxCost) returns (
            uint256 requiredInToken
        ) {
            if (feePaid < requiredInToken) {
                revert InsufficientFee(requiredInToken, feePaid);
            }
        } catch (bytes memory reason) {
            revert OracleFailure(reason);
        }
        context = "";
        validationData = 0;
    }

    function quoteWeiInToken(
        address feeToken,
        uint256 weiAmount
    ) public view returns (uint256 tokenAmount) {
        if (feeToken == WETH) return weiAmount;
        if (feeToken == address(0)) return weiAmount; // Native ETH

        uint128 weiAmount128 = uint128(weiAmount);

        address pool = feeTokens[feeToken].pool;
        (int24 meanTick, ) = OracleLibrary.consult(pool, twapPeriod);
        return
            OracleLibrary.getQuoteAtTick(
                meanTick,
                weiAmount128,
                WETH,
                feeToken
            );
    }
}
