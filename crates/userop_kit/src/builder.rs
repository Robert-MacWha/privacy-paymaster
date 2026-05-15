use alloy::primitives::{Address, Bytes, U256};
use alloy::rpc::types::Authorization;
use alloy_sol_types::Eip712Domain;

use crate::bundler::{BundlerError, BundlerProvider};
use crate::{UserOperation, UserOperationGasEstimate};

pub struct UserOperationBuilder<P = ()> {
    pub op: UserOperation,
    pub protocol: P,

    gas_set: bool,
}

impl<P> UserOperationBuilder<P> {
    pub fn new_with(
        sender: Address,
        entry_point: Address,
        domain: Eip712Domain,
        protocol: P,
    ) -> Self {
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
                entry_point,
                domain,
            },
            protocol,
            gas_set: false,
        }
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

    pub fn with_nonce(mut self, nonce: U256) -> Self {
        self.set_nonce(nonce);
        self
    }

    pub fn set_nonce(&mut self, nonce: U256) {
        self.op.nonce = nonce;
    }

    pub fn with_authorization(mut self, auth: Authorization) -> Self {
        self.set_authorization(auth);
        self
    }

    pub fn set_authorization(&mut self, auth: Authorization) {
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

    /// Fetches a gas estimate from the provider for the current UserOp.
    pub async fn with_gas_estimate(
        mut self,
        bundler: &dyn BundlerProvider,
    ) -> Result<Self, BundlerError> {
        let (est, max_fee, max_priority_fee) = futures::try_join!(
            bundler.estimate_gas(&self.op),
            bundler.suggest_max_fee_per_gas(),
            bundler.suggest_max_priority_fee_per_gas()
        )?;

        self.set_gas(est, max_fee, max_priority_fee);
        Ok(self)
    }

    pub fn set_gas(
        &mut self,
        gas: UserOperationGasEstimate,
        max_fee_per_gas: u128,
        max_priority_fee_per_gas: u128,
    ) {
        self.gas_set = true;

        self.op.call_gas_limit = gas.call_gas_limit;
        self.op.verification_gas_limit = gas.verification_gas_limit;
        self.op.pre_verification_gas = gas.pre_verification_gas;
        self.op.paymaster_verification_gas_limit = gas.paymaster_verification_gas_limit;
        self.op.paymaster_post_op_gas_limit = gas.paymaster_post_op_gas_limit;
        self.op.max_fee_per_gas = max_fee_per_gas;
        self.op.max_priority_fee_per_gas = max_priority_fee_per_gas;
    }

    pub fn with_factory(mut self, factory: Address, data: Bytes) -> Self {
        self.op.factory = Some(factory);
        self.op.factory_data = Some(data);
        self
    }

    pub fn build(self) -> UserOperation {
        self.op
    }
}
