// SPDX-License-Identifier: MIT
// WARNING! This smart contract and the associated zk-SNARK verifiers have not been audited.
// DO NOT USE THIS CONTRACT FOR PRODUCTION
pragma solidity ^0.8.12;

import {IAxiomV0} from "./IAxiomV0.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {IUniswapV2Twap} from "./IUniswapV2Twap.sol";

contract UniswapV2Twap is Ownable, IUniswapV2Twap {
    uint256 public constant VERSION = 1;

    address public axiomAddress;
    address public verifierAddress;

    // mapping between abi.encodePacked(address poolAddress, uint32 startBlockNumber, uint32 endBlockNumber) => twapPri (uint256)
    mapping(bytes28 => uint256) public twapPris;

    event UpdateAxiomAddress(address newAddress);
    event UpdateSnarkVerifierAddress(address newAddress);

    constructor(address _axiomAddress, address _verifierAddress) {
        axiomAddress = _axiomAddress;
        verifierAddress = _verifierAddress;
    }

    function updateAxiomAddress(address _axiomAddress) external onlyOwner {
        axiomAddress = _axiomAddress;
        emit UpdateAxiomAddress(_axiomAddress);
    }

    function updateSnarkVerifierAddress(address _verifierAddress) external onlyOwner {
        verifierAddress = _verifierAddress;
        emit UpdateSnarkVerifierAddress(_verifierAddress);
    }

    // The public inputs and outputs of the ZK proof
    struct Instance {
        address pairAddress;
        uint32 startBlockNumber;
        uint32 endBlockNumber;
        bytes32 startBlockHash;
        bytes32 endBlockHash;
        uint256 twapPri;
    }

    function getProofInstance(bytes calldata proof) internal pure returns (Instance memory instance) {
        // Public instances: total 6 field elements
        // * 0: `pair_address . start_block_number . end_block_number` is `20 + 4 + 4 = 28` bytes, packed into a single field element
        // * 1..3: `start_block_hash` (32 bytes) is split into two field elements (hi, lo u128)
        // * 3..5: `end_block_hash` (32 bytes) is split into two field elements (hi, lo u128)
        // * 5: `twap_pri` (32 bytes) is single field element representing the computed TWAP
        bytes32[6] memory fieldElements;
        // The first 4 * 3 * 32 bytes give two elliptic curve points for internal pairing check
        uint256 start = 384;
        for (uint256 i = 0; i < 6; i++) {
            fieldElements[i] = bytes32(proof[start:start + 32]);
            start += 32;
        }
        instance.pairAddress = address(bytes20(fieldElements[0] << 32)); // 4 * 8, bytes is right padded so conversion is from left
        instance.startBlockNumber = uint32(bytes4(fieldElements[0] << 192)); // 24 * 8
        instance.endBlockNumber = uint32(bytes4(fieldElements[0] << 224)); // 28 * 8
        instance.startBlockHash = bytes32((uint256(fieldElements[1]) << 128) | uint128(uint256(fieldElements[2])));
        instance.endBlockHash = bytes32((uint256(fieldElements[3]) << 128) | uint128(uint256(fieldElements[4])));
        instance.twapPri = uint256(fieldElements[5]);
    }

    function validateBlockHash(IAxiomV0.BlockHashWitness calldata witness) internal view {
        if (block.number - witness.blockNumber <= 256) {
            if (!IAxiomV0(axiomAddress).isRecentBlockHashValid(witness.blockNumber, witness.claimedBlockHash)) {
                revert("BlockHashWitness is not validated by Axiom");
            }
        } else {
            if (!IAxiomV0(axiomAddress).isBlockHashValid(witness)) {
                revert("BlockHashWitness is not validated by Axiom");
            }
        }
    }

    function verifyUniswapV2Twap(
        IAxiomV0.BlockHashWitness calldata startBlock,
        IAxiomV0.BlockHashWitness calldata endBlock,
        bytes calldata proof
    ) external returns (uint256) {
        Instance memory instance = getProofInstance(proof);
        // compare calldata vs proof instances:
        if (instance.startBlockNumber > instance.endBlockNumber) {
            revert("startBlockNumber <= endBlockNumber");
        }
        if (instance.startBlockNumber != startBlock.blockNumber) {
            revert("instance.startBlockNumber != startBlock.blockNumber");
        }
        if (instance.endBlockNumber != endBlock.blockNumber) {
            revert("instance.endBlockNumber != endBlock.blockNumber");
        }
        if (instance.startBlockHash != startBlock.claimedBlockHash) {
            revert("instance.startBlockHash != startBlock.claimedBlockHash");
        }
        if (instance.endBlockHash != endBlock.claimedBlockHash) {
            revert("instance.endBlockHash != endBlock.claimedBlockHash");
        }
        // Use Axiom to validate block hashes
        validateBlockHash(startBlock);
        validateBlockHash(endBlock);

        (bool success,) = verifierAddress.call(proof);
        if (!success) {
            revert("Proof verification failed");
        }
        twapPris[bytes28(abi.encodePacked(instance.pairAddress, instance.startBlockNumber, instance.endBlockNumber))] =
            instance.twapPri;
        emit UniswapV2TwapProof(instance.pairAddress, startBlock.blockNumber, endBlock.blockNumber, instance.twapPri);
        return instance.twapPri;
    }
}
