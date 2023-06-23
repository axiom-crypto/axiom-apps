// SPDX-License-Identifier: MIT
// WARNING! This smart contract and the associated zk-SNARK verifiers have not been audited.
// DO NOT USE THIS CONTRACT FOR PRODUCTION
pragma solidity ^0.8.12;

import {IAxiomV1Query} from "axiom-contracts/contracts/interfaces/IAxiomV1Query.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {RLPReader} from "utils/RLPReader.sol";

contract Randao is Ownable {
    using RLPReader for RLPReader.RLPItem;
    using RLPReader for bytes;

    address public axiomQueryAddress;
    uint32 MERGE_BLOCK = 15537393;

    // mapping between blockNumber and prevRandao
    mapping(uint32 => uint256) public prevRandaos;

    event RandaoProof(uint32 blockNumber, uint256 prevRandao);

    event UpdateAxiomQueryAddress(address newAddress);

    constructor(address _axiomQueryAddress) {
        axiomQueryAddress = _axiomQueryAddress;
    }

    function updateAxiomAddress(address _axiomQueryAddress) external onlyOwner {
        axiomQueryAddress = _axiomQueryAddress;
        emit UpdateAxiomQueryAddress(_axiomQueryAddress);
    }

    function _getRandaoFromBlock(
        uint32 blockNumber,
        bytes32 blockHash,
        bytes memory rlpEncodedHeader
    ) internal pure returns (uint256) {
        require(keccak256(rlpEncodedHeader) == blockHash, "invalid blockhash");

        RLPReader.RLPItem[] memory ls = rlpEncodedHeader.toRlpItem().toList();
        require(blockNumber == ls[8].toUint(), "invalid block number");
        uint256 randao = ls[13].toUint();
        return randao;
    }

    function verifyRandao(
        IAxiomV1Query.BlockResponse[] calldata blockResponses,
        bytes calldata header,
        bytes32[3] calldata keccakResponses
    ) external {
        require(blockResponses.length == 1, "invalid blockResponses length");
        require(
            IAxiomV1Query(axiomQueryAddress).areResponsesValid(
                keccakResponses[0],
                keccakResponses[1],
                keccakResponses[2],
                blockResponses,
                new IAxiomV1Query.AccountResponse[](0),
                new IAxiomV1Query.StorageResponse[](0)
            ),
            "invalid proofs"
        );
        uint256 prevRandao = _getRandaoFromBlock(
            blockResponses[0].blockNumber,
            blockResponses[0].blockHash,
            header
        );

        prevRandaos[blockResponses[0].blockNumber] = prevRandao;
        emit RandaoProof(blockResponses[0].blockNumber, prevRandao);
    }
}
