// SPDX-License-Identifier: MIT
// WARNING! This smart contract and the associated zk-SNARK verifiers have not been audited.
// DO NOT USE THIS CONTRACT FOR PRODUCTION
pragma solidity >=0.8.0 <0.9.0;

import {IAxiomV0} from "./IAxiomV0.sol";

interface IUniswapV2TwapV0 {
    /// @notice Mapping between abi.encodePacked(address poolAddress, uint32 startBlockNumber, uint32 endBlockNumber) => twapPri (uint256)
    function twapPris(bytes28) external view returns (uint256);

    event UniswapV2TwapProof(address pairAddress, uint32 startBlockNumber, uint32 endBlockNumber, uint256 twapPri);

    /// @notice Verify a ZK proof of a Uniswap V2 TWAP computation and verifies the validity of checkpoint blockhashes using Axiom.
    ///         Caches the TWAP price value for future use.
    ///         Returns the time (seconds) weighted average price (arithmetic mean)
    function verifyUniswapV2Twap(
        IAxiomV0.BlockHashWitness calldata startBlock,
        IAxiomV0.BlockHashWitness calldata endBlock,
        bytes calldata proof
    ) external returns (uint256 twapPri);
}
