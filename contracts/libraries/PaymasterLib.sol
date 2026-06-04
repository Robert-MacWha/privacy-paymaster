// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {
    UserOperationLib
} from "@account-abstraction/contracts/core/UserOperationLib.sol";

library PaymasterLib {
    struct PaymasterData {
        address adapter;
        bytes adapterData;
    }

    function decodePaymasterAndData(
        bytes calldata paymasterAndData
    ) internal pure returns (PaymasterData memory data) {
        uint256 paymasterAndDataOffset = UserOperationLib.PAYMASTER_DATA_OFFSET;

        data = abi.decode(
            paymasterAndData[paymasterAndDataOffset:],
            (PaymasterData)
        );
        return data;
    }
}
