use axiom_account_age::helpers::{AccountAgeScheduler, AccountAgeTask};
use axiom_scaffold::axiom_eth::{
    util::scheduler::{evm_wrapper::Wrapper::ForEvm, Scheduler},
    Network,
};
use clap::Parser;
use clap_num::maybe_hex;
use ethers_core::types::Address;
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)] // Read from `Cargo.toml`
/// Generates ZK SNARK that proves the account age of an EOA Ethereum address, where
/// account age is defined as the block of the first transaction made by the account.
///
/// The output is the proof calldata to send to the EVM SNARK verifier or Axiom's specialized AccountAge smart contract.
/// Optionally produces the EVM verifier contract Yul code.
struct Cli {
    #[arg(long, default_value_t = Network::Mainnet)]
    network: Network,
    #[arg(short, long = "address")]
    address: Address,
    #[arg(short, long = "block-number", value_parser=maybe_hex::<u32>)]
    block_number: u32,
    #[arg(long = "create-contract")]
    create_contract: bool,
    #[arg(long = "readonly")]
    readonly: bool,
    #[arg(long = "srs-readonly")]
    srs_readonly: bool,
    #[arg(short, long = "config-path")]
    config_path: Option<PathBuf>,
    #[arg(short, long = "data-path")]
    data_path: Option<PathBuf>,
}

fn main() {
    let args = Cli::parse();
    #[cfg(feature = "production")]
    let srs_readonly = true;
    #[cfg(not(feature = "production"))]
    let srs_readonly = args.srs_readonly;

    let scheduler = AccountAgeScheduler::new(
        args.network,
        srs_readonly,
        args.readonly,
        args.config_path.unwrap_or_else(|| PathBuf::from("configs")),
        args.data_path.unwrap_or_else(|| PathBuf::from("data")),
    );

    scheduler.get_calldata(
        ForEvm(AccountAgeTask::new(args.block_number, args.address, args.network)),
        args.create_contract,
    );
}
