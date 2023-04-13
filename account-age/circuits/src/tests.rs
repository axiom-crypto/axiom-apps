use std::path::PathBuf;

use super::helpers::{AccountAgeScheduler, AccountAgeTask};
use axiom_scaffold::axiom_eth::{
    util::scheduler::{evm_wrapper::Wrapper::ForEvm, Scheduler},
    Network,
};
use ethers_core::types::Address;

fn get_test_task(network: Network) -> AccountAgeTask {
    let addr;
    let block_number;
    match network {
        Network::Mainnet => {
            // vitalik.eth
            addr = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045".parse::<Address>().unwrap();
            block_number = 0x4dc40;
        }
        Network::Goerli => {
            // vitalik.eth
            addr = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045".parse::<Address>().unwrap();
            block_number = 0x304e9d;
        }
    }
    AccountAgeTask::new(block_number, addr, network)
}

#[test]
fn test_mainnet_vitalik() {
    let network = Network::Mainnet;
    let scheduler = AccountAgeScheduler::new(
        network,
        false,
        false,
        PathBuf::from("configs"),
        PathBuf::from("data"),
    );
    scheduler.get_calldata(ForEvm(get_test_task(network)), true);
}
