// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "./Axiom.sol";

uint8 constant SLOT_NUMBER = 10;

contract AxiomStoragePf {
    address private axiomAddress;
    address private verifierAddress;

    bytes32[] public slotAttestations;

    event SlotAttestationEvent(
        uint32 blockNumber,
        address addr,
        uint256 slot,
        uint256 slotValue
    );

    constructor(address _axiomAddress, address _verifierAddress) {
        axiomAddress = _axiomAddress;
        verifierAddress = _verifierAddress;
    }

    function attestSlots(
        Axiom.BlockHashWitness calldata blockData,
        bytes calldata proof
    ) external returns (uint256) {
        require(
            Axiom(axiomAddress).isBlockHashValid(
                blockData.blockNumber,
                blockData.claimedBlockHash,
                blockData.prevHash,
                blockData.numFinal,
                blockData.merkleProof
            ),
            "Invalid block hash in cache"
        );

        // Extract instances from proof
        uint256 _blockHash     = (uint256(bytes32(proof[384       : 384 +  32])) << 128) | 
                                  uint128(bytes16(proof[384 +  48 : 384 +  64]));   
        uint256 _blockNumber   =  uint256(bytes32(proof[384 +  64 : 384 +  96]));
        address account        =  address(bytes20(proof[384 + 108 : 384 + 128]));

        // Check block hash and block number
        require(_blockHash == uint256(blockData.claimedBlockHash), "Invalid block hash in instance");
        require(_blockNumber == blockData.blockNumber, "Invalid block number in instance");

        (bool success, ) = verifierAddress.call(proof);
        if (!success) {
            revert("Proof verification failed");        
        }

        for (uint16 i = 0; i < SLOT_NUMBER; i++) {
            uint256 slot      = (uint256(bytes32(proof[384 + 128 + 128 * i : 384 + 160 + 128 * i])) << 128) |
                                 uint128(bytes16(proof[384 + 176 + 128 * i : 384 + 192 + 128 * i]));
            uint256 slotValue = (uint256(bytes32(proof[384 + 192 + 128 * i : 384 + 224 + 128 * i])) << 128) |
                                 uint128(bytes16(proof[384 + 240 + 128 * i : 384 + 256 + 128 * i]));
            slotAttestations.push(
                keccak256(abi.encodePacked(uint32(_blockNumber), account, slot, slotValue))
            );
            emit SlotAttestationEvent(uint32(_blockNumber), account, slot, slotValue);                                 
        }
        return slotAttestations.length - 1;
    }
}
