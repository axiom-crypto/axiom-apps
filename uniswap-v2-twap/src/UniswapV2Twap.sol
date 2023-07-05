// SPDX-License-Identifier: MIT
// WARNING! This smart contract has not been audited.
// DO NOT USE THIS CONTRACT FOR PRODUCTION
// This is an example contract to demonstrate how to integrate an application with the audited production release of AxiomV1 and AxiomV1Query.
pragma solidity 0.8.19;

import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {IAxiomV1Query} from "axiom-contracts/contracts/interfaces/IAxiomV1Query.sol";
import "utils/RLPReader.sol";
import "utils/UQ112x112.sol";

contract UniswapV2Twap is Ownable {
    using RLPReader for RLPReader.RLPItem;
    using RLPReader for RLPReader.Iterator;
    using RLPReader for bytes;
    using UQ112x112 for uint224;

    address public axiomQueryAddress;
    mapping(bytes28 => uint256) public twapPris;

    event UniswapV2TwapProof(address pairAddress, uint32 startBlockNumber, uint32 endBlockNumber, uint256 twapPri);

    event UpdateAxiomQueryAddress(address newAddress);

    constructor(address _axiomQueryAddress) {
        axiomQueryAddress = _axiomQueryAddress;
        emit UpdateAxiomQueryAddress(_axiomQueryAddress);
    }

    function updateAxiomQueryAddress(address _axiomQueryAddress) external onlyOwner {
        axiomQueryAddress = _axiomQueryAddress;
        emit UpdateAxiomQueryAddress(_axiomQueryAddress);
    }

    function _getTimestampFromBlock(uint32 blockNumber, bytes32 blockHash, bytes memory rlpEncodedHeader)
        internal
        pure
        returns (uint256)
    {
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
        uint256 price1CumulativeLast
    ) internal pure returns (uint256) {
        unchecked {
            uint32 timeElapsed = uint32(blockTimestamp) - blockTimestampLast; // overflow is desired
            uint256 increment =
                uint256(UQ112x112.encode(reserve1).uqdiv(reserve0)) * timeElapsed;
            return increment + price1CumulativeLast;
        }
    }

    // slot is structured as follows:
    // blockTimestampLast (32) . reserves1 (112) . reserves0 (112)
    function _unpackReserveValues(uint256 slot) internal pure returns (uint112, uint112, uint32) {
        uint112 reserve0 = uint112(slot >> 144);
        uint112 reserve1 = uint112(slot >> 32);
        uint32 blockTimestampLast = uint32(slot);
        return (reserve0, reserve1, blockTimestampLast);
    }

    /*  | Name                 | Type                                            | Slot | Offset | Bytes | Contract                                  |
        |----------------------|-------------------------------------------------|------|--------|-------|-------------------------------------------|
        | totalSupply          | uint256                                         | 0    | 0      | 32    | contracts/UniswapV2Pair.sol:UniswapV2Pair |
        | balanceOf            | mapping(address => uint256)                     | 1    | 0      | 32    | contracts/UniswapV2Pair.sol:UniswapV2Pair |
        | allowance            | mapping(address => mapping(address => uint256)) | 2    | 0      | 32    | contracts/UniswapV2Pair.sol:UniswapV2Pair |
        | DOMAIN_SEPARATOR     | bytes32                                         | 3    | 0      | 32    | contracts/UniswapV2Pair.sol:UniswapV2Pair |
        | nonces               | mapping(address => uint256)                     | 4    | 0      | 32    | contracts/UniswapV2Pair.sol:UniswapV2Pair |
        | factory              | address                                         | 5    | 0      | 20    | contracts/UniswapV2Pair.sol:UniswapV2Pair |
        | token0               | address                                         | 6    | 0      | 20    | contracts/UniswapV2Pair.sol:UniswapV2Pair |
        | token1               | address                                         | 7    | 0      | 20    | contracts/UniswapV2Pair.sol:UniswapV2Pair |
        | reserve0             | uint112                                         | 8    | 0      | 14    | contracts/UniswapV2Pair.sol:UniswapV2Pair |
        | reserve1             | uint112                                         | 8    | 14     | 14    | contracts/UniswapV2Pair.sol:UniswapV2Pair |
        | blockTimestampLast   | uint32                                          | 8    | 28     | 4     | contracts/UniswapV2Pair.sol:UniswapV2Pair |
        | price0CumulativeLast | uint256                                         | 9    | 0      | 32    | contracts/UniswapV2Pair.sol:UniswapV2Pair |
        | price1CumulativeLast | uint256                                         | 10   | 0      | 32    | contracts/UniswapV2Pair.sol:UniswapV2Pair |
        | kLast                | uint256                                         | 11   | 0      | 32    | contracts/UniswapV2Pair.sol:UniswapV2Pair |
        | unlocked             | uint256                                         | 12   | 0      | 32    | contracts/UniswapV2Pair.sol:UniswapV2Pair | 
    */

    function calculateUniswapV2Twap(
        IAxiomV1Query.StorageResponse[] calldata storageProofs,
        IAxiomV1Query.BlockResponse[] calldata blockProofs,
        bytes[2] calldata rlpEncodedHeaders,
        bytes32[3] calldata keccakResponses
    ) public returns (uint256) {
        require(storageProofs[0].slot == 8 && storageProofs[2].slot == 8, "invalid reserve slot");
        require(storageProofs[1].slot == 10 && storageProofs[3].slot == 10, "invalid cumulative price slot");
        require(
            storageProofs[0].blockNumber == storageProofs[1].blockNumber
                && storageProofs[0].blockNumber == blockProofs[0].blockNumber,
            "inconsistent block number"
        );
        require(
            storageProofs[2].blockNumber == storageProofs[3].blockNumber
                && storageProofs[2].blockNumber == blockProofs[1].blockNumber,
            "inconsistent block number"
        );
        require(
            storageProofs[0].addr == storageProofs[1].addr && storageProofs[0].addr == storageProofs[2].addr
                && storageProofs[0].addr == storageProofs[3].addr,
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

        uint256 blockTimestamp_k1 =
            _getTimestampFromBlock(blockProofs[0].blockNumber, blockProofs[0].blockHash, rlpEncodedHeaders[0]);

        uint256 blockTimestamp_k2 =
            _getTimestampFromBlock(blockProofs[1].blockNumber, blockProofs[1].blockHash, rlpEncodedHeaders[1]);

        (uint112 reserve0_k1, uint112 reserve1_k1, uint32 blockTimestampLast_k1) =
            _unpackReserveValues(storageProofs[0].value);

        (uint112 reserve0_k2, uint112 reserve1_k2, uint32 blockTimestampLast_k2) =
            _unpackReserveValues(storageProofs[2].value);

        uint256 currentCumulativePrice_k1 = _currentCumulativePrice(
            reserve0_k1, reserve1_k1, blockTimestamp_k1, blockTimestampLast_k1, storageProofs[1].value
        );

        uint256 currentCumulativePrice_k2 = _currentCumulativePrice(
            reserve0_k2, reserve1_k2, blockTimestamp_k2, blockTimestampLast_k2, storageProofs[3].value
        );

        uint256 twap = (currentCumulativePrice_k2 - currentCumulativePrice_k1) / (blockTimestamp_k2 - blockTimestamp_k1);

        twapPris[bytes28(
            abi.encodePacked(storageProofs[0].addr, blockProofs[0].blockNumber, blockProofs[1].blockNumber)
        )] = twap;

        emit UniswapV2TwapProof(storageProofs[0].addr, blockProofs[0].blockNumber, blockProofs[1].blockNumber, twap);

        return twap;
    }
}
