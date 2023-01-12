// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

contract MockBlockCache {
    mapping(uint => uint) public cache;

    function setBlockHash(uint256 number, uint256 hash) public {
        cache[number] = hash;
    }

    function getBlockHash(uint256 number) public view returns (uint256) {
        return cache[number];
    }
}
