// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IAxiomV1} from "axiom-contracts/contracts/interfaces/IAxiomV1.sol";

interface IRandao {
    function prevRandaos(uint32 blockNumber) external view returns (uint256);
    function axiomAddress() external view returns (address);
    function mergeBlock() external view returns (uint32);

    function updateAxiomAddress(address _axiomAddress) external;
    function verifyRandao(IAxiomV1.BlockHashWitness calldata witness, bytes calldata header) external;
}