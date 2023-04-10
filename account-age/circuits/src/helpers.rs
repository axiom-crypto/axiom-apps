use axiom_scaffold::axiom_eth::{
    util::scheduler::{
        evm_wrapper::{EvmWrapper, SimpleTask},
        Task,
    },
    Network,
};
use ethers_core::types::Address;
use ethers_providers::{Http, Provider};
use std::sync::Arc;

use crate::AccountAgeCircuit;

pub type AccountAgeScheduler = EvmWrapper<AccountAgeTask>;

#[derive(Clone, Copy, Debug, Hash, Eq, PartialEq)]
pub struct AccountAgeTask {
    pub block_number: u32,
    pub address: Address,
    network: Network,
}

impl AccountAgeTask {
    pub fn new(block_number: u32, address: Address, network: Network) -> Self {
        Self { block_number, address, network }
    }

    pub fn network(&self) -> Network {
        self.network
    }
}

impl Task for AccountAgeTask {
    type CircuitType = Network;

    fn circuit_type(&self) -> Network {
        self.network
    }
    fn type_name(network: Network) -> String {
        format!("{network}")
    }
    fn name(&self) -> String {
        format!("{}_{:?}_{:x}", self.network, self.address, self.block_number)
    }
    fn dependencies(&self) -> Vec<Self> {
        vec![]
    }
}

impl SimpleTask for AccountAgeTask {
    type PreCircuit = AccountAgeCircuit;

    fn get_circuit(&self, provider: Arc<Provider<Http>>, _: Network) -> AccountAgeCircuit {
        AccountAgeCircuit {
            provider,
            address: self.address,
            claimed_block_number: self.block_number,
        }
    }
}
