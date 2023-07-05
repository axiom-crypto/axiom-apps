#!/bin/sh
cd $(git rev-parse --show-toplevel)
source .env

cd account-age
forge create --ledger --rpc-url $MAINNET_RPC_URL --constructor-args-path deploy/constructor_args.txt --verify --etherscan-api-key $ETHERSCAN_API_KEY --force src/AccountAge.sol:AccountAge

# this actually had problems verifying because viaIR was turned on

# verified later using
# forge flatten src/AccountAge.sol > src/AccountAge.flatten.sol
# forge verify-contract --constructor-args-path deploy/constructor_args.txt 0xDd215c64BB70868cC0D45bF3f7c3d97A074920b2 src/AccountAge.flatten.sol:AccountAge --etherscan-api-key $ETHERSCAN_API_KEY

# using: https://github.com/foundry-rs/foundry/issues/3507#issuecomment-1465382107
