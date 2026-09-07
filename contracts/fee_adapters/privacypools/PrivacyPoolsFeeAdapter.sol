// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {PackedUserOperation} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {UserOperationLib} from "@account-abstraction/contracts/core/UserOperationLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {PaymasterLib} from "../../libraries/PaymasterLib.sol";
import {IFeeAdapter} from "../../interfaces/IFeeAdapter.sol";
import {IPrivacyPool} from "./interfaces/IPrivacyPool.sol";

/// Fee adapter for 0xbow `privacy-pools-core` pools.
///
/// The adapter acts as the withdrawal's `processooor`: the pool pushes the
/// withdrawn value to this adapter, which then forwards a fixed fee to the
/// paymaster and the remainder to the recipient. The proof's `context`
/// signal binds the whole `withdrawal` struct (including our `FeeData`),
/// so only this adapter can spend the note — mirroring
/// `TornadoFeeAdapter`'s fixed-fee model.
contract PrivacyPoolsFeeAdapter is IFeeAdapter {
    using SafeERC20 for IERC20;

    struct AdapterData {
        IPrivacyPool.Withdrawal withdrawal;
        IPrivacyPool.WithdrawProof proof;
    }

    /// Encoded in `withdrawal.data`, bound by the proof's `context` signal.
    struct FeeData {
        address recipient;
        address feeRecipient;
        uint256 fee;
    }

    // ----- ERRORS -----
    error MalformedAdapterData();
    error MalformedFeeData();
    error ProcessooorNotAdapter(address expected, address actual);
    error InvalidFeeRecipient(address expected, address actual);
    error CallGasLimitNonZero(uint256 callGasLimit);
    error PrivacyPoolWithdrawalFailed(bytes reason);
    error FeeExceedsWithdrawal(uint256 fee, uint256 received);

    /// ----- IMMUTABLES -----
    IPrivacyPool public immutable POOL;
    /// The pool's asset, or the `NATIVE_ASSET` sentinel for native pools.
    address public immutable ASSET;

    /// Sentinel used by privacy-pools-core to represent the native asset.
    address constant NATIVE_ASSET = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    constructor(IPrivacyPool _pool) {
        POOL = _pool;
        ASSET = _pool.ASSET();
    }

    /// Native pools push ETH to this contract during `withdraw`.
    receive() external payable {}

    function collectFee(PackedUserOperation calldata userOp)
        external
        returns (address feeToken, uint256 feePaid, address refundRecipient)
    {
        address paymaster = msg.sender;

        AdapterData memory d;
        try this.decodeAdapterData(userOp.paymasterAndData) returns (AdapterData memory decoded) {
            d = decoded;
        } catch {
            revert MalformedAdapterData();
        }

        // Only this adapter can spend the note: the proof binds
        // `processooor` and the pool enforces `msg.sender == processooor`.
        if (d.withdrawal.processooor != address(this)) {
            revert ProcessooorNotAdapter(address(this), d.withdrawal.processooor);
        }

        FeeData memory feeData;
        try this.decodeFeeData(d.withdrawal.data) returns (FeeData memory decoded) {
            feeData = decoded;
        } catch {
            revert MalformedFeeData();
        }

        // The fee must be paid to the paymaster validating this user op,
        // guaranteeing the paymaster is made whole.
        if (feeData.feeRecipient != paymaster) {
            revert InvalidFeeRecipient(paymaster, feeData.feeRecipient);
        }

        // Anti-griefing: either the recipient is the userOp sender (secondary
        // actions allowed), or no calls are allowed in the execution phase.
        uint256 callGasLimit = UserOperationLib.unpackCallGasLimit(userOp);
        if (feeData.recipient != userOp.sender && callGasLimit != 0) {
            revert CallGasLimitNonZero(callGasLimit);
        }

        uint256 balanceBefore = _selfBalance(ASSET);
        try POOL.withdraw(d.withdrawal, d.proof) {}
        catch (bytes memory reason) {
            revert PrivacyPoolWithdrawalFailed(reason);
        }

        // The pool pushes `withdrawnValue` to the processooor; the balance
        // delta is the source of truth (robust to fee-on-transfer).
        uint256 received = _selfBalance(ASSET) - balanceBefore;
        if (feeData.fee > received) {
            revert FeeExceedsWithdrawal(feeData.fee, received);
        }

        _payout(ASSET, paymaster, feeData.fee);
        _payout(ASSET, feeData.recipient, received - feeData.fee);

        feeToken = _normalizeAsset(ASSET);
        feePaid = feeData.fee;
        refundRecipient = feeData.recipient;
        return (feeToken, feePaid, refundRecipient);
    }

    function decodeAdapterData(bytes calldata paymasterAndData) external pure returns (AdapterData memory) {
        PaymasterLib.PaymasterData memory pd = PaymasterLib.decodePaymasterAndData(paymasterAndData);
        return abi.decode(pd.adapterData, (AdapterData));
    }

    function decodeFeeData(bytes calldata data) external pure returns (FeeData memory) {
        return abi.decode(data, (FeeData));
    }

    function _isNative(address asset) internal pure returns (bool) {
        return asset == NATIVE_ASSET;
    }

    function _selfBalance(address asset) internal view returns (uint256) {
        if (_isNative(asset)) return address(this).balance;
        return IERC20(asset).balanceOf(address(this));
    }

    function _payout(address asset, address to, uint256 amount) internal {
        if (amount == 0) return;
        if (_isNative(asset)) {
            (bool ok,) = to.call{value: amount}("");
            require(ok, "native payout failed");
        } else {
            IERC20(asset).safeTransfer(to, amount);
        }
    }

    /// The paymaster quotes address(0) 1:1 against wei; native pools must
    /// report as ETH, not the `NATIVE_ASSET` sentinel.
    function _normalizeAsset(address asset) internal pure returns (address) {
        return _isNative(asset) ? address(0) : asset;
    }
}
