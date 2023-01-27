import argparse
import os
import subprocess
import getpass
from botocore.exceptions import ClientError
from dotenv import load_dotenv


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bin-path", type=str, required=True)
    args = parser.parse_args()
    load_dotenv()

    path = args.bin_path

    keystore_path = os.getenv("KEYSTORE_PATH")
    print(
        "WARNING!!! You are about to create a contract, which has expensive"
        " costs. Are you sure you want to proceed?"
    )
    key_passwd = getpass.getpass(prompt="Enter clef password: ")

    with open(args.bin_path, "r") as file:
        bytecode: str = file.read()
        subprocess.run(
            [
                "cast",
                "send",
                "--keystore",
                keystore_path,
                "--password",
                key_passwd,
                "--create",
                bytecode,
            ]
        )
