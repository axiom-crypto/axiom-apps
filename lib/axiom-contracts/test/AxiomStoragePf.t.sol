// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Axiom.sol";
import "../src/AxiomDemo.sol";
import "../src/AxiomStoragePf.sol";
import "./lib/YulDeployer.sol";

uint32 constant testBlockNumber = 0xf929e6;
uint32 constant testPrevBlockNumber = 16328704;
bytes32 constant testBlockHash = bytes32(hex"eaa53f3fbfe912c45af96f4a1a34e3cb1de8e9ac1b6fe8d8b1c9eadad976eda9");
bytes32 constant testPrevHash = bytes32(hex"87445763da0b6836b89b8189c4fe71861987aa9af5a715bfb222a7978d98630d");
bytes32 constant testRoot = bytes32(hex"94768cc8e722c0dfa1be6e2326573764102b7a80685a3e98d340ab121e7277cd");
uint32 constant testNumFinal = 0;

contract AxiomStoragePfTest is Test {
    AxiomDemo public axiom;
    AxiomStoragePf public axiomStorage;
    YulDeployer yulDeployer;

    function setUp() public {
        yulDeployer = new YulDeployer();
        address axiomVerifierAddress = address(yulDeployer.deployContract("mainnet_10_7"));
        address storageVerifierAddress = address(yulDeployer.deployContract("storage"));

        axiom = new AxiomDemo(
            axiomVerifierAddress,
            axiomVerifierAddress,
            testPrevBlockNumber, 
            keccak256(abi.encodePacked(testPrevHash, testRoot, testNumFinal))        
        );
        axiomStorage = new AxiomStoragePf(address(axiom), storageVerifierAddress);
    }

    function testAttestSlots() public {        
        string memory path = "test/data/storage.calldata";
        string memory bashCommand = string.concat('cast abi-encode "f(bytes)" $(cat ', string.concat(path, ")"));

        string[] memory inputs = new string[](3);
        inputs[0] = "bash";
        inputs[1] = "-c";
        inputs[2] = bashCommand;        

        bytes memory proof = abi.decode(vm.ffi(inputs), (bytes));
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
        Axiom.BlockHashWitness memory blockData = Axiom.BlockHashWitness({
            blockNumber: testBlockNumber,
            claimedBlockHash: testBlockHash,
            prevHash: testPrevHash,
            numFinal: testNumFinal,
            merkleProof: blockMerkleProof
        });

        axiomStorage.attestSlots(blockData, proof);
    }
}
