import argparse
import os
import asyncio
import json
from dotenv import load_dotenv
from web3 import Web3

# from utils import get_secret

from gql import Client, gql
from gql.transport.websockets import WebsocketsTransport

CHAIN_ID = 1
INITIAL_DEPTH = 7
MAX_DEPTH = 10
NUM_LEAVES = 2**MAX_DEPTH
AXIOM_ADDRESS = "0x09120eAED8e4cD86D85a616680151DAA653880F2"


SUBSCRIPTION = gql(
    """
subscription BlockHeaderProofSubscription(
    $end_num: Int!,
    $chain_id: Int!,
    $initial_depth: Int!,
    $max_depth: Int!
) {
    demo_block_headers_calldata_stream(
        batch_size: 1, 
        cursor: {initial_value: {end_num: $end_num}, ordering: ASC}, 
        where: {max_depth: {_eq: $max_depth}, initial_depth: {_eq: $initial_depth}, chain_id: {_eq: $chain_id}}
    ) {
        calldata
        start_num
        end_num
    }
}
"""
)


def sign_contract_transaction(txn):
    keystore_path = os.getenv("KEYSTORE_PATH")
    key_passwd = os.getenv("KEY_PASSWD")  # TESTING
    # key_passwd = get_secret("prod/AxiomHotWallet/Clef") # PROD

    # no network connection should interact with private key
    w3 = Web3(None)
    with open(keystore_path) as keyfile:
        encrypted_key = keyfile.read()
        private_key = w3.eth.account.decrypt(encrypted_key, key_passwd)
    return w3.eth.account.sign_transaction(txn, private_key)


def sign_axiom_update_recent(w3, sender_address, axiom, calldata):
    nonce = w3.eth.get_transaction_count(Web3.toChecksumAddress(sender_address))
    axiom_txn = axiom.functions.updateRecent(
        Web3.toHex(hexstr=calldata)
    ).build_transaction(
        {
            "chainId": CHAIN_ID,
            "gas": 500_000,
            "maxPriorityFeePerGas": w3.toWei(3, "gwei"),
            "nonce": nonce,
        }
    )
    return sign_contract_transaction(axiom_txn)


def axiom_abi():
    abi_path = "out/Axiom.sol/Axiom.json"
    with open(abi_path) as f:
        data = json.load(f)
    return data["abi"]


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--latest", type=int)
    args = parser.parse_args()

    token = os.getenv("JWT_TOKEN")  # TESTING
    # token = get_secret("prod/AxiomWatcher/Hasura") # PROD
    transport = WebsocketsTransport(
        url="wss://axiom-database-1.hasura.app/v1/graphql",
        headers={"Authorization": f"Bearer {token}"},
    )

    w3 = Web3(
        Web3.HTTPProvider("http://localhost:8545")
    )  # TESTING local testnet
    # infura_id = get_secret("prod/INFURA_ID")
    # w3 = Web3(Web3.HTTPProvider(f"https://mainnet.infura.io/v3/{infura_id}")) # PROD

    axiom = w3.eth.contract(address=AXIOM_ADDRESS, abi=axiom_abi())
    load_dotenv()
    sender_address = os.getenv("SENDER_ADDRESS")

    if args.latest is not None:
        last_updated = args.latest
    else:
        block_number = Web3.toInt(w3.eth.block_number)
        last_updated = block_number - 256
        event_filter = axiom.events.UpdateEvent.createFilter(
            fromBlock=last_updated, toBlock="latest"
        )
        for UpdateEvent in event_filter.get_all_entries():
            event = UpdateEvent["args"]
            start_num = Web3.toInt(event["startBlockNumber"])
            num_final = Web3.toInt(event["numFinal"])
            last_updated = max(last_updated, start_num + num_final - 1)

    print(f"Starting from last updated block number {last_updated}")

    async with Client(
        transport=transport,
        fetch_schema_from_transport=True,
    ) as gql_session:

        async for result in gql_session.subscribe(
            SUBSCRIPTION,
            variable_values={
                "end_num": last_updated,
                "chain_id": CHAIN_ID,
                "initial_depth": INITIAL_DEPTH,
                "max_depth": MAX_DEPTH,
            },
        ):
            response = result["demo_block_headers_calldata_stream"]
            if response is None or len(response) == 0:
                continue
            response = response[0]

            start_num = int(response["start_num"])
            end_num = int(response["end_num"])
            if end_num <= last_updated:
                continue
            block_number = Web3.toInt(w3.eth.block_number)
            if end_num >= block_number:
                raise Exception(
                    "ALERT! unexpected behavior: "
                    "updater is ahead of latest block"
                )
            if end_num <= block_number - 256:
                raise Exception("ALERT! updater is out of sync with the chain")

            calldata = response["calldata"]
            signed_txn = sign_axiom_update_recent(
                w3, sender_address, axiom, calldata
            )
            tx_hash = w3.eth.send_raw_transaction(signed_txn.rawTransaction)
            tx_receipt = w3.eth.wait_for_transaction_receipt(tx_hash)
            # if transaction failed, something unexpected happened and the updater should stop and alert
            # the admins to investigate
            if tx_receipt.status != 1:
                raise Exception("Transaction failed")
            print(
                f"Successfully sent transaction with start_num: {start_num},"
                f" end_num: {end_num}"
            )
            last_updated = end_num


if __name__ == "__main__":
    asyncio.run(main())
