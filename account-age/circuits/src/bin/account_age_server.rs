#![feature(proc_macro_hygiene, decl_macro)]
#[macro_use]
extern crate rocket;

use std::path::PathBuf;

use axiom_account_age::helpers::{AccountAgeScheduler, AccountAgeTask};
use axiom_scaffold::axiom_eth::{
    util::scheduler::{evm_wrapper::Wrapper::ForEvm, Scheduler},
    Network,
};
use clap::Parser;
use ethers_core::types::Address;
use rocket::State;
use rocket_contrib::json::Json;
use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, Hash, Eq, PartialEq, Serialize, Deserialize)]
pub struct Task {
    pub block_number: u32,
    pub address: Address,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub chain_id: Option<u64>,
}

impl TryFrom<Task> for AccountAgeTask {
    type Error = &'static str;

    fn try_from(task: Task) -> Result<Self, Self::Error> {
        let chain_id = task.chain_id.unwrap_or(1);
        let network = match chain_id {
            1 => Ok(Network::Mainnet),
            5 => Ok(Network::Goerli),
            _ => Err("Unsupported chainid"),
        };
        network.map(|network| Self::new(task.block_number, task.address, network))
    }
}

#[post("/account-age", format = "json", data = "<task>")]
fn serve(task: Json<Task>, scheduler: State<AccountAgeScheduler>) -> Result<String, String> {
    let task: AccountAgeTask = task.into_inner().try_into()?;
    if task.network() != scheduler.network {
        return Err(format!(
            "JSON-RPC provider expected {:?}, got {:?}",
            scheduler.network,
            task.network()
        ));
    }
    // Get the proof calldata
    let calldata = scheduler.get_calldata(ForEvm(task), false);
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
    let scheduler = AccountAgeScheduler::new(
        args.network,
        true,
        true,
        args.config_path.unwrap_or_else(|| PathBuf::from("configs")),
        args.data_path.unwrap_or_else(|| PathBuf::from("data")),
    );
    rocket::ignite().manage(scheduler).mount("/", routes![serve]).launch();
}
