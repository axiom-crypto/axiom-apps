// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IAxiomV1Query} from "axiom-contracts/contracts/interfaces/IAxiomV1Query.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";

contract AccountAge is Ownable {
    address public axiomQueryAddress;

    mapping(address => uint32) public birthBlocks;
    event UpdateAxiomQueryAddress(address newAddress);
    event AccountAgeVerified(address account, uint32 birthBlock);

    constructor(address _axiomQueryAddress) {
        axiomQueryAddress = _axiomQueryAddress;
        emit UpdateAxiomQueryAddress(_axiomQueryAddress);
    }

    function updateAxiomQueryAddress(
        address _axiomQueryAddress
    ) external onlyOwner {
        axiomQueryAddress = _axiomQueryAddress;
        emit UpdateAxiomQueryAddress(_axiomQueryAddress);
    }

    function verifyAge(
        IAxiomV1Query.AccountResponse[] calldata accountProofs,
        bytes32[3] calldata keccakResponses
    ) external {
        require(accountProofs.length == 2, "Too many account proofs");
        address account = accountProofs[0].addr;
        require(account == accountProofs[1].addr, "Accounts are not the same");
        require(
            accountProofs[0].blockNumber + 1 == accountProofs[1].blockNumber,
            "Block numbers are not consecutive"
        );
        require(accountProofs[0].nonce == 0, "Prev block nonce is not 0");
        require(accountProofs[1].nonce > 0, "No account transactions in curr block");
        uint addrSize;
        assembly {
            addrSize := extcodesize(account)
        }
        require(addrSize == 0, "Account is a contract");

        require(
            IAxiomV1Query(axiomQueryAddress).areResponsesValid(
                keccakResponses[0],
                keccakResponses[1],
                keccakResponses[2],
                new IAxiomV1Query.BlockResponse[](0),
                accountProofs,
                new IAxiomV1Query.StorageResponse[](0)
            ),
            "Proof not valid"
        );

        birthBlocks[account] = accountProofs[0].blockNumber;
        emit AccountAgeVerified(account, accountProofs[0].blockNumber);
    }
}
