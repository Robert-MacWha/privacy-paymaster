use alloy_primitives::{Address, Bytes, U256, aliases::U192};
use alloy_rpc_types::SignedAuthorization;

use crate::BundlerError;
use crate::BundlerProvider;
use crate::UserOperation;

pub struct UserOperationBuilder<P = ()> {
    pub op: UserOperation,
    pub protocol: P,

    nonce_key: Option<U192>,
    gas_set: bool,
}

impl<P> UserOperationBuilder<P> {
    pub fn new_with(sender: Address, protocol: P) -> Self {
        Self {
            op: UserOperation {
                sender,
                nonce: U256::ZERO,
                factory: None,
                factory_data: None,
                call_data: Bytes::new(),
                call_gas_limit: 0,
                verification_gas_limit: 0,
                pre_verification_gas: 0,
                max_fee_per_gas: 0,
                max_priority_fee_per_gas: 0,
                paymaster: None,
                paymaster_verification_gas_limit: None,
                paymaster_post_op_gas_limit: None,
                paymaster_data: None,
                signature: Bytes::new(),
                authorization: None,
            },
            protocol,
            nonce_key: None,
            gas_set: false,
        }
    }

    pub fn with_calldata(mut self, calldata: Bytes) -> Self {
        self.op.call_data = calldata;
        self
    }

    pub fn with_paymaster(mut self, paymaster: Address) -> Self {
        self.op.paymaster = Some(paymaster);
        self
    }

    pub fn with_paymaster_data(mut self, data: Bytes) -> Self {
        self.op.paymaster_data = Some(data);
        self
    }

    pub fn with_signature(mut self, sig: Bytes) -> Self {
        self.op.signature = sig;
        self
    }

    /// Set the nonce key for this operation.
    pub fn with_nonce_key(mut self, nonce_key: U192) -> Self {
        self.nonce_key = Some(nonce_key);
        self
    }

    pub fn with_authorization(mut self, auth: SignedAuthorization) -> Self {
        self.op.authorization = Some(auth);
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
        self.gas_set = true;

        self.op.call_gas_limit = call_gas_limit;
        self.op.verification_gas_limit = verification_gas_limit;
        self.op.pre_verification_gas = pre_verification_gas;
        self.op.max_fee_per_gas = max_fee_per_gas;
        self.op.max_priority_fee_per_gas = max_priority_fee_per_gas;
        self.op.paymaster_verification_gas_limit = Some(paymaster_verification_gas_limit);
        self.op.paymaster_post_op_gas_limit = Some(paymaster_post_op_gas_limit);
        self
    }

    pub fn with_factory(mut self, factory: Address, data: Bytes) -> Self {
        self.op.factory = Some(factory);
        self.op.factory_data = Some(data);
        self
    }

    /// Build a complete `UserOperation` ready for submission.
    pub async fn build(
        mut self,
        provider: &BundlerProvider,
    ) -> Result<UserOperation, BundlerError> {
        if let Some(nonce_key) = self.nonce_key {
            let nonce = provider.get_nonce(self.op.sender, nonce_key).await?;
            self.op.nonce = U256::from(nonce);
        }

        if !self.gas_set {
            self.estimate_gas(provider).await?;
        }

        Ok(self.op)
    }

    async fn estimate_gas(&mut self, provider: &BundlerProvider) -> Result<(), BundlerError> {
        let est = provider.estimate_gas(&self.op).await?;
        let max_fee = provider.suggest_max_fee_per_gas().await?;
        let max_priority_fee = provider.suggest_max_priority_fee_per_gas().await?;

        self.op.call_gas_limit = u256_to_u128(est.call_gas_limit);
        self.op.verification_gas_limit = u256_to_u128(est.verification_gas_limit);
        self.op.pre_verification_gas = u256_to_u128(est.pre_verification_gas);
        self.op.max_fee_per_gas = max_fee;
        self.op.max_priority_fee_per_gas = max_priority_fee;
        self.op.paymaster_verification_gas_limit =
            est.paymaster_verification_gas_limit.map(u256_to_u128);
        self.op.paymaster_post_op_gas_limit = est.paymaster_post_op_gas_limit.map(u256_to_u128);
        Ok(())
    }
}

fn u256_to_u128(v: U256) -> u128 {
    v.saturating_to()
}
