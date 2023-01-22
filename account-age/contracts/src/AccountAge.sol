// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@axiom/src/Axiom.sol";

contract AccountAge {
    address plonkVerifier;
    address axiomAddress;

    mapping(address => uint) public birthBlock;

    constructor(address _plonkVerifier, address _axiomAddress) {
        plonkVerifier = _plonkVerifier;
        axiomAddress = _axiomAddress;
    }

    function verifyAge(
        address account,
        Axiom.BlockHashWitness memory prevBlock,
        Axiom.BlockHashWitness memory currBlock,
        bytes calldata proof
    ) public {
        require(
            Axiom(axiomAddress).isBlockHashValid(
                prevBlock.blockNumber,
                prevBlock.claimedBlockHash,
                prevBlock.prevHash,
                prevBlock.numFinal,
                prevBlock.merkleProof
            ),
            "Invalid previous block hash in cache"
        );
        require(
            Axiom(axiomAddress).isBlockHashValid(
                currBlock.blockNumber,
                currBlock.claimedBlockHash,
                currBlock.prevHash,
                currBlock.numFinal,
                currBlock.merkleProof
            ),
            "Invalid current block hash in cache"
        );

        // Extract instances from proof 
        uint256 _prevBlockHash = uint256(bytes32(proof[384    :384+32 ])) << 128 | 
                                 uint128(bytes16(proof[384+48 :384+64 ]));
        uint256 _currBlockHash = uint256(bytes32(proof[384+64 :384+96 ])) << 128 | 
                                 uint128(bytes16(proof[384+112:384+128]));
        uint256 _blockNumber   = uint256(bytes32(proof[384+128:384+160]));
        address _account       = address(bytes20(proof[384+172:384+204]));

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
        if (_account != account) {
            revert("Invalid account");
        }

        // Verify the following statement: 
        //   nonce(account, blockNumber - 1) == 0 AND 
        //   nonce(account, blockNumber) != 0     AND
        //   codeHash(account, blockNumber) == keccak256([])
        (bool success, ) = plonkVerifier.call(proof);
        if (!success) {
            revert("Plonk verification failed");
        }
        birthBlock[account] = _blockNumber;
    }
}
