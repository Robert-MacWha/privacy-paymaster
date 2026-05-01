use alloy_primitives::{Address, Bytes};
use alloy_sol_types::SolCall;

use crate::{UserOperationBuilder, abis::privacy_account::IPrivacyAccount};

pub struct RailgunProtocol {
    fee_calldata: Bytes,
    tail_calls: Vec<IPrivacyAccount::Call>,
}

// TODO: Add helper function for constructing a new Builder fomr (sender: Address, fee_transaction: RailgunSmartWallet::Transaction)
impl UserOperationBuilder<RailgunProtocol> {
    /// Create a new Railgun UserOperationBuilder with the given sender and fee transaction calldata.
    ///
    /// fee_calldata should be the RailgunSmartWallet::transactCall::abi_encode((fee_transaction)) containing
    /// a single transaction that pays the fee.
    pub fn new_railgun(sender: Address, fee_calldata: Bytes) -> Self {
        let protocol = RailgunProtocol {
            fee_calldata,
            tail_calls: Vec::new(),
        };

        let builder = UserOperationBuilder::new_with(sender, protocol);
        builder.update_calldata()
    }

    pub fn with_tail_calls(mut self, calls: Vec<IPrivacyAccount::Call>) -> Self {
        self.protocol.tail_calls = calls;
        self.update_calldata()
    }

    fn update_calldata(self) -> Self {
        let fee_call = self.protocol.fee_calldata.clone();
        let calldata =
            IPrivacyAccount::executeCall::new((fee_call, self.protocol.tail_calls.clone()))
                .abi_encode()
                .into();
        self.with_calldata(calldata)
    }
}
