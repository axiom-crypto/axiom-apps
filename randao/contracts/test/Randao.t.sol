// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Randao.sol";
import "../test/MockAxiom.sol";

contract RandaoTest is Test {
    function testVerifyRandao() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy mock block cache contract
        MockAxiom cache = new MockAxiom();
        
        // Deploy Uniswap TWAP contact
        Randao app = new Randao(address(cache));

        // Import test proof and instance calldata
        string[] memory prevInputs = new string[](2);
        prevInputs[0] = "cat";
        prevInputs[1] = "test/data/testPrev.calldata";
        bytes memory blockRlpPrev = vm.ffi(prevInputs);

        // Import test proof and instance calldata
        string[] memory postInputs = new string[](2);
        postInputs[0] = "cat";
        postInputs[1] = "test/data/testPost.calldata";
        bytes memory blockRlpPost = vm.ffi(postInputs);

        // Prepare witness data for Uniswap TWAP proof.
        // Note that only the claimed block hash is checked in the test.
        uint32 blockNumber = 0xf4456b;
        bytes32 blockHash = 0x4cc24ed848c5d1243ac65af84470d38ed339a6ae85d88896a326d08c07cbb4d5;
        bytes32[10] memory blockMerkleProof = [
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
        Randao.BlockHashWitness memory block = Randao.BlockHashWitness({
            blockNumber: blockNumber,
            claimedBlockHash: blockHash,
            prevHash: 0x0000000000000000000000000000000000000000000000000000000000000000,
            numFinal: 0,
            merkleProof: blockMerkleProof
        });
        uint256 prevRandao = 0xdc3a72752076f8f6aa38686afdcdc8e7c20a040670a7938e014d15665d2063ef;
        
        // Insert required block hashes into cache
        cache.setBlockHash(blockNumber, uint256(blockHash));

        // Call verify function in app
        app.verifyRandao(block, prevRandao, blockRlpPrev, blockRlpPost);

        vm.stopBroadcast();
    }
}