# Trustless Uniswap V3 TWAP via ZK (Axiom)

## Circuit

Optional: symlink existing `params` folder to `circuits/params` to avoid regenerating NOT FOR PRODUCTION trusted setup files. (It's fine to ignore this if you don't know what it means.)

If you want to use the same [universal trusted setup](https://docs.axiom.xyz/axiom-architecture/how-axiom-works/kzg-trusted-setup) as the one we use, so that the SNARK verifier matches the one deployed on mainnet, then you can download the following trusted setup files:

```bash
# start in account-age directory
cd circuits
mkdir -p params
wget https://axiom-crypto.s3.amazonaws.com/params/kzg_bn254_19.srs -O params/kzg_bn254_19.srs
wget https://axiom-crypto.s3.amazonaws.com/params/kzg_bn254_23.srs -O params/kzg_bn254_23.srs
cd ..
```

## Smart Contract Testing

We use [foundry](https://book.getfoundry.sh/) for smart contract development and testing. You can follow these [instructions](https://book.getfoundry.sh/getting-started/installation) to install it.
We fork mainnet for tests, so make sure that `.env` variables have been [exported](../README.md#environmental-variables).

After installing `foundry`, in the [`contracts`](contracts/) directory, run:

```bash
forge install
forge test
```

For verbose logging of events and gas tracking, run

```bash
forge test -vvvv
```

## ZK Proving

In the [`circuits`](circuits/) directory, run:

```bash
cargo run --bin v2_twap_proof --release -- --pair <UNISWAP V3 POOL ADDRESS> --start <TWAP START BLOCK NUMBER> --end <TWAP END BLOCK NUMBER>
# For example:
# cargo run --bin v2_twap_proof --release -- --pair 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc --start 10008566 --end 16509301
```

If this is the first time running, it will generate proving keys (and trusted setup files if they don't exist already).
The proof calldata is written as a hex string to `circuits/data/mainnet_*_*_*_evm.calldata`.

You can pass an optional `--create-contract` flag to the binary for it to produce the [Yul code](./circuits/data/mainnet_evm.yul) for the on-chain contract to verifier the ZK proof. Note that this verifier depends on the universal trusted setup you provide in the `params` directory. The trusted setup auto-generated by the binary is **UNSAFE**. See [here](https://docs.axiom.xyz/axiom-architecture/how-axiom-works/kzg-trusted-setup) for more about trusted setups and how to get a trusted setup that was actually created via a multi-party computation.

We provide the [Yul code](./circuits/data/deployed_verifier.yul) for the verifier contract generated using a [trusted setup](https://docs.axiom.xyz/axiom-architecture/how-axiom-works/kzg-trusted-setup) derived from the perpetual powers of tau ceremony shared by [Semaphore](https://medium.com/coinmonks/to-mixers-and-beyond-presenting-semaphore-a-privacy-gadget-built-on-ethereum-4c8b00857c9b) and [Hermez](https://www.reddit.com/r/ethereum/comments/iftos6/powers_of_tau_selection_for_hermez_rollup/).

**Note:** The proof generation requires up to 40GB of RAM to complete. If you do not have enough RAM, you can [set up swap](https://www.digitalocean.com/community/tutorials/how-to-add-swap-space-on-ubuntu-20-04) to compensate (this is done automatically on Macs) at the tradeoff of slower runtimes.

### (Optional) Server

For convenience we provide an implementation of a server that receives POST JSON requests for account age proofs. The benefit of the server is that it holds the proving keys in memory and does not re-read from file each time. To use the server you must have already generated a trusted setup and the proving keys (using the `v2_twap_proof` binary): this is primarily a safety precaution.

**This is provided as a developer tool only. DO NOT USE FOR PRODUCTION.**
To build the server binary, run

```bash
cargo build --bin v2_twap_server --features "server" --no-default-features --release
```

The binary is located in `axiom-apps/target/release/v2_twap_server`. You must start the binary from the `circuits` directory for file paths to work appropriately. Running the binary will start the server on `localhost:8000`.

Once the server is running, you can query it via

```bash
curl -X POST -i "http://localhost:8000/uniswap-v2" -H "Content-Type: application/json" -d @data/task.t.json
```

where [`task.t.json`](./circuits/data/task.t.json) is a JSON file with an example request.