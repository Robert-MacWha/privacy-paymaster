use alloy_primitives::Address;
use alloy_sol_types::SolCall;

use crate::{
    UserOperationBuilder,
    abis::{privacy_account::IPrivacyAccount, tornado::Tornado},
};

pub struct TornadoCashProtocol {
    unshield_calldata: Tornado::withdrawCall,
    tail_calls: Vec<IPrivacyAccount::Call>,
}

impl UserOperationBuilder<TornadoCashProtocol> {
    pub fn new_tornadocash(sender: Address, withdraw: Tornado::withdrawCall) -> Self {
        let protocol = TornadoCashProtocol {
            unshield_calldata: withdraw,
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
        let unshield_calldata = self.protocol.unshield_calldata.abi_encode().into();
        let calldata = IPrivacyAccount::executeCall::new((
            unshield_calldata,
            self.protocol.tail_calls.clone(),
        ))
        .abi_encode()
        .into();
        self.with_calldata(calldata)
    }
}
