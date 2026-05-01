use alloy_primitives::Address;
use alloy_sol_types::SolCall;

use crate::{
    UserOperationBuilder,
    abis::{privacy_account::IPrivacyAccount, railgun::RailgunSmartWallet},
};

pub struct RailgunProtocol {
    fee_transaction: RailgunSmartWallet::transactCall,
    tail_calls: Vec<IPrivacyAccount::Call>,
}

impl UserOperationBuilder<RailgunProtocol> {
    pub fn new_railgun(sender: Address, fee_transaction: RailgunSmartWallet::Transaction) -> Self {
        let protocol = RailgunProtocol {
            fee_transaction: RailgunSmartWallet::transactCall::new((vec![fee_transaction],)),
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
        let fee_call = self.protocol.fee_transaction.abi_encode().into();
        let calldata =
            IPrivacyAccount::executeCall::new((fee_call, self.protocol.tail_calls.clone()))
                .abi_encode()
                .into();
        self.with_calldata(calldata)
    }
}
