// SPDX-License-Identifier: MIT
// WARNING! This smart contract and the associated zk-SNARK verifiers have not been audited.
// DO NOT USE THIS CONTRACT FOR PRODUCTION
pragma solidity ^0.8.12;

import "./IAxiomV0.sol";

contract Randao {
    address private axiomAddress;

    // mapping between blockNumber and prevRandao 
    mapping(uint32 => uint256) public prevRandaos;

    event RandaoProof(uint32 blockNumber, uint256 prevRandao);

    constructor(address _axiomAddress) {
        axiomAddress = _axiomAddress;
    }

    function verifyRandao(
        IAxiomV0.BlockHashWitness memory witness,
        uint256 prevRandao,
        bytes calldata prevBlockRlp,
        bytes calldata postBlockRlp
    ) public {
        if (block.number - witness.blockNumber <= 256) {
            require(IAxiomV0(axiomAddress).isRecentBlockHashValid(witness.blockNumber, witness.claimedBlockHash),
                    "Block hash was not validated in cache");
        } else {
            require(IAxiomV0(axiomAddress).isBlockHashValid(witness),
                    "Block hash was not validated in cache");
        } 

        require(
            keccak256(abi.encodePacked(prevBlockRlp, prevRandao, postBlockRlp)) ==
                witness.claimedBlockHash,
            "Block hash does not match witness hash"
        );

        prevRandaos[witness.blockNumber] = prevRandao;
        emit RandaoProof(witness.blockNumber, prevRandao);        
    }
}