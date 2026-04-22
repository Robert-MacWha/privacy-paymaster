use alloy_primitives::{Address, Bytes, U256, aliases::U192};
use alloy_provider::Provider;
use alloy_rpc_types::SignedAuthorization;

use crate::BundlerError;
use crate::BundlerProvider;
use crate::UserOperation;

pub struct UserOperationBuilder {
    sender: Address,
    calldata: Option<Bytes>,
    paymaster: Option<Address>,
    paymaster_data: Option<Bytes>,
    signature: Option<Bytes>,
    nonce_key: U192,
    gas: GasConfig,
    factory: Option<Address>,
    factory_data: Option<Bytes>,
    authorization: Option<SignedAuthorization>,
}

enum GasConfig {
    Auto,
    Manual {
        call_gas_limit: u128,
        verification_gas_limit: u128,
        pre_verification_gas: u128,
        max_fee_per_gas: u128,
        max_priority_fee_per_gas: u128,
        paymaster_verification_gas_limit: u128,
        paymaster_post_op_gas_limit: u128,
    },
}

impl UserOperationBuilder {
    pub fn new(sender: Address) -> Self {
        Self {
            sender,
            calldata: None,
            paymaster: None,
            paymaster_data: None,
            signature: None,
            nonce_key: U192::ZERO,
            gas: GasConfig::Auto,
            factory: None,
            factory_data: None,
            authorization: None,
        }
    }

    pub fn with_calldata(mut self, calldata: Bytes) -> Self {
        self.calldata = Some(calldata);
        self
    }

    pub fn with_paymaster(mut self, paymaster: Address) -> Self {
        self.paymaster = Some(paymaster);
        self
    }

    pub fn with_paymaster_data(mut self, data: Bytes) -> Self {
        self.paymaster_data = Some(data);
        self
    }

    pub fn with_signature(mut self, sig: Bytes) -> Self {
        self.signature = Some(sig);
        self
    }

    /// Set the nonce key for this operation.
    pub fn with_nonce_key(mut self, key: U192) -> Self {
        self.nonce_key = key;
        self
    }

    pub fn with_authorization(mut self, auth: SignedAuthorization) -> Self {
        self.authorization = Some(auth);
        self
    }

    pub fn with_gas(
        mut self,
        call_gas_limit: u128,
        verification_gas_limit: u128,
        pre_verification_gas: u128,
        max_fee_per_gas: u128,
        max_priority_fee_per_gas: u128,
        paymaster_verification_gas_limit: u128,
        paymaster_post_op_gas_limit: u128,
    ) -> Self {
        self.gas = GasConfig::Manual {
            call_gas_limit,
            verification_gas_limit,
            pre_verification_gas,
            max_fee_per_gas,
            max_priority_fee_per_gas,
            paymaster_verification_gas_limit,
            paymaster_post_op_gas_limit,
        };
        self
    }

    pub fn with_factory(mut self, factory: Address, data: Bytes) -> Self {
        self.factory = Some(factory);
        self.factory_data = Some(data);
        self
    }

    /// Build a complete `UserOperation` ready for submission.
    ///
    /// Fetches the nonce from the EntryPoint. When `GasConfig::Auto`,
    /// also estimates gas via the bundler and fetches fee market values from
    /// the eth node.
    pub async fn build<P: Provider>(
        &self,
        provider: &BundlerProvider<P>,
    ) -> Result<UserOperation, BundlerError> {
        let sender = self.sender;
        let calldata = self.calldata.clone().unwrap_or_default();
        let signature = self.signature.clone().unwrap_or_default();
        let nonce = provider.get_nonce(sender, self.nonce_key).await?;

        let mut skeleton = UserOperation {
            sender,
            nonce,
            factory: self.factory.clone(),
            factory_data: self.factory_data.clone(),
            call_data: calldata,
            call_gas_limit: 0,
            verification_gas_limit: 0,
            pre_verification_gas: 0,
            max_fee_per_gas: 0,
            max_priority_fee_per_gas: 0,
            paymaster: self.paymaster.clone(),
            paymaster_verification_gas_limit: Some(0),
            paymaster_post_op_gas_limit: Some(0),
            paymaster_data: self.paymaster_data.clone(),
            signature,
            authorization: self.authorization.clone(),
        };

        match self.gas {
            GasConfig::Auto => {
                let est = provider.estimate_gas(&skeleton).await?;
                let max_fee = provider.suggest_max_fee_per_gas().await?;
                let max_priority_fee = provider.suggest_max_priority_fee_per_gas().await?;

                skeleton.call_gas_limit = u256_to_u128(est.call_gas_limit);
                skeleton.verification_gas_limit = u256_to_u128(est.verification_gas_limit);
                skeleton.pre_verification_gas = u256_to_u128(est.pre_verification_gas);
                skeleton.max_fee_per_gas = max_fee;
                skeleton.max_priority_fee_per_gas = max_priority_fee;
                skeleton.paymaster_verification_gas_limit =
                    est.paymaster_verification_gas_limit.map(u256_to_u128);
                skeleton.paymaster_post_op_gas_limit =
                    est.paymaster_post_op_gas_limit.map(u256_to_u128);
            }
            GasConfig::Manual {
                call_gas_limit,
                verification_gas_limit,
                pre_verification_gas,
                max_fee_per_gas,
                max_priority_fee_per_gas,
                paymaster_verification_gas_limit,
                paymaster_post_op_gas_limit,
            } => {
                skeleton.call_gas_limit = call_gas_limit;
                skeleton.verification_gas_limit = verification_gas_limit;
                skeleton.pre_verification_gas = pre_verification_gas;
                skeleton.max_fee_per_gas = max_fee_per_gas;
                skeleton.max_priority_fee_per_gas = max_priority_fee_per_gas;
                skeleton.paymaster_verification_gas_limit = Some(paymaster_verification_gas_limit);
                skeleton.paymaster_post_op_gas_limit = Some(paymaster_post_op_gas_limit);
            }
        }

        Ok(skeleton)
    }
}

fn u256_to_u128(v: U256) -> u128 {
    v.saturating_to()
}
