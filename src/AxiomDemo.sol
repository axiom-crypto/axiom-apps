// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./Axiom.sol";

contract AxiomDemo is Axiom {
    constructor(
        address _verifierAddress, 
        address _historicalVerifierAddress, 
        uint32 specialBlockNumber, 
        bytes32 specialBlockHash
    ) Axiom(_verifierAddress, _historicalVerifierAddress) {
        historicalRoots[specialBlockNumber] = specialBlockHash;
    }

    function setBlockRoot(uint32 blockNumber, bytes32 root) public {
        historicalRoots[blockNumber] = root;
    }

    fallback() external payable {}
}
