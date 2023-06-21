// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "../axiom-contracts/contracts/interfaces/IAxiomV1Query.sol";
import "../forge-std/src/console.sol";
import "../forge-std/src/Vm.sol";

library ReadQueryData {

    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct RawAccountResponse {
        address addr;
        bytes balance;
        bytes blockNumber;    
        bytes32 codeHash;   
        bytes leafIdx; 
        bytes nonce;
        bytes32[] proof;
        bytes32 storageRoot;

    }

    struct KeccakResponses {
        bytes32 keccakBlockResponse;
        bytes32 keccakAccountResponse;
        bytes32 keccakStorageResponse;
    }

    function _bytesToUint(bytes memory b) private pure returns (uint256) {
        require(b.length <= 32, "StdCheats _bytesToUint(bytes): Bytes length exceeds 32.");
        return abi.decode(abi.encodePacked(new bytes(32 - b.length), b), (uint256));
    }

    function readAccountResponse(bytes memory jsonBytes) internal pure returns (IAxiomV1Query.AccountResponse memory) {
        RawAccountResponse memory raw = abi.decode(jsonBytes, (RawAccountResponse));
        require(raw.proof.length == 6, "Proof length is not 6");
        bytes32[6] memory proof;
        for (uint i = 0; i < 6; i++) {
            proof[i] = raw.proof[i];
        }
        return IAxiomV1Query.AccountResponse({
            addr: raw.addr,
            balance: uint96(_bytesToUint(raw.balance)),
            blockNumber: uint32(_bytesToUint(raw.blockNumber)),
            codeHash: raw.codeHash,
            leafIdx: uint32(_bytesToUint(raw.leafIdx)),
            nonce: uint64(_bytesToUint(raw.nonce)),
            proof: proof,
            storageRoot: raw.storageRoot
        });
    }

    function readKeccakResponses(bytes memory jsonBytes) internal pure returns (bytes32[3] memory) {
        KeccakResponses memory keccakResponsesParsed = abi.decode(jsonBytes, (KeccakResponses));
        bytes32[3] memory keccakResponses = [keccakResponsesParsed.keccakBlockResponse, keccakResponsesParsed.keccakAccountResponse, keccakResponsesParsed.keccakStorageResponse];
        return keccakResponses;
    }

}