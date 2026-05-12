use alloy::{
    eips::eip7702::Authorization,
    primitives::{Address, B256, Bytes, U256},
    rpc::types::{Log, ReceiptWithBloom, TransactionReceipt},
    signers::Signer,
    sol_types::{Eip712Domain, SolStruct},
};
use serde::{Deserialize, Serialize};

use crate::{abis::entry_point::PackedUserOperation, signed_user_operation::SignedUserOperation};

/// ERC-4337 0.7 & 0.8 UserOperation in unpacked JSON-RPC wire format.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[cfg_attr(target_arch = "wasm32", derive(tsify::Tsify))]
#[cfg_attr(target_arch = "wasm32", tsify(into_wasm_abi, from_wasm_abi))]
#[serde(rename_all = "camelCase")]
pub struct UserOperation {
    pub sender: Address,
    pub nonce: U256,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub factory: Option<Address>,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub factory_data: Option<Bytes>,
    pub call_data: Bytes,

    #[serde(with = "alloy::serde::quantity")]
    pub call_gas_limit: u128,

    #[serde(with = "alloy::serde::quantity")]
    pub verification_gas_limit: u128,

    #[serde(with = "alloy::serde::quantity")]
    pub pre_verification_gas: u128,

    #[serde(with = "alloy::serde::quantity")]
    pub max_fee_per_gas: u128,

    #[serde(with = "alloy::serde::quantity")]
    pub max_priority_fee_per_gas: u128,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub paymaster: Option<Address>,

    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        with = "alloy::serde::quantity::opt"
    )]
    pub paymaster_verification_gas_limit: Option<u128>,

    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        with = "alloy::serde::quantity::opt"
    )]
    pub paymaster_post_op_gas_limit: Option<u128>,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub paymaster_data: Option<Bytes>,

    #[serde(rename = "eip7702Auth", skip_serializing_if = "Option::is_none")]
    pub authorization: Option<Authorization>,

    pub signature: Bytes,
}

/// A submitted user operation hash.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(target_arch = "wasm32", derive(tsify::Tsify))]
#[cfg_attr(target_arch = "wasm32", tsify(into_wasm_abi, from_wasm_abi))]
pub struct UserOperationHash(pub B256);

/// Gas estimates returned by `eth_estimateUserOperationGas`.
///
/// EntryPoint 0.7 & 0.8
#[derive(Debug, Copy, Clone, Serialize, Deserialize)]
#[cfg_attr(target_arch = "wasm32", derive(tsify::Tsify))]
#[cfg_attr(target_arch = "wasm32", tsify(into_wasm_abi, from_wasm_abi))]
#[serde(rename_all = "camelCase")]
pub struct UserOperationGasEstimate {
    #[serde(with = "alloy::serde::quantity")]
    pub pre_verification_gas: u128,
    #[serde(with = "alloy::serde::quantity")]
    pub verification_gas_limit: u128,
    #[serde(with = "alloy::serde::quantity")]
    pub call_gas_limit: u128,
    #[serde(default, with = "alloy::serde::quantity::opt")]
    pub paymaster_verification_gas_limit: Option<u128>,
    #[serde(default, with = "alloy::serde::quantity::opt")]
    pub paymaster_post_op_gas_limit: Option<u128>,
}

/// Receipt returned by `eth_getUserOperationReceipt`.
///
/// EntryPoint 0.7 & 0.8
///
/// TODO: Add logs and receipt fields
#[derive(Debug, Clone, Serialize, Deserialize)]
#[cfg_attr(target_arch = "wasm32", derive(tsify::Tsify))]
#[cfg_attr(target_arch = "wasm32", tsify(into_wasm_abi, from_wasm_abi))]
#[serde(rename_all = "camelCase")]
pub struct UserOperationReceipt {
    pub entry_point: Address,
    pub user_op_hash: B256,
    pub sender: Address,
    pub nonce: U256,
    pub actual_gas_used: U256,
    pub actual_gas_cost: U256,
    pub success: bool,
    pub reason: Option<Bytes>,
    pub logs: Vec<Log>,
    pub receipt: TransactionReceipt<ReceiptWithBloom>,
}

impl UserOperation {
    /// Returns the total gas estimate, including paymaster gas if applicable.
    pub fn total_gas_limit(&self) -> u128 {
        let mut total =
            self.pre_verification_gas + self.verification_gas_limit + self.call_gas_limit;
        if let Some(paymaster_verification_gas_limit) = self.paymaster_verification_gas_limit {
            total += paymaster_verification_gas_limit;
        }
        if let Some(paymaster_post_op_gas_limit) = self.paymaster_post_op_gas_limit {
            total += paymaster_post_op_gas_limit;
        }
        total
    }

    pub async fn signed(
        &self,
        signer: &impl Signer,
        domain: &Eip712Domain,
    ) -> Result<SignedUserOperation, alloy::signers::Error> {
        let packed = PackedUserOperation::from(self);
        let domain_hash = packed.eip712_signing_hash(domain);
        let userop_sig = signer.sign_hash(&domain_hash).await?.as_bytes().into();

        let authorization = if let Some(auth) = self.authorization.clone() {
            let authorization_hash = auth.signature_hash();
            let authorization_sig = signer.sign_hash(&authorization_hash).await?;
            Some(auth.into_signed(authorization_sig))
        } else {
            None
        };

        Ok(SignedUserOperation {
            user_op: self.clone(),
            signature: userop_sig,
            authorization,
        })
    }
}

#[cfg(test)]
mod tests {
    use alloy::{
        primitives::{address, b256},
        signers::local::PrivateKeySigner,
        sol_types::SolStruct,
    };

    use crate::entry_point::ENTRY_POINT_08_DOMAIN;

    use super::*;

    #[test]
    fn test_pack() {
        let op = test_user_operation();

        let packed = PackedUserOperation::from(&op);
        insta::assert_debug_snapshot!(packed);
    }

    #[test]
    fn test_hash() {
        let op = test_user_operation();

        let packed = PackedUserOperation::from(&op);
        let hash = packed.eip712_hash_struct();

        // If you change the above UserOperation struct, the hash will change.
        // You can check new hashes against the on-chain impl by running:
        // `cast call 0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108 "getUserOpHash((address,uint256,bytes,bytes,bytes32,uint256,bytes32,bytes,bytes))" "(...)" --rpc-url $RPC_URL`
        println!("UserOperation tuple: {:?}", packed);

        insta::assert_debug_snapshot!(hash);
    }

    #[tokio::test]
    async fn test_sign() {
        let op = test_user_operation();
        let domain = ENTRY_POINT_08_DOMAIN;
        let signer = PrivateKeySigner::from_bytes(&b256!(
            "0x00000000000000000000000000000000000000000000000000000000DEADBEEF"
        ))
        .unwrap();

        let packed = PackedUserOperation::from(&op);
        let signed = op.signed(&signer, &domain).await.unwrap();
        let signature = signed.signature();
        insta::assert_debug_snapshot!(signature);

        let recovered = signature
            .recover_address_from_prehash(&packed.eip712_signing_hash(&domain))
            .unwrap();
        assert_eq!(
            recovered,
            signer.address(),
            "Recovered address does not match signer address"
        );
    }

    fn test_user_operation() -> UserOperation {
        UserOperation {
            sender: address!("0x000000000000000000000000000000000000DEAD"),
            signature: Bytes::new(),
            nonce: U256::from(42),
            factory: Some(address!("0x000000000000000000000000000000000000BEEF")),
            factory_data: Some(Bytes::from_static(b"factory data")),
            call_data: Bytes::from_static(b"call data"),
            call_gas_limit: 100_000,
            verification_gas_limit: 50_000,
            pre_verification_gas: 10_000,
            max_fee_per_gas: 200,
            max_priority_fee_per_gas: 50,
            paymaster: Some(address!("0x000000000000000000000000000000000000FEED")),
            paymaster_verification_gas_limit: Some(20_000),
            paymaster_post_op_gas_limit: Some(30_000),
            paymaster_data: Some(Bytes::from_static(b"paymaster data")),
            authorization: None,
        }
    }
}
