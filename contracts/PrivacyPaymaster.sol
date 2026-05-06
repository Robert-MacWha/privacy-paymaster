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
import {
    EIP7702Utils
} from "@openzeppelin/contracts/account/utils/EIP7702Utils.sol";

import {IPrivacyAccount} from "./interfaces/IPrivacyAccount.sol";

struct FeeToken {
    bool allowed;
    address pool;
}

/// Singleton multi-protocol privacy paymaster.
///
/// A single staked paymaster that sponsors unshields from multiple
/// privacy protocols. The paymaster enforces the following control flow:
///   1. The paymaster is configured with a list of approved per-protocol
///      7702 delegate implementations (e.g., `TornadoDelegate`, `RailgunDelegate`)
///   2. Upon receiving a user operation, the paymaster checks that the sender's
///     delegate impl is approved, that the calldata selector is `IPrivacyAccount.execute`,
///     that the user's selected fee token is allowed, and that the quoted fee amount
///     is sufficient to cover the operation's max cost.
///
/// The paymaster relies on the per-protocol delegate implementations to estimate
/// each operation's fee amount. This allows the paymaster to be agnostic to
/// underlying privacy protocols.
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
    mapping(address => bool) public approvedImpls;
    mapping(address => FeeToken) public feeTokens;

    // ----- EVENTS -----
    event ImplApproved(address indexed impl, bool approved);
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
        feeTokens[_weth] = FeeToken({allowed: true, pool: address(0)});
    }

    receive() external payable {}

    // ----- ADMIN -----
    function setApprovedImpl(
        address impl,
        bool approved
        // aderyn-ignore-next-line(centralization-risk)
    ) external onlyOwner {
        approvedImpls[impl] = approved;
        emit ImplApproved(impl, approved);
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
        address senderImpl = EIP7702Utils.fetchDelegate(userOp.sender);
        if (!approvedImpls[senderImpl]) {
            revert SenderNotApproved(userOp.sender);
        }

        bytes memory feeCalldata = _decodeFeeCalldata(userOp.callData);

        (address feeToken, uint256 feeAmount) = IPrivacyAccount(userOp.sender)
            .previewFee(feeCalldata, userOp.paymasterAndData);
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
                WETH,
                feeToken
            );
    }

    function _decodeFeeCalldata(
        bytes calldata useropCalldata
    ) internal pure returns (bytes memory feeCalldata) {
        bool isValidSelector = bytes4(useropCalldata[:4]) ==
            IPrivacyAccount.execute.selector;
        if (!isValidSelector)
            revert InvalidSelector(bytes4(useropCalldata[:4]));

        (feeCalldata, ) = abi.decode(
            useropCalldata[4:],
            (bytes, IPrivacyAccount.Call[])
        );
    }
}
