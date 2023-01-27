import argparse
import getpass
import os
import asyncio
import json
from dotenv import load_dotenv
from web3 import Web3
from update_recent import (
    CHAIN_ID,
    INITIAL_DEPTH,
    MAX_DEPTH,
    AXIOM_ADDRESS,
    sign_contract_transaction,
    axiom_abi,
)

# from utils import get_secret

from gql import gql, Client
from gql.transport.aiohttp import AIOHTTPTransport

HISTORICAL_DEPTH = 17
HISTORICAL_NUM_LEAVES = 2**HISTORICAL_DEPTH

QUERY_CALLDATA = gql(
    """
query QueryCallData($start_num: Int!, $end_num: Int!, $chain_id: Int!, $initial_depth: Int!, $max_depth: Int!) {
  demo_block_headers_calldata_by_pk(chain_id: $chain_id, end_num: $end_num, initial_depth: $initial_depth, max_depth: $max_depth, start_num: $start_num) {
    calldata
  }
}
"""
)

QUERY_BLOCKHASH = gql(
    """
query QueryBlockHashes($start: Int!, $stop: Int!) {
  demo_chaindata(order_by: {block_number: asc}, where: {block_number: {_gte: $start, _lt: $stop}}) {
    block_hash
  }
}
"""
)


def hash_tree_root(leaves):
    if len(leaves) == 0:
        return Web3.toBytes(0)
    elif len(leaves) == 1:
        return leaves[0]
    depth = len(leaves).bit_length() - 1
    assert 1 << depth == len(leaves)
    hashes = leaves
    for d in range(depth - 1, -1, -1):
        new_hashes = [
            Web3.solidityKeccak(
                ["bytes32", "bytes32"], [hashes[2 * i], hashes[2 * i + 1]]
            )
            for i in range(1 << d)
        ]
        hashes = new_hashes
    return hashes[0]


# returns block hashes of block numbers [start, stop)
def get_block_hashes(gql_client, start, stop):
    response = gql_client.execute(
        QUERY_BLOCKHASH, variable_values={"start": start, "stop": stop}
    )
    objects = response["demo_chaindata"]
    assert len(objects) == stop - start, "Not all block hashes found"
    return [Web3.toBytes(hexstr=obj["block_hash"]) for obj in objects]


def sign_axiom_update_historical(
    w3,
    gql_client,
    sender_address,
    axiom,
    start_num,
    next_root,
    next_num_final,
    proof_data,
):
    # get block hashes
    block_hashes = get_block_hashes(
        gql_client, start_num, start_num + HISTORICAL_NUM_LEAVES
    )
    roots = [
        Web3.toBytes(hash_tree_root(block_hashes[i : i + 2**MAX_DEPTH]))
        for i in range(0, HISTORICAL_NUM_LEAVES, 2**MAX_DEPTH)
    ]

    # build transaction
    nonce = w3.eth.get_transaction_count(Web3.toChecksumAddress(sender_address))
    axiom_txn = axiom.functions.updateHistorical(
        next_root,
        next_num_final,
        roots,
        Web3.toHex(hexstr=proof_data),
    ).build_transaction(
        {
            "chainId": CHAIN_ID,
            "gas": 5_000_000,
            "maxPriorityFeePerGas": w3.toWei(3, "gwei"),
            "nonce": nonce,
        }
    )
    return sign_contract_transaction(axiom_txn)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--prev-num", type=int, required=True)
    args = parser.parse_args()

    token = os.getenv("JWT_TOKEN")  # TESTING
    # token = get_secret("prod/AxiomWatcher/Hasura")
    transport = AIOHTTPTransport(
        url="https://axiom-database-1.hasura.app/v1/graphql",
        headers={"Authorization": f"Bearer {token}"},
    )

    w3 = Web3(
        Web3.HTTPProvider("http://localhost:8545")
    )  # TESTING local testnet
    # infura_id = get_secret("prod/INFURA_ID")
    # w3 = Web3(Web3.HTTPProvider(f"https://mainnet.infura.io/v3/{infura_id}"))

    axiom = w3.eth.contract(address=AXIOM_ADDRESS, abi=axiom_abi())
    load_dotenv()
    sender_address = os.getenv("SENDER_ADDRESS")

    print(
        "WARNING!!! You are about to send a very expensive transaction. "
        "Are you sure you want to proceed?"
    )
    if input("Confirm (Yes/no): ") != "Yes":
        return

    prev_num = args.prev_num
    event_filter = axiom.events.UpdateEvent.createFilter(
        fromBlock=prev_num - 1024, toBlock="latest"
    )
    last_event_block = 0
    # find the update event for prev_num
    for UpdateEvent in event_filter.get_all_entries():
        event = UpdateEvent["args"]
        event_block_num = Web3.toInt(UpdateEvent["blockNumber"])
        start_num = Web3.toInt(event["startBlockNumber"])
        if start_num == prev_num and event_block_num > last_event_block:
            num_final = Web3.toInt(event["numFinal"])
            next_root = event["root"]
            last_event_block = event_block_num
    if next_root is None:
        raise Exception(
            f"No existing UpdateEvent has startBlockNumber = {prev_num}"
        )

    gql_client = Client(transport=transport)

    result = gql_client.execute(
        QUERY_CALLDATA,
        variable_values={
            "end_num": prev_num - 1,
            "start_num": prev_num - HISTORICAL_NUM_LEAVES,
            "chain_id": CHAIN_ID,
            "initial_depth": INITIAL_DEPTH,
            "max_depth": HISTORICAL_DEPTH,
        },
    )
    calldata = result["demo_block_headers_calldata_by_pk"]["calldata"]
    if calldata is None:
        raise Exception("[ERROR] calldata does not exist")

    print(calldata)
    signed_txn = sign_axiom_update_historical(
        w3,
        gql_client,
        sender_address,
        axiom,
        prev_num - HISTORICAL_NUM_LEAVES,
        next_root,
        num_final,
        calldata,
    )
    tx_hash = w3.eth.send_raw_transaction(signed_txn.rawTransaction)
    tx_receipt = w3.eth.wait_for_transaction_receipt(tx_hash)
    # if transaction failed, something unexpected happened and the updater should stop and alert
    # the admins to investigate
    if tx_receipt.status != 1:
        raise Exception("Transaction failed")
    print(
        "Successfully updated historical blocks"
        f" {prev_num - HISTORICAL_NUM_LEAVES} to {prev_num - 1}"
    )


if __name__ == "__main__":
    main()
