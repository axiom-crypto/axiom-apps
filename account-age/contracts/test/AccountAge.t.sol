// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "@axiom/src/AxiomDemo.sol";
import "../lib/YulDeployer.sol";
import "../src/AccountAge.sol";

uint32 constant testBlockNumber = 7223086;
uint32 constant testPrevBlockNumber = 7222272;
bytes32 constant testPrevBlockHash = bytes32(hex"acafa94f7772123e7f7b0538f86a2f42176f5bff18af96da0e926fe6b49513c8");
bytes32 constant testCurrBlockHash = bytes32(hex"7f3e693e42d45526b98ad3be7be681c07ce05618f515d097280aab5860360209");
bytes32 constant testPrevHash = bytes32(hex"a3e3b64135c6002f8cebfcf1a6faeadf738810cf1c5dec785af15332b88a58d7");
bytes32 constant testRoot = bytes32(hex"162320b81c5945e7b2477150cc7e8a4a289421e171e089ff46317b5711aa4a98");
uint32 constant testNumFinal = 0;

contract AccountAgeTest is Test {
    AxiomDemo public axiom;
    YulDeployer yulDeployer;    
    AccountAge app;

    function setUp() public {
        yulDeployer = new YulDeployer();
        address accountAgeAddress = address(yulDeployer.deployContract("PlonkVerifier"));
        address axiomVerifierAddress = address(yulDeployer.deployContract("mainnet_10_7"));

        axiom = new AxiomDemo(
            axiomVerifierAddress,
            axiomVerifierAddress,
            testPrevBlockNumber, 
            keccak256(abi.encodePacked(testPrevHash, testRoot, testNumFinal))        
        );
        app = new AccountAge(accountAgeAddress, address(axiom));
    }

    function testVerifyAge() public {
        // Import test proof and instance calldata
        string[] memory inputs = new string[](2);
        inputs[0] = "cat";
        inputs[1] = "test/data/test.calldata";
        bytes memory proof = vm.ffi(inputs);

        // Prepare witness data for account age proof.
        address account = 0xd20BebA9eFA30fB34aF93AF5c91C9a4d6854eAC4;
        uint32 blockNumber = 7223086;
        bytes32[TREE_DEPTH] memory prevBlockMerkleProof = [
            bytes32(0xcc8005f086f967abe0300d9ef450f1c27d3fec76c449ffa0c978f3557cf8085b),
            bytes32(0xf24b175d5975e56aa1491932882f568f803b44839fd560d7f84ce606884171d3),
            bytes32(0x20b208628fdd71f05c28c8751b2ce9712403827a91e59a41feab1b6f3ac8a726),
            bytes32(0x294139bd5d86654a23adaf927dc8835e11a15543ad4c17968b34a7b737c6c3c0),
            bytes32(0x8088a749a7d4c3aa7168cc3c5dceb3a6276470b017fd8204b5138c95c346b1e4),
            bytes32(0x4574c9d98cfb69f06c8c4249a35277d776be5300cfd446a48435fc7729278304),
            bytes32(0x2708aa326d94dc4c4b7fe0b0ccaa819ee8c205be1c38905f444ae32bf61c0d25),
            bytes32(0x209a52e44f78f2c93bcdf36910dbc3cf391b27f5dc1286088aa866202a300196),
            bytes32(0xfe904e836ccb5f33cc28faea81fbb1cb0e9169e62e11b7d0e026648ae7e582f9),
            bytes32(0x66c75ef2145ecadbc2bc56b6182be236a0017e6bbf95edd3d66fcded284bd47c)                   
        ];
        bytes32[TREE_DEPTH] memory currBlockMerkleProof = [
            bytes32(0x35f84db1609fa6ef9902780f5068ef82d7e766598e03904f7d7e030bf7293dcd),
            bytes32(0xc64f42837e8fda87eeaa74f2dae28436e2650e693d01640f62071bb07dbc00bc),
            bytes32(0x20b208628fdd71f05c28c8751b2ce9712403827a91e59a41feab1b6f3ac8a726),
            bytes32(0x294139bd5d86654a23adaf927dc8835e11a15543ad4c17968b34a7b737c6c3c0),
            bytes32(0x8088a749a7d4c3aa7168cc3c5dceb3a6276470b017fd8204b5138c95c346b1e4),
            bytes32(0x4574c9d98cfb69f06c8c4249a35277d776be5300cfd446a48435fc7729278304),
            bytes32(0x2708aa326d94dc4c4b7fe0b0ccaa819ee8c205be1c38905f444ae32bf61c0d25),
            bytes32(0x209a52e44f78f2c93bcdf36910dbc3cf391b27f5dc1286088aa866202a300196),
            bytes32(0xfe904e836ccb5f33cc28faea81fbb1cb0e9169e62e11b7d0e026648ae7e582f9),
            bytes32(0x66c75ef2145ecadbc2bc56b6182be236a0017e6bbf95edd3d66fcded284bd47c)                   
        ];        
        Axiom.BlockHashWitness memory prevBlock = Axiom.BlockHashWitness({
            blockNumber: blockNumber - 1,
            claimedBlockHash: testPrevBlockHash,
            prevHash: testPrevHash,
            numFinal: 0,
            merkleProof: prevBlockMerkleProof
        });
        Axiom.BlockHashWitness memory currBlock = Axiom.BlockHashWitness({
            blockNumber: blockNumber,
            claimedBlockHash: testCurrBlockHash,
            prevHash: testPrevHash,
            numFinal: 0,
            merkleProof: currBlockMerkleProof
        });

        // Call verify function in app
        app.verifyAge(account, prevBlock, currBlock, proof);
    }
}
