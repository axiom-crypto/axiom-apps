// SPDX-License-Identifier: MIT
// WARNING! This smart contract and the associated zk-SNARK verifiers have not been audited.
// DO NOT USE THIS CONTRACT FOR PRODUCTION
pragma solidity 0.8.19;

import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {IAxiomV1Query} from "axiom-contracts/contracts/interfaces/IAxiomV1Query.sol";
import "utils/RLPReader.sol";

contract UniswapV2Twap is Ownable {
    using RLPReader for RLPReader.RLPItem;
    using RLPReader for RLPReader.Iterator;
    using RLPReader for bytes;

    address public axiomQueryAddress;
    mapping(bytes28 => uint256) public twapPris;

    event UniswapV2TwapProof(
        address pairAddress,
        uint32 startBlockNumber,
        uint32 endBlockNumber,
        uint256 twapPri
    );
    event UpdateAxiomAddress(address newAddress);

    constructor(address _axiomQueryAddress) {
        axiomQueryAddress = _axiomQueryAddress;
    }

    function updateAxiomQueryAddress(
        address _axiomQueryAddress
    ) external onlyOwner {
        axiomQueryAddress = _axiomQueryAddress;
        emit UpdateAxiomAddress(_axiomQueryAddress);
    }

    function _getTimestampFromBlock(
        uint32 blockNumber,
        bytes32 blockHash,
        bytes memory rlpEncodedHeader
    ) internal pure returns (uint256) {
        require(keccak256(rlpEncodedHeader) == blockHash, "invalid blockhash");

        RLPReader.RLPItem[] memory ls = rlpEncodedHeader.toRlpItem().toList();
        require(blockNumber == ls[8].toUint(), "invalid block number");
        uint256 timestamp = ls[11].toUint();
        return timestamp;
    }

    function _currentCumulativePrice(
        uint112 reserve0,
        uint112 reserve1,
        uint256 blockTimestamp,
        uint32 blockTimestampLast,
        uint priceCumulativeLast
    ) internal pure returns (uint256) {
        //overflow is desired
        unchecked {
            uint256 increment = uint(reserve1 / reserve0) *
                (blockTimestamp - blockTimestampLast);
            return increment + priceCumulativeLast;
        }
    }

    function _unpackReserveValues(
        uint256 slot
    ) internal pure returns (uint112, uint112, uint32) {
        uint112 reserve0 = uint112(slot >> 144);
        uint112 reserve1 = uint112(slot >> 32);
        uint32 blockTimestampLast = uint32(slot);
        return (reserve0, reserve1, blockTimestampLast);
    }

    function calculateUniswapV2Twap(
        IAxiomV1Query.StorageResponse[] calldata storageProofs,
        IAxiomV1Query.BlockResponse[] calldata blockProofs,
        bytes[2] calldata rlpEncodedHeaders,
        bytes32[3] calldata keccakResponses
    ) public returns (uint256) {
        require(
            storageProofs[0].slot == 8 && storageProofs[2].slot == 8,
            "invalid reserve slot"
        );
        require(
            storageProofs[1].slot == 10 && storageProofs[3].slot == 10,
            "invalid cumulative price slot"
        );
        require(
            storageProofs[0].blockNumber == storageProofs[1].blockNumber &&
                storageProofs[0].blockNumber == blockProofs[0].blockNumber,
            "inconsistent block number"
        );
        require(
            storageProofs[2].blockNumber == storageProofs[3].blockNumber &&
                storageProofs[2].blockNumber == blockProofs[1].blockNumber,
            "inconsistent block number"
        );
        require(
            storageProofs[0].addr == storageProofs[1].addr &&
                storageProofs[2].addr == storageProofs[3].addr &&
                storageProofs[0].addr == storageProofs[2].addr,
            "inconsistent pair address"
        );
        require(
            IAxiomV1Query(axiomQueryAddress).areResponsesValid(
                keccakResponses[0],
                keccakResponses[1],
                keccakResponses[2],
                blockProofs,
                new IAxiomV1Query.AccountResponse[](0),
                storageProofs
            ),
            "invalid proofs"
        );

        uint256 blockTimestamp_k1 = _getTimestampFromBlock(
            blockProofs[0].blockNumber,
            blockProofs[0].blockHash,
            rlpEncodedHeaders[0]
        );

        uint256 blockTimestamp_k2 = _getTimestampFromBlock(
            blockProofs[1].blockNumber,
            blockProofs[1].blockHash,
            rlpEncodedHeaders[1]
        );

        (
            uint112 reserve0_k1,
            uint112 reserve1_k1,
            uint32 blockTimestampLast_k1
        ) = _unpackReserveValues(storageProofs[0].value);

        (
            uint112 reserve0_k2,
            uint112 reserve1_k2,
            uint32 blockTimestampLast_k2
        ) = _unpackReserveValues(storageProofs[2].value);

        uint256 currentCumulativePrice_k1 = _currentCumulativePrice(
            reserve0_k1,
            reserve1_k1,
            blockTimestamp_k1,
            blockTimestampLast_k1,
            storageProofs[1].value
        );

        uint256 currentCumulativePrice_k2 = _currentCumulativePrice(
            reserve0_k2,
            reserve1_k2,
            blockTimestamp_k2,
            blockTimestampLast_k2,
            storageProofs[3].value
        );

        uint256 twap = (currentCumulativePrice_k2 - currentCumulativePrice_k1) /
            (blockTimestamp_k2 - blockTimestamp_k1);

        twapPris[
            bytes28(
                abi.encodePacked(
                    storageProofs[0].addr,
                    blockProofs[0].blockNumber,
                    blockProofs[1].blockNumber
                )
            )
        ] = twap;

        emit UniswapV2TwapProof(
            storageProofs[0].addr,
            blockProofs[0].blockNumber,
            blockProofs[1].blockNumber,
            twap
        );

        return twap;
    }
}
