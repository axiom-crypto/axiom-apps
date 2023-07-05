#!/bin/sh
cd $(git rev-parse --show-toplevel)
source .env

cd randao
forge create --ledger --rpc-url $MAINNET_RPC_URL --constructor-args-path deploy/constructor_args.txt --verify --etherscan-api-key $ETHERSCAN_API_KEY --force src/Randao.sol:Randao