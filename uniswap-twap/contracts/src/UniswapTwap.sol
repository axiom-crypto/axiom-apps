// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../test/MockAxiom.sol";

uint8 constant TREE_DEPTH = 10;

contract UniswapTwap {
    address plonkVerifier;
    address blockCache;

    // mapping between packed [startBlockNumber (32) || endBlockNumber (32)] and twapPri
    mapping(uint64 => uint256) public twapPris;

    event UniswapTwapProof(uint32 startBlockNumber, uint32 endBlockNumber, uint256 twapPri);

    struct BlockHashWitness {
        uint32 blockNumber;
        bytes32 claimedBlockHash;
        bytes32 prevHash;
        uint32 numFinal;
        bytes32[TREE_DEPTH] merkleProof;
    }

    constructor(address _plonkVerifier, address _blockCache) {
        plonkVerifier = _plonkVerifier;
        blockCache = _blockCache;
    }

    function verifyUniswapTwap(
        BlockHashWitness memory startBlock,
        BlockHashWitness memory endBlock,
        uint256 twapPri,
        bytes calldata proof
    ) public {
        require(
            MockAxiom(blockCache).isBlockHashValid(
                startBlock.blockNumber,
                startBlock.claimedBlockHash,
                startBlock.prevHash,
                startBlock.numFinal,
                startBlock.merkleProof
            ),
            "Invalid starting block hash in cache"
        );
        require(
            MockAxiom(blockCache).isBlockHashValid(
                endBlock.blockNumber,
                endBlock.claimedBlockHash,
                endBlock.prevHash,
                endBlock.numFinal,
                endBlock.merkleProof
            ),
            "Invalid ending block hash in cache"
        );

        // Extract instances from proof 
        uint256 _startBlockHash   = uint256(bytes32(proof[384    :384+32 ])) << 128 | 
                                            uint128(bytes16(proof[384+48 :384+64 ]));
        uint256 _endBlockHash     = uint256(bytes32(proof[384+64 :384+96 ])) << 128 | 
                                            uint128(bytes16(proof[384+112:384+128]));
        uint256 _startBlockNumber = uint256(bytes32(proof[384+128:384+160]));
        uint256 _endBlockNumber   = uint256(bytes32(proof[384+160:384+192]));
        uint256 _twapPri          = uint256(bytes32(proof[384+192:384+224]));

        // Check instance values
        if (_startBlockHash != uint256(startBlock.claimedBlockHash)) {
            revert("Invalid startBlockHash in instance");
        }
        if (_endBlockHash != uint256(endBlock.claimedBlockHash)) {
            revert("Invalid endBlockHash in instance");
        }
        if (_startBlockNumber != startBlock.blockNumber) {
            revert("Invalid startBlockNumber");
        }
        if (_endBlockNumber != endBlock.blockNumber) {
            revert("Invalid endBlockNumber");
        }        
        if (_twapPri != twapPri) {
            revert("Invalid twapPri");
        }

        (bool success, ) = plonkVerifier.call(proof);
        if (!success) {
            revert("Plonk verification failed");
        }
        emit UniswapTwapProof(startBlock.blockNumber, endBlock.blockNumber, twapPri);
        twapPris[uint64(uint64(startBlock.blockNumber) << 32 | endBlock.blockNumber)] = _twapPri;
    }
}