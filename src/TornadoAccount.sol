// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IAccount} from "@account-abstraction/contracts/interfaces/IAccount.sol";
import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {
    PackedUserOperation
} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {ITornadoInstance} from "./interfaces/ITornadoInstance.sol";

contract TornadoAccount is IAccount {
    // ----- ERRORS -----
    error CallerNotEntryPoint();

    // ----- CONSTANTS -----
    IEntryPoint public immutable ENTRY_POINT;
    ITornadoInstance public immutable TORNADO_INSTANCE;

    // ----- CONSTRUCTOR -----
    constructor(IEntryPoint _entryPoint, ITornadoInstance _tornadoInstance) {
        ENTRY_POINT = _entryPoint;
        TORNADO_INSTANCE = _tornadoInstance;
    }

    // ----- IAccount -----
    function validateUserOp(
        PackedUserOperation calldata,
        bytes32,
        uint256
    ) external virtual override returns (uint256 validationData) {
        if (msg.sender != address(ENTRY_POINT)) revert CallerNotEntryPoint();
        validationData = 0;
    }

    function withdraw(
        bytes calldata proof,
        bytes32 root,
        bytes32 nullifierHash,
        address payable recipient,
        uint256 refund
    ) external {
        TORNADO_INSTANCE.withdraw(
            proof,
            root,
            nullifierHash,
            recipient,
            payable(address(0)), // relayer
            uint256(0), // fee
            refund
        );
    }
}
