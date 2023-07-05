# Axiom Apps

Demo applications built using core Axiom functionality. These apps are live on mainnet and you can try them out at [demo.axiom.xyz](https://demo.axiom.xyz).

## Setup

Clone this repository (and git submodule dependencies) with

```bash
git clone --recurse-submodules -j8 https://github.com/axiom-crypto/axiom-apps.git
cd axiom-apps
```

### Environmental variables

```bash
cp .env.example .env
```

Fill in `.env` with your RPC provider URLs. In order for Forge to access these endpoints for testing, we need to source `.env`:

```bash
source .env
```

More detailed instructions are provided in each app's individual readme.
