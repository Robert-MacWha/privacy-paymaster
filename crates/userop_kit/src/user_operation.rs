use alloy_primitives::{Address, B256, Bytes, U256};
use alloy_rpc_types::{Log, SignedAuthorization, TransactionReceipt};
use alloy_signer::{Signature, Signer};
use alloy_sol_types::{Eip712Domain, SolStruct};
use serde::{Deserialize, Serialize};

use crate::abis::entry_point::{PackedUserOperation, SignedUserOperation};

/// ERC-4337 0.7 & 0.8 UserOperation in unpacked JSON-RPC wire format.
#[derive(Debug, Clone, Serialize, Deserialize)]
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

    #[serde(with = "alloy_serde::quantity")]
    pub call_gas_limit: u128,

    #[serde(with = "alloy_serde::quantity")]
    pub verification_gas_limit: u128,

    pub pre_verification_gas: U256,

    #[serde(with = "alloy_serde::quantity")]
    pub max_fee_per_gas: u128,

    #[serde(with = "alloy_serde::quantity")]
    pub max_priority_fee_per_gas: u128,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub paymaster: Option<Address>,

    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        with = "alloy_serde::quantity::opt"
    )]
    pub paymaster_verification_gas_limit: Option<u128>,

    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        with = "alloy_serde::quantity::opt"
    )]
    pub paymaster_post_op_gas_limit: Option<u128>,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub paymaster_data: Option<Bytes>,

    pub signature: Bytes,

    #[serde(rename = "eip7702Auth", skip_serializing_if = "Option::is_none")]
    pub authorization: Option<SignedAuthorization>,
}

/// A submitted user operation hash.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(target_arch = "wasm32", derive(tsify::Tsify))]
#[cfg_attr(target_arch = "wasm32", tsify(into_wasm_abi, from_wasm_abi))]
pub struct UserOperationHash(pub B256);

/// Gas estimates returned by `eth_estimateUserOperationGas`.
///
/// EntryPoint 0.7 & 0.8
#[derive(Debug, Clone, Serialize, Deserialize)]
#[cfg_attr(target_arch = "wasm32", derive(tsify::Tsify))]
#[cfg_attr(target_arch = "wasm32", tsify(into_wasm_abi, from_wasm_abi))]
#[serde(rename_all = "camelCase")]
pub struct UserOperationGasEstimate {
    pub pre_verification_gas: U256,
    pub verification_gas_limit: U256,
    pub call_gas_limit: U256,
    #[serde(default)]
    pub paymaster_verification_gas_limit: Option<U256>,
    #[serde(default)]
    pub paymaster_post_op_gas_limit: Option<U256>,
}

/// Receipt returned by `eth_getUserOperationReceipt`.
///
/// EntryPoint 0.7 & 0.8
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
    pub logs: Vec<Log>,
    pub receipt: TransactionReceipt,
}

impl UserOperation {
    pub fn packed(&self) -> PackedUserOperation {
        self.clone().into()
    }
}

impl PackedUserOperation {
    pub fn hash(&self, domain: &Eip712Domain) -> B256 {
        self.eip712_signing_hash(domain)
    }

    pub async fn signed(
        &self,
        domain: &Eip712Domain,
        signer: &impl Signer,
    ) -> Result<SignedUserOperation, alloy_signer::Error> {
        let hash = self.hash(domain);
        let signature = signer.sign_hash(&hash).await?.as_bytes().into();

        Ok(SignedUserOperation {
            user_op: self.clone(),
            signature,
        })
    }
}

impl SignedUserOperation {
    pub fn signature(&self) -> Signature {
        Signature::try_from(self.signature.as_ref()).expect("Invalid signature")
    }
}

impl From<UserOperation> for PackedUserOperation {
    fn from(op: UserOperation) -> Self {
        let account_gas_limits = pack_gas(op.verification_gas_limit, op.call_gas_limit).into();
        let gas_fees = pack_gas(op.max_priority_fee_per_gas, op.max_fee_per_gas).into();
        let init_code = pack_init_code(op.factory, op.factory_data);
        let paymaster_and_data = pack_paymaster_and_data(
            op.paymaster,
            op.paymaster_verification_gas_limit,
            op.paymaster_post_op_gas_limit,
            op.paymaster_data,
        );

        PackedUserOperation {
            sender: op.sender,
            nonce: op.nonce,
            initCode: init_code,
            callData: op.call_data,
            accountGasLimits: account_gas_limits,
            preVerificationGas: op.pre_verification_gas,
            gasFees: gas_fees,
            paymasterAndData: paymaster_and_data,
        }
    }
}

fn pack_gas(a: u128, b: u128) -> U256 {
    let a = U256::from(a);
    let b = U256::from(b);
    (a << 128) | b
}

fn pack_init_code(factory: Option<Address>, factory_data: Option<Bytes>) -> Bytes {
    let (Some(factory), Some(factory_data)) = (factory, factory_data) else {
        return Bytes::new();
    };

    let mut init_code = Vec::new();
    init_code.extend_from_slice(factory.as_slice());
    init_code.extend_from_slice(&factory_data);
    init_code.into()
}

fn pack_paymaster_and_data(
    paymaster: Option<Address>,
    verification_gas_limit: Option<u128>,
    post_op_gas_limit: Option<u128>,
    paymaster_data: Option<Bytes>,
) -> Bytes {
    let (
        Some(paymaster),
        Some(verification_gas_limit),
        Some(post_op_gas_limit),
        Some(paymaster_data),
    ) = (
        paymaster,
        verification_gas_limit,
        post_op_gas_limit,
        paymaster_data,
    )
    else {
        return Bytes::new();
    };

    let mut data = Vec::new();
    data.extend_from_slice(paymaster.as_slice());
    data.extend_from_slice(&verification_gas_limit.to_be_bytes());
    data.extend_from_slice(&post_op_gas_limit.to_be_bytes());
    data.extend_from_slice(&paymaster_data);
    data.into()
}

#[cfg(test)]
mod tests {
    use alloy_primitives::{address, b256};
    use alloy_sol_types::eip712_domain;

    use super::*;

    #[test]
    fn test_pack() {
        let op = test_user_operation();

        let packed = op.packed();
        insta::assert_debug_snapshot!(packed);
    }

    #[test]
    fn test_hash() {
        let op = test_user_operation();
        let domain = test_domain();

        let hash = op.packed().hash(&domain);

        // If you change the above UserOperation struct, the hash will change.
        // You can check new hashes against the on-chain impl by running:
        // `cast call 0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108 "getUserOpHash((address,uint256,bytes,bytes,bytes32,uint256,bytes32,bytes,bytes))" "(...)" --rpc-url $RPC_URL`
        println!("UserOperation tuple: {}", op.packed());

        insta::assert_debug_snapshot!(hash);
    }

    #[tokio::test]
    async fn test_sign() {
        use alloy_signer_local::PrivateKeySigner;

        let op = test_user_operation();
        let domain = test_domain();
        let signer = PrivateKeySigner::from_bytes(&b256!(
            "0x00000000000000000000000000000000000000000000000000000000DEADBEEF"
        ))
        .unwrap();

        let signed = op.packed().signed(&domain, &signer).await.unwrap();
        let signature = signed.signature();
        insta::assert_debug_snapshot!(signature);

        let recovered = signature
            .recover_address_from_prehash(&op.packed().hash(&domain))
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
            nonce: U256::from(42),
            factory: Some(address!("0x000000000000000000000000000000000000BEEF")),
            factory_data: Some(Bytes::from_static(b"factory data")),
            call_data: Bytes::from_static(b"call data"),
            call_gas_limit: 100_000,
            verification_gas_limit: 50_000,
            pre_verification_gas: U256::from(10_000),
            max_fee_per_gas: 200,
            max_priority_fee_per_gas: 50,
            paymaster: Some(address!("0x000000000000000000000000000000000000FEED")),
            paymaster_verification_gas_limit: Some(20_000),
            paymaster_post_op_gas_limit: Some(30_000),
            paymaster_data: Some(Bytes::from_static(b"paymaster data")),
            signature: Bytes::from_static(b"signature"),
            authorization: None,
        }
    }

    fn test_domain() -> Eip712Domain {
        eip712_domain! {
            name: "ERC4337",
            version: "1",
            chain_id: 1,
            verifying_contract: address!("0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108"),
        }
    }
}
