// SPDX-License-Identifier: MIT
// WARNING! This smart contract and the associated zk-SNARK verifiers have not been audited.
// DO NOT USE THIS CONTRACT FOR PRODUCTION
pragma solidity ^0.8.12;

import {IAxiomV0} from "./IAxiomV0.sol";
import {IAccountAge} from "./IAccountAge.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";

contract AccountAge is Ownable, IAccountAge {
    uint256 public constant VERSION = 1;

    address public axiomAddress;
    address public verifierAddress;

    mapping(address => uint32) public birthBlocks;

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

    // TODO: prevBlock witness is not needed - it is already checked in ZKP
    function verifyAge(
        IAxiomV0.BlockHashWitness calldata prevBlock,
        IAxiomV0.BlockHashWitness calldata currBlock,
        bytes calldata proof
    ) external {
        if (block.number - prevBlock.blockNumber <= 256) {
            if (!IAxiomV0(axiomAddress).isRecentBlockHashValid(prevBlock.blockNumber, prevBlock.claimedBlockHash)) {
                revert("Prev block hash was not validated in cache");
            }
        } else {
            if (!IAxiomV0(axiomAddress).isBlockHashValid(prevBlock)) {
                revert("Prev block hash was not validated in cache");
            }
        }
        if (block.number - currBlock.blockNumber <= 256) {
            if (!IAxiomV0(axiomAddress).isRecentBlockHashValid(currBlock.blockNumber, currBlock.claimedBlockHash)) {
                revert("Curr block hash was not validated in cache");
            }
        } else {
            if (!IAxiomV0(axiomAddress).isBlockHashValid(currBlock)) {
                revert("Curr block hash was not validated in cache");
            }
        }

        // Extract instances from proof
        uint256 _prevBlockHash =
            uint256(bytes32(proof[384:384 + 32])) << 128 | uint128(bytes16(proof[384 + 48:384 + 64]));
        uint256 _currBlockHash =
            uint256(bytes32(proof[384 + 64:384 + 96])) << 128 | uint128(bytes16(proof[384 + 112:384 + 128]));
        uint256 _blockNumber = uint256(bytes32(proof[384 + 128:384 + 160]));
        address account = address(bytes20(proof[384 + 172:384 + 204]));

        // Check instance values
        if (_prevBlockHash != uint256(prevBlock.claimedBlockHash)) {
            revert("Invalid previous block hash in instance");
        }
        if (_currBlockHash != uint256(currBlock.claimedBlockHash)) {
            revert("Invalid current block hash in instance");
        }
        if (_blockNumber != currBlock.blockNumber) {
            revert("Invalid block number");
        }

        // Verify the following statement:
        //   nonce(account, blockNumber - 1) == 0 AND
        //   nonce(account, blockNumber) != 0     AND
        //   codeHash(account, blockNumber) == keccak256([])
        (bool success,) = verifierAddress.call(proof);
        if (!success) {
            revert("Proof verification failed");
        }
        birthBlocks[account] = currBlock.blockNumber;
        emit AccountAgeProof(account, currBlock.blockNumber);
    }
}
