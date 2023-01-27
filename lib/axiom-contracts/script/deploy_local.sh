LOCAL_RPC_URL="http://localhost:8545"
source ../.env
# forge script AxiomStoragePfDeployLocal.s.sol:AxiomStoragePfDeployLocal --rpc-url $LOCAL_RPC_URL --broadcast --verify -vvvv
forge script AxiomDeployLocal.s.sol:AxiomDeployLocal --rpc-url $LOCAL_RPC_URL --broadcast --verify -vvvv
