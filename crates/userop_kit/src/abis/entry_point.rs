use std::fmt::{Display, Formatter};

use alloy::{
    primitives::{B256, Bytes},
    sol,
};
use serde::{Deserialize, Serialize};

sol! {
    contract EntryPoint {
        function getNonce(address sender, uint192 key) external view returns (uint256 nonce);
    }

    #[derive(Debug, Serialize, Deserialize)]
    struct PackedUserOperation {
        address sender;
        uint256 nonce;
        bytes initCode;
        bytes callData;
        bytes32 accountGasLimits;
        uint256 preVerificationGas;
        bytes32 gasFees;
        bytes paymasterAndData;
    }
}

#[derive(Serialize, Deserialize)]
pub struct SignedUserOperation {
    #[serde(flatten)]
    pub user_op: PackedUserOperation,
    pub signature: Bytes,
}

impl Display for PackedUserOperation {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "({},{},{},{},{},{},{},{},{})",
            self.sender,
            self.nonce,
            self.initCode,
            self.callData,
            self.accountGasLimits,
            self.preVerificationGas,
            self.gasFees,
            self.paymasterAndData,
            B256::ZERO, // Placeholder for signature in the EIP-712 hash
        )
    }
}
