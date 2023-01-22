// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "@axiom/src/AxiomDemo.sol";
import "../lib/YulDeployer.sol";
import "../src/UniswapTwap.sol";

uint32 constant startBlockNumber = 16008555;
uint32 constant endBlockNumber = 16431426;
bytes32 constant startBlockHash = bytes32(hex"4cc24ed848c5d1243ac65af84470d38ed339a6ae85d88896a326d08c07cbb4d5");
bytes32 constant startPrevBlockHash = bytes32(hex"e572e95c36d40a1bcdd318505897d61725057fa58c06c16141df4f2498c467a3");
bytes32 constant startRoot = bytes32(0x39e7bd3c8f49a0f269491757e0554590d88d5c4b8d6e7760b538db7cd127c306);
bytes32 constant endBlockHash = bytes32(hex"ab5c0c98cb198a6d012a7d4f640750ca3e03e04f386dba0a2a4a7d95b10da8e1");  
bytes32 constant endPrevBlockHash = bytes32(hex"b4592ca206dd2bd848fa1609b4d750ee0e8485bb26dc795fa83428ff1fe53f65");
bytes32 constant endRoot = bytes32(0x33e267091c0aa8884dda8d0f54d5ebfd3057fa63bc4ad14ce5432d9d9aa842f3);
uint32 constant testNumFinal = 0;

contract UniswapTwapTest is Test {
    AxiomDemo public axiom;
    YulDeployer yulDeployer;    
    UniswapTwap app;

    function setUp() public {
        yulDeployer = new YulDeployer();
        address uniswapTwapAddress = address(yulDeployer.deployContract("PlonkVerifier"));
        address axiomVerifierAddress = address(yulDeployer.deployContract("mainnet_10_7"));

        axiom = new AxiomDemo(
            axiomVerifierAddress,
            axiomVerifierAddress,
            startBlockNumber - (startBlockNumber % 1024), 
            keccak256(abi.encodePacked(startPrevBlockHash, startRoot, testNumFinal))        
        );
        axiom.setBlockRoot(endBlockNumber - (endBlockNumber % 1024), 
                           keccak256(abi.encodePacked(endPrevBlockHash, endRoot, testNumFinal)));
        app = new UniswapTwap(uniswapTwapAddress, address(axiom));
    }    

    function testVerifyTwapPri() public {
        // Import test proof and instance calldata
        string[] memory inputs = new string[](2);
        inputs[0] = "cat";
        inputs[1] = "test/data/test.calldata";
        bytes memory proof = vm.ffi(inputs);

        // Prepare witness data for Uniswap TWAP proof.
        bytes32[10] memory startBlockMerkleProof = [
            bytes32(0x9fa8a9e1c8011b09815b79f632cbe6273e6180782e05b2aa5c5ae3b55a78eb3f),
            bytes32(0xf771cb2a22b794fb30299e72624b8329ed6ca2d31a74e35dc2d8db47c91022b1),
            bytes32(0xfa76230ed23c44be9f022e815ec0b440ddd261ff1e702e1ba8261f289deb060e),
            bytes32(0x241a1dbd674767ee4a6e4bc0433733220f9a3ff3b2dbc96b70074288d887698c),
            bytes32(0x0acf3d81bc722149b62552f3d591c6d69c81234e53aac03e2f6932276d4e79da),
            bytes32(0x71b4edab1bbdc9128e70fb21b5c6e83296e1be05ba1cd2110ac92efaec82446a),
            bytes32(0x5d7baa58c56b8765638a7ad713cf3afb33ca430c2b36a2f4ccf8bb4d69cbcbf3),
            bytes32(0x5068bdc8e6b5cdc2615ec7dbadfc0317bd0090a1a8f51a8e84f604090666a499),
            bytes32(0x5f09ffd84b83010f48b93c249b9ed81923cf3d64480c23b2aba2f3dd4c59061f),
            bytes32(0x1450432d9322be042ac59562e0d63139824e204ee21c88dd3fd6f7005a8260c1)                
        ];
        bytes32[10] memory endBlockMerkleProof = [
            bytes32(0x4de5797203d80c53eaf79c0f483dc8c86a72cb0fefcc5b8694520c6ff15d7ef0),
            bytes32(0x6b97a95a878b4bf6cdbf726e47d551a30b825b5503e887f5ec0c153533b96bec),
            bytes32(0xcf2b66f94c502dcdfd87dbd536ed4c4c26c07d1a74fda508cc516b08041c43bf),
            bytes32(0x9494dd9df540679d8d83563543efca6c3a2a7ba032f8e24203fa719bb26eda33),
            bytes32(0xae8bfbd8c0b66d4f2e47ad08b278b62f313f1f7a31f8af903e8a823ec8401499),
            bytes32(0x3d64748e46a8c91340de65d57accea60758d4293d489ac34621fe49cedd611f6),
            bytes32(0xdda807b3cbc2f96fc536f17faec60fb1706e5bb898c17349cc5458b56aba86a8),
            bytes32(0x41518b9cec1bae798ce35c6e1f8356dda36ced7705c552309cadaea1e612736f),
            bytes32(0x6606dae4ba44fa21a961ca8a1b8a6147cdad03fdc94eaf2a5516aec5d71d2279),
            bytes32(0x9e83faf016e6d3ad63b783b1adb0fb9aa3540fc81af8aa3ddcca7ade13295187)                 
        ];
        Axiom.BlockHashWitness memory startBlock = Axiom.BlockHashWitness({
            blockNumber: startBlockNumber,
            claimedBlockHash: startBlockHash,
            prevHash: startPrevBlockHash,
            numFinal: 0,
            merkleProof: startBlockMerkleProof
        });
        Axiom.BlockHashWitness memory endBlock = Axiom.BlockHashWitness({
            blockNumber: endBlockNumber,
            claimedBlockHash: endBlockHash,
            prevHash: endPrevBlockHash,
            numFinal: 0,
            merkleProof: endBlockMerkleProof
        });
        // twapPri in uq112x112 format, test value computed independently
        uint256 twapPri = 0x056a73df806331153e53e2;

        // Call verify function in app
        app.verifyUniswapTwap(startBlock, endBlock, proof);
        require(app.twapPris((uint64(startBlockNumber) << 32) | endBlockNumber) == twapPri, "TwapPri not verified");
    }
}