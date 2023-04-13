// Copied from uniswap-v3-oracles/circuits/src/bin/v3_twap_proof.rs
#![feature(proc_macro_hygiene, decl_macro)]
#[macro_use]
extern crate rocket;

use std::path::PathBuf;

use axiom_scaffold::axiom_eth::{
    util::scheduler::{evm_wrapper::Wrapper::ForEvm, Scheduler},
    Network,
};
use axiom_uniswap_v2_twap::helpers::{UniswapTwapTask, UniswapV2TwapScheduler};
use clap::Parser;
use ethers_core::types::Address;
use rocket::State;
use rocket_contrib::json::Json;
use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, Hash, Eq, PartialEq, Serialize, Deserialize)]
pub struct Task {
    pub start_block_number: u32,
    pub end_block_number: u32,
    pub address: Address,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub chain_id: Option<u64>,
}

impl TryFrom<Task> for UniswapTwapTask {
    type Error = &'static str;

    fn try_from(task: Task) -> Result<Self, Self::Error> {
        let chain_id = task.chain_id.unwrap_or(1);
        let network = match chain_id {
            1 => Ok(Network::Mainnet),
            5 => Ok(Network::Goerli),
            _ => Err("Unsupported chainid"),
        };
        network.map(|network| {
            Self::new(task.start_block_number, task.end_block_number, task.address, network)
        })
    }
}

#[post("/uniswap-v2", format = "json", data = "<task>")]
fn serve(task: Json<Task>, oracle: State<UniswapV2TwapScheduler>) -> Result<String, String> {
    let task: UniswapTwapTask = task.into_inner().try_into()?;
    if task.network() != oracle.network {
        return Err(format!(
            "JSON-RPC provider expected {:?}, got {:?}",
            oracle.network,
            task.network()
        ));
    }
    if task.start_block_number > task.end_block_number {
        return Err(format!(
            "start_block_number ({}) > end_block_number ({})",
            task.start_block_number, task.end_block_number
        ));
    }

    // Get the proof calldata
    let calldata = oracle.get_calldata(ForEvm(task), false);
    Ok(calldata)
}

#[derive(Parser, Debug)]
struct Cli {
    #[arg(long, default_value_t = Network::Mainnet)]
    network: Network,
    #[arg(short, long = "config-path")]
    config_path: Option<PathBuf>,
    #[arg(short, long = "data-path")]
    data_path: Option<PathBuf>,
}

fn main() {
    let args = Cli::parse();
    let oracle = UniswapV2TwapScheduler::new(
        args.network,
        true,
        true,
        args.config_path.unwrap_or_else(|| PathBuf::from("configs")),
        args.data_path.unwrap_or_else(|| PathBuf::from("data")),
    );
    rocket::ignite().manage(oracle).mount("/", routes![serve]).launch();
}
