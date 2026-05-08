use alloy::eips::eip7702::SignedAuthorization;
use alloy::primitives::{Address, Bytes, U256};
use alloy::signers::Signer;

use crate::bundler::{BundlerError, BundlerProvider};
use crate::{UserOperation, UserOperationGasEstimate};

pub struct UserOperationBuilder<P = ()> {
    pub op: UserOperation,
    pub protocol: P,

    gas_set: bool,
}

impl<P> UserOperationBuilder<P> {
    pub fn new_with(protocol: P) -> Self {
        Self {
            op: UserOperation {
                sender: Address::ZERO,
                nonce: U256::ZERO,
                factory: None,
                factory_data: None,
                call_data: Bytes::new(),
                call_gas_limit: 0,
                verification_gas_limit: 0,
                pre_verification_gas: U256::ZERO,
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
            gas_set: false,
        }
    }

    pub fn with_sender(mut self, sender: Address) -> Self {
        self.set_sender(sender);
        self
    }

    pub fn set_sender(&mut self, sender: Address) {
        self.op.sender = sender;
    }

    pub fn with_calldata(mut self, calldata: Bytes) -> Self {
        self.set_calldata(calldata);
        self
    }

    pub fn set_calldata(&mut self, calldata: Bytes) {
        self.op.call_data = calldata;
    }

    pub fn with_paymaster(mut self, paymaster: Address) -> Self {
        self.set_paymaster(paymaster);
        self
    }

    pub fn set_paymaster(&mut self, paymaster: Address) {
        self.op.paymaster = Some(paymaster);
    }

    pub fn with_paymaster_data(mut self, data: Bytes) -> Self {
        self.set_paymaster_data(data);
        self
    }

    pub fn set_paymaster_data(&mut self, data: Bytes) {
        self.op.paymaster_data = Some(data);
    }

    pub fn with_signature(mut self, sig: Bytes) -> Self {
        self.set_signature(sig);
        self
    }

    pub fn set_signature(&mut self, sig: Bytes) {
        self.op.signature = sig;
    }

    pub fn with_nonce(mut self, nonce: U256) -> Self {
        self.set_nonce(nonce);
        self
    }

    pub fn set_nonce(&mut self, nonce: U256) {
        self.op.nonce = nonce;
    }

    pub fn with_authorization(mut self, auth: SignedAuthorization) -> Self {
        self.set_authorization(auth);
        self
    }

    pub fn set_authorization(&mut self, auth: SignedAuthorization) {
        self.op.authorization = Some(auth);
    }

    pub fn with_gas(
        mut self,
        gas: UserOperationGasEstimate,
        max_fee_per_gas: u128,
        max_priority_fee_per_gas: u128,
    ) -> Self {
        self.set_gas(gas, max_fee_per_gas, max_priority_fee_per_gas);
        self
    }

    pub fn set_gas(
        &mut self,
        gas: UserOperationGasEstimate,
        max_fee_per_gas: u128,
        max_priority_fee_per_gas: u128,
    ) {
        self.gas_set = true;

        self.op.call_gas_limit = gas.call_gas_limit.saturating_to();
        self.op.verification_gas_limit = gas.verification_gas_limit.saturating_to();
        self.op.pre_verification_gas = gas.pre_verification_gas.saturating_to();
        self.op.paymaster_verification_gas_limit = gas
            .paymaster_verification_gas_limit
            .map(|v| v.saturating_to());
        self.op.paymaster_post_op_gas_limit =
            gas.paymaster_post_op_gas_limit.map(|v| v.saturating_to());
        self.op.max_fee_per_gas = max_fee_per_gas;
        self.op.max_priority_fee_per_gas = max_priority_fee_per_gas;
    }

    pub fn with_factory(mut self, factory: Address, data: Bytes) -> Self {
        self.op.factory = Some(factory);
        self.op.factory_data = Some(data);
        self
    }

    /// Build a complete `UserOperation` ready for submission.
    pub async fn build(
        mut self,
        sender: &impl Signer,
        provider: &impl BundlerProvider,
    ) -> Result<UserOperation, BundlerError> {
        self.op.sender = sender.address();

        if !self.gas_set {
            self.estimate_gas(provider).await?;
        }

        let hash = self.op.packed().hash(&provider.eip712_domain());
        self.op.signature = sender.sign_hash(&hash).await.unwrap().as_bytes().into();

        Ok(self.op)
    }

    pub async fn estimate_gas(
        &mut self,
        provider: &impl BundlerProvider,
    ) -> Result<(UserOperationGasEstimate, u128, u128), BundlerError> {
        let est = provider.estimate_gas(&self.op).await?;
        let max_fee = provider.suggest_max_fee_per_gas().await?;
        let max_priority_fee = provider.suggest_max_priority_fee_per_gas().await?;

        self.set_gas(est, max_fee, max_priority_fee);
        Ok((est, max_fee, max_priority_fee))
    }
}
