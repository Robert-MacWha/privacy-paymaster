use alloy::{
    primitives::{Address, address},
    sol_types::{Eip712Domain, eip712_domain},
};

pub const ENTRY_POINT_08: Address = address!("0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108");
pub const ENTRY_POINT_08_DOMAIN: Eip712Domain = eip712_domain! {
    name: "ERC4337",
    version: "1",
    chain_id: 1,
    verifying_contract: address!("0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108"),
};
