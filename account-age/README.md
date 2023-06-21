# Axiom Account Age App

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
