// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "@axiom/src/AxiomDemo.sol";
import "../src/Randao.sol";
import "../lib/YulDeployer.sol";

uint32 constant testBlockNumber = 15537393;
uint32 constant testPrevBlockNumber = 15537152;
bytes32 constant testBlockHash = bytes32(hex"55b11b918355b1ef9c5db810302ebad0bf2544255b530cdce90674d5887bb286");
bytes32 constant testPrevHash = bytes32(hex"a9d44102e2414cef64b15e650b841ab630b772b733e30d1019d91d168e415468");
bytes32 constant testRoot = bytes32(hex"5425b718c94550877486f0b9b52d01425c1e6262e5d6a5402e9eb8344e4239c7");
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
            bytes32(0x2b3ea3cd4befcab070812443affb08bf17a91ce382c714a536ca3cacab82278b),
            bytes32(0xb2963b40c8811b7659c2425d357daa4165c5710493ab4cf0293d30d98a621c53),
            bytes32(0x7d0ee8935eb7043fa21a29a90a734165170dd8aafbec8628c3d94b006a8efb75),
            bytes32(0x6296f8a7f7225045ea4e812d5fc4352861d1069eaef2ff7896adc2445803eee6),
            bytes32(0xf7b917c02728fd0513d726200a4169b9c3558a0b1b86d01f9a6d85c4494e4901),
            bytes32(0x933c8f3e40ca3f46a8c4d64557ff7d8b9b7007890d86e01a7de68cc27dba4bdc),
            bytes32(0xc5a9564ad180dfc461af09fb31d537bcca46f71959041bd572c60b847e171b5b),
            bytes32(0x456fb200c357e2247a22a43756c7775a1a7a899024c18686673e003817eec534),
            bytes32(0xb11f638166e5dbfea2261971c9d4a8a2008eea043cd4b1074f8ad727b1f14ce6),
            bytes32(0x3b506100b1b0de2e657521e4c43d1a41dfeb4ac189139de5d7f4d99fa0672acb)
        ];
        Axiom.BlockHashWitness memory block = Axiom.BlockHashWitness({
            blockNumber: testBlockNumber,
            claimedBlockHash: testBlockHash,
            prevHash: testPrevHash,
            numFinal: 0,
            merkleProof: blockMerkleProof
        });
        uint256 prevRandao = 0x4cbec03dddd4b939730a7fe6048729604d4266e82426d472a2b2024f3cc4043f;

        // Call verify function in app
        app.verifyRandao(block, prevRandao, blockRlpPrev, blockRlpPost);
    }
}