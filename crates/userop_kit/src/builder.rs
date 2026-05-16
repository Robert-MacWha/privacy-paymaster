use alloy::primitives::{Address, Bytes, U256};
use alloy_sol_types::Eip712Domain;

use crate::bundler::{BundlerError, BundlerProvider};
use crate::signable_user_operation::SignableUserOperation;
use crate::{UserOperation, UserOperationGasEstimate};

pub struct UserOperationBuilder<P = ()> {
    pub op: UserOperation,
    pub protocol: P,

    gas_set: bool,
    entry_point: Address,
    domain: Eip712Domain,
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
                authorization: Default::default(),
            },
            entry_point,
            domain,
            protocol,
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

    /// Sets the 4337 operation nonce for this UserOperation.
    pub fn with_nonce(mut self, nonce: U256) -> Self {
        self.op.nonce = nonce;
        self
    }

    pub fn with_authorization(mut self, auth: alloy::eips::eip7702::Authorization) -> Self {
        self.op.authorization = crate::user_operation::Authorization::Eip7702(auth);
        self
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
        let op = self.build();
        let (est, max_fee, max_priority_fee) = futures::try_join!(
            bundler.estimate_gas(&op),
            bundler.suggest_max_fee_per_gas(),
            bundler.suggest_max_priority_fee_per_gas()
        )?;

        self.set_gas(est, max_fee, max_priority_fee);
        Ok(self)
    }

    fn set_gas(
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

    pub fn build(&self) -> SignableUserOperation {
        SignableUserOperation {
            user_op: self.op.clone(),
            entry_point: self.entry_point,
            domain: self.domain.clone(),
        }
    }
}
