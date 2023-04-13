use std::path::PathBuf;

use crate::helpers::{UniswapTwapTask, UniswapV2TwapScheduler};
use axiom_scaffold::axiom_eth::{
    util::scheduler::{evm_wrapper::Wrapper::ForEvm, Scheduler},
    Network,
};
use ethers_core::types::Address;
use test_log::test;

#[test]
fn test_v2_usdc_eth() {
    let network = Network::Mainnet;
    let oracle = UniswapV2TwapScheduler::new(
        network,
        false,
        false,
        PathBuf::from("configs"),
        PathBuf::from("data"),
    );
    // USDC / WETH pair
    let pair_address = "0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc".parse::<Address>().unwrap();
    // contract creation: https://etherscan.io/tx/0xd07cbde817318492092cc7a27b3064a69bd893c01cb593d6029683ffd290ab3a#internal
    let contract_creation_block_number = 10008355;
    let start_block_number = 0xf4456b;
    assert!(start_block_number >= contract_creation_block_number);
    oracle.get_calldata(
        ForEvm(UniswapTwapTask::new(start_block_number, 0xfab942, pair_address, network)),
        true,
    );
}
