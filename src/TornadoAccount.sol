pragma solidity ^0.8.28;

import {IAccount} from "@account-abstraction/contracts/interfaces/IAccount.sol";
import {
    PackedUserOperation
} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {ITornadoInstance} from "./interfaces/ITornadoInstance.sol";

contract TornadoAccount is IAccount {
    // ----- CONSTANTS -----
    ITornadoInstance public immutable TORNADO_INSTANCE;

    // ----- CONSTRUCTOR -----
    constructor(ITornadoInstance _tornadoInstance) {
        TORNADO_INSTANCE = _tornadoInstance;
    }

    // ----- IAccount -----
    function validateUserOp(
        PackedUserOperation calldata,
        bytes32,
        uint256
    ) external virtual override returns (uint256 validationData) {
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
        return;
    }
}
