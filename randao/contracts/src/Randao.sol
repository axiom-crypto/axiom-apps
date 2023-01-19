// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../test/MockAxiom.sol";

uint8 constant TREE_DEPTH = 10;

contract Randao {
    address blockCache;

    // mapping between blockNumber (32) and prevRandao (256)
    mapping(uint32 => uint256) public prevRandaos;

    event RandaoProof(uint32 blockNumber, uint256 prevRandao);

    struct BlockHashWitness {
        uint32 blockNumber;
        bytes32 claimedBlockHash;
        bytes32 prevHash;
        uint32 numFinal;
        bytes32[TREE_DEPTH] merkleProof;
    }

    constructor(address _blockCache) {
        blockCache = _blockCache;
    }

    function verifyRandao(
        BlockHashWitness memory block,
        uint256 prevRandao,
        bytes calldata prevBlockRlp,
        bytes calldata postBlockRlp
    ) public {
        require(
            MockAxiom(blockCache).isBlockHashValid(
                block.blockNumber,
                block.claimedBlockHash,
                block.prevHash,
                block.numFinal,
                block.merkleProof
            ),
            "Invalid block hash in cache"
        );
        require(
            keccak256(abi.encodePacked(prevBlockRlp, prevRandao, postBlockRlp)) ==
                block.claimedBlockHash,
            "Block hash does not match witness hash"
        );

        emit RandaoProof(block.blockNumber, prevRandao);
        prevRandaos[block.blockNumber] = prevRandao;
    }
}