use std::sync::Arc;

use axiom_scaffold::axiom_eth::{
    util::scheduler::{
        evm_wrapper::{EvmWrapper, SimpleTask},
        Task,
    },
    Network,
};
use ethers_core::types::Address;
use ethers_providers::{Http, Provider};

pub use super::UniswapV2TwapCircuit;

pub type UniswapV2TwapScheduler = EvmWrapper<UniswapTwapTask>;

#[derive(Clone, Copy, Debug, Hash, Eq, PartialEq)]
pub struct UniswapTwapTask {
    pub start_block_number: u32,
    pub end_block_number: u32,
    pub pair_address: Address,
    network: Network,
}

impl UniswapTwapTask {
    pub fn new(
        start_block_number: u32,
        end_block_number: u32,
        pair_address: Address,
        network: Network,
    ) -> Self {
        Self { start_block_number, end_block_number, pair_address, network }
    }

    pub fn network(&self) -> Network {
        self.network
    }
}

impl Task for UniswapTwapTask {
    type CircuitType = Network;

    fn circuit_type(&self) -> Network {
        self.network
    }
    fn type_name(network: Network) -> String {
        format!("{network}")
    }
    fn name(&self) -> String {
        format!(
            "{}_{:?}_{:06x}_{:06x}",
            self.network, self.pair_address, self.start_block_number, self.end_block_number
        )
    }
    fn dependencies(&self) -> Vec<Self> {
        vec![]
    }
}

impl SimpleTask for UniswapTwapTask {
    type PreCircuit = UniswapV2TwapCircuit;

    fn get_circuit(&self, provider: Arc<Provider<Http>>, _: Network) -> UniswapV2TwapCircuit {
        UniswapV2TwapCircuit {
            provider,
            pair_address: self.pair_address,
            start_block_number: self.start_block_number,
            end_block_number: self.end_block_number,
        }
    }
}
