// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {
    UserOperationLib
} from "@account-abstraction/contracts/core/UserOperationLib.sol";

library PaymasterLib {
    function decodePaymasterAndData(
        bytes calldata paymasterAndData
    ) internal pure returns (address adapter, bytes calldata adapterData) {
        uint256 paymasterAndDataOffset = UserOperationLib.PAYMASTER_DATA_OFFSET;

        adapter = address(
            bytes20(
                paymasterAndData[
                    paymasterAndDataOffset:paymasterAndDataOffset + 20
                ]
            )
        );
        adapterData = paymasterAndData[paymasterAndDataOffset + 20:];
    }
}
