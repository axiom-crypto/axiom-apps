// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../lib/YulDeployer.sol";
import "../src/UniswapTwap.sol";
import "../test/MockAxiom.sol";

contract UniswapTwapTest is Test {
    YulDeployer yulDeployer = new YulDeployer();

    function testVerifyTwapPri() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy mock block cache contract
        MockAxiom cache = new MockAxiom();

        // Deploy PLONK verifier contract
        address plonkVerifierAddress = yulDeployer.deployContract("PlonkVerifier");
        
        // Deploy Uniswap TWAP contact
        UniswapTwap app = new UniswapTwap(plonkVerifierAddress, address(cache));

        // Import test proof and instance calldata
        string[] memory inputs = new string[](2);
        inputs[0] = "cat";
        inputs[1] = "test/data/test.calldata";
        bytes memory proof = vm.ffi(inputs);

        // Prepare witness data for Uniswap TWAP proof.
        // Note that only the claimed block hash is checked in the test.
        uint32 startBlockNumber = 0xf4456b;
        uint32 endBlockNumber = 0xfab942;
        bytes32 startBlockHash = 0x4cc24ed848c5d1243ac65af84470d38ed339a6ae85d88896a326d08c07cbb4d5;
        bytes32 endBlockHash = 0xab5c0c98cb198a6d012a7d4f640750ca3e03e04f386dba0a2a4a7d95b10da8e1;        
        bytes32[10] memory startBlockMerkleProof = [
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000)                  
        ];
        bytes32[10] memory endBlockMerkleProof = [
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000)                  
        ];
        UniswapTwap.BlockHashWitness memory startBlock = UniswapTwap.BlockHashWitness({
            blockNumber: startBlockNumber,
            claimedBlockHash: startBlockHash,
            prevHash: 0x0000000000000000000000000000000000000000000000000000000000000000,
            numFinal: 0,
            merkleProof: startBlockMerkleProof
        });
        UniswapTwap.BlockHashWitness memory endBlock = UniswapTwap.BlockHashWitness({
            blockNumber: endBlockNumber,
            claimedBlockHash: endBlockHash,
            prevHash: 0x0000000000000000000000000000000000000000000000000000000000000000,
            numFinal: 0,
            merkleProof: endBlockMerkleProof
        });
        // twapPri in uq112x112 format, test value computed independently
        uint256 twapPri = 0x056a73df806331153e53e2;
        
        // Insert required block hashes into cache
        cache.setBlockHash(startBlockNumber, uint256(startBlockHash));
        cache.setBlockHash(endBlockNumber, uint256(endBlockHash));

        // Call verify function in app
        app.verifyUniswapTwap(startBlock, endBlock, twapPri, proof);

        vm.stopBroadcast();
    }
}