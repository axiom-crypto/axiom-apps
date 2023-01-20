// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@axiom/src/Axiom.sol";

contract Randao {
    address axiomAddress;

    // mapping between blockNumber (32) and prevRandao (256)
    mapping(uint32 => uint256) public prevRandaos;

    event RandaoProof(uint32 blockNumber, uint256 prevRandao);

    constructor(address _axiomAddress) {
        axiomAddress = _axiomAddress;
    }

    function verifyRandao(
        Axiom.BlockHashWitness memory blockProof,
        uint256 prevRandao,
        bytes calldata prevBlockRlp,
        bytes calldata postBlockRlp
    ) public {
        require(
            Axiom(axiomAddress).isBlockHashValid(
                blockProof.blockNumber,
                blockProof.claimedBlockHash,
                blockProof.prevHash,
                blockProof.numFinal,
                blockProof.merkleProof
            ),
            "Invalid block hash in cache"
        );
        require(
            keccak256(abi.encodePacked(prevBlockRlp, prevRandao, postBlockRlp)) ==
                blockProof.claimedBlockHash,
            "Block hash does not match witness hash"
        );

        emit RandaoProof(blockProof.blockNumber, prevRandao);
        prevRandaos[blockProof.blockNumber] = prevRandao;
    }
}