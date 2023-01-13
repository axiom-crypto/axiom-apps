// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

contract MockBlockCache {
    mapping(uint => uint) public cache;

    function setBlockHash(uint256 number, uint256 hash) public {
        cache[number] = hash;
    }

    uint8 constant TREE_DEPTH = 4;

    function isBlockHashValid(
        uint32 blockNumber,
        bytes32 claimedBlockHash,
        bytes32 prevHash,
        uint32 numFinal,
        bytes32[TREE_DEPTH] calldata merkleProof
    ) public view returns (bool) {
        // For testing purposes, check only that the claimed block hash is in the cache
        return (cache[blockNumber] == uint256(claimedBlockHash));
    }
}
