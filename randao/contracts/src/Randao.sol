// SPDX-License-Identifier: MIT
// WARNING! This smart contract and the associated zk-SNARK verifiers have not been audited.
// DO NOT USE THIS CONTRACT FOR PRODUCTION
pragma solidity ^0.8.12;

import "./lib/RLPReader.sol";
import {IAxiomV0} from "./IAxiomV0.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";

contract Randao is Ownable {
    using RLPReader for RLPReader.RLPItem;
    using RLPReader for bytes;

    address public axiomAddress;
    uint32 MERGE_BLOCK = 15537393;

    // mapping between blockNumber and prevRandao
    mapping(uint32 => uint256) public prevRandaos;

    event RandaoProof(uint32 blockNumber, uint256 prevRandao);

    event UpdateAxiomAddress(address newAddress);

    constructor(address _axiomAddress) {
        axiomAddress = _axiomAddress;
    }

    function updateAxiomAddress(address _axiomAddress) external onlyOwner {
        axiomAddress = _axiomAddress;
        emit UpdateAxiomAddress(_axiomAddress);
    }

    function verifyRandao(IAxiomV0.BlockHashWitness calldata witness, bytes calldata header) external {
        if (block.number - witness.blockNumber <= 256) {
            require(
                IAxiomV0(axiomAddress).isRecentBlockHashValid(witness.blockNumber, witness.claimedBlockHash),
                "Block hash was not validated in cache"
            );
        } else {
            require(IAxiomV0(axiomAddress).isBlockHashValid(witness), "Block hash was not validated in cache");
        }

        require(keccak256(header) == witness.claimedBlockHash, "Block hash does not match witness hash");

        require(witness.blockNumber > MERGE_BLOCK, "prevRandao is not valid before merge block");

        RLPReader.RLPItem[] memory headerItems = header.toRlpItem().toList();
        uint256 prevRandao = headerItems[13].toUint();

        prevRandaos[witness.blockNumber] = prevRandao;
        emit RandaoProof(witness.blockNumber, prevRandao);
    }
}
