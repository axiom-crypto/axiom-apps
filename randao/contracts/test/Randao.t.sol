// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "@axiom/src/AxiomDemo.sol";
import "../src/Randao.sol";
import "../lib/YulDeployer.sol";

uint32 constant testBlockNumber = 0xf929e6;
uint32 constant testPrevBlockNumber = 16328704;
bytes32 constant testBlockHash = bytes32(hex"eaa53f3fbfe912c45af96f4a1a34e3cb1de8e9ac1b6fe8d8b1c9eadad976eda9");
bytes32 constant testPrevHash = bytes32(hex"87445763da0b6836b89b8189c4fe71861987aa9af5a715bfb222a7978d98630d");
bytes32 constant testRoot = bytes32(hex"94768cc8e722c0dfa1be6e2326573764102b7a80685a3e98d340ab121e7277cd");
uint32 constant testNumFinal = 0;

contract RandaoTest is Test {
    AxiomDemo public axiom;
    YulDeployer yulDeployer;    
    Randao app;

    function setUp() public {
        yulDeployer = new YulDeployer();
        address axiomVerifierAddress = address(yulDeployer.deployContract("mainnet_10_7"));

        axiom = new AxiomDemo(
            axiomVerifierAddress,
            axiomVerifierAddress,
            testPrevBlockNumber, 
            keccak256(abi.encodePacked(testPrevHash, testRoot, testNumFinal))        
        );
        app = new Randao(address(axiom));
    }

    function testVerifyRandao() public {
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
        Axiom.BlockHashWitness memory block = Axiom.BlockHashWitness({
            blockNumber: testBlockNumber,
            claimedBlockHash: testBlockHash,
            prevHash: testPrevHash,
            numFinal: 0,
            merkleProof: blockMerkleProof
        });
        uint256 prevRandao = 0x77e70a1ebdeffad090cf2b0c8a126b9a6d5befa12669ff0e5001997e1a326599;

        // Call verify function in app
        app.verifyRandao(block, prevRandao, blockRlpPrev, blockRlpPost);
    }
}