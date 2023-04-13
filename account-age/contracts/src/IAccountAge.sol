// SPDX-License-Identifier: MIT
// WARNING! This smart contract and the associated zk-SNARK verifiers have not been audited.
// DO NOT USE THIS CONTRACT FOR PRODUCTION
pragma solidity ^0.8.12;

import {IAxiomV0} from "./IAxiomV0.sol";

interface IAccountAge {
    /// @notice Mapping between EOA address => block number of first transaction
    function birthBlocks(address) external view returns (uint32);

    event AccountAgeProof(address account, uint32 blockNumber);

    /// @notice Verify a ZK proof of account age using Axiom.
    ///         Caches the account age value for future use.
    function verifyAge(
        IAxiomV0.BlockHashWitness calldata prevBlock,
        IAxiomV0.BlockHashWitness calldata currBlock,
        bytes calldata proof
    ) external;
}
