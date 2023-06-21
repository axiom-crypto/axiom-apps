// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "../axiom-contracts/contracts/interfaces/IAxiomV1Query.sol";
import "../forge-std/src/console.sol";
import "../forge-std/src/Vm.sol";
import {stdJson} from "forge-std/StdJson.sol";

library ReadQueryData {

    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct RawBlockResponse {
        bytes32 blockHash;
        bytes blockNumber;
        bytes leafIdx;
        bytes32[] proof;
    }

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

    struct RawStorageResponse {
        address addr;
        bytes blockNumber;
        bytes leafIdx;
        bytes32[] proof;
        bytes slot;
        bytes32 value;
    }

    struct KeccakResponses {
        bytes32 keccakAccountResponse;
        bytes32 keccakBlockResponse;
        bytes32 keccakStorageResponse;
    }

    struct QueryResponse {
        IAxiomV1Query.BlockResponse[] blockResponses;
        IAxiomV1Query.AccountResponse[] accountResponses;
        IAxiomV1Query.StorageResponse[] storageResponses;
        bytes32[3] keccakResponses;
    }

    function _bytesToUint(bytes memory b) private pure returns (uint256) {
        require(b.length <= 32, "StdCheats _bytesToUint(bytes): Bytes length exceeds 32.");
        return abi.decode(abi.encodePacked(new bytes(32 - b.length), b), (uint256));
    }

    function convertRawAccountResponse(RawAccountResponse memory raw) internal pure returns (IAxiomV1Query.AccountResponse memory) {
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

    function readAccountResponse(bytes memory jsonBytes) internal pure returns (IAxiomV1Query.AccountResponse memory) {
        RawAccountResponse memory raw = abi.decode(jsonBytes, (RawAccountResponse));
        return convertRawAccountResponse(raw);
    }

    function readAccountResponseArray(bytes memory jsonBytes) internal pure returns (IAxiomV1Query.AccountResponse[] memory) {
        RawAccountResponse[] memory raw = abi.decode(jsonBytes, (RawAccountResponse[]));
        IAxiomV1Query.AccountResponse[] memory accountResponses = new IAxiomV1Query.AccountResponse[](raw.length);
        for (uint i = 0; i < raw.length; i++) {
            accountResponses[i] = convertRawAccountResponse(raw[i]);
        }
        return accountResponses;
    }

    function convertRawStorageResponse(RawStorageResponse memory raw) internal pure returns (IAxiomV1Query.StorageResponse memory){
        require(raw.proof.length == 6, "Proof length is not 6");
        bytes32[6] memory proof;
        for (uint i = 0; i < 6; i++) {
            proof[i] = raw.proof[i];
        }
        return IAxiomV1Query.StorageResponse({
            addr: raw.addr,
            blockNumber: uint32(_bytesToUint(raw.blockNumber)),
            leafIdx: uint32(_bytesToUint(raw.leafIdx)),
            proof: proof,
            slot: uint256(_bytesToUint(raw.slot)),
            value: uint256(raw.value)
        });
    }

    function readStorageResponse(bytes memory jsonBytes) internal pure returns (IAxiomV1Query.StorageResponse memory) {
        RawStorageResponse memory raw = abi.decode(jsonBytes, (RawStorageResponse));
        return convertRawStorageResponse(raw);
    }

    function readStorageResponseArray(bytes memory jsonBytes) internal pure returns (IAxiomV1Query.StorageResponse[] memory) {
        RawStorageResponse[] memory raw = abi.decode(jsonBytes, (RawStorageResponse[]));
        IAxiomV1Query.StorageResponse[] memory storageResponses = new IAxiomV1Query.StorageResponse[](raw.length);
        for (uint i = 0; i < raw.length; i++) {
            storageResponses[i] = convertRawStorageResponse(raw[i]);
        }
        return storageResponses;
    }

    function convertRawBlockResponse(RawBlockResponse memory raw) internal pure returns (IAxiomV1Query.BlockResponse memory) {
        require(raw.proof.length == 6, "Proof length is not 6");
        bytes32[6] memory proof;
        for (uint i = 0; i < 6; i++) {
            proof[i] = raw.proof[i];
        }
        return IAxiomV1Query.BlockResponse({
            blockHash: raw.blockHash,
            blockNumber: uint32(_bytesToUint(raw.blockNumber)),
            leafIdx: uint32(_bytesToUint(raw.leafIdx)),
            proof: proof
        });
    }

    function readBlockResponse(bytes memory jsonBytes) internal pure returns (IAxiomV1Query.BlockResponse memory) {
        RawBlockResponse memory raw = abi.decode(jsonBytes, (RawBlockResponse));
        return convertRawBlockResponse(raw);
    }

    function readBlockResponseArray(bytes memory jsonBytes) internal pure returns (IAxiomV1Query.BlockResponse[] memory) {
        RawBlockResponse[] memory raw = abi.decode(jsonBytes, (RawBlockResponse[]));
        IAxiomV1Query.BlockResponse[] memory blockResponses = new IAxiomV1Query.BlockResponse[](raw.length);
        for (uint i = 0; i < raw.length; i++) {
            blockResponses[i] = convertRawBlockResponse(raw[i]);
        }
        return blockResponses;
    }

    function readKeccakResponses(bytes memory jsonBytes) internal pure returns (bytes32[3] memory) {
        KeccakResponses memory keccakResponsesParsed = abi.decode(jsonBytes, (KeccakResponses));
        bytes32[3] memory keccakResponses = [keccakResponsesParsed.keccakBlockResponse, keccakResponsesParsed.keccakAccountResponse, keccakResponsesParsed.keccakStorageResponse];
        return keccakResponses;
    }

    function readQueryResponses(string memory json) internal pure returns (QueryResponse memory) {
        bytes32[3] memory keccakResponses = readKeccakResponses(stdJson.parseRaw(json, ".keccakResponses"));
        IAxiomV1Query.StorageResponse[] memory storageProofs = readStorageResponseArray(stdJson.parseRaw(json, ".storageResponses"));
        IAxiomV1Query.BlockResponse[] memory blockProofs = readBlockResponseArray(stdJson.parseRaw(json, ".blockResponses"));
        IAxiomV1Query.AccountResponse[] memory accountProofs = readAccountResponseArray(stdJson.parseRaw(json, ".accountResponses"));
        return QueryResponse({
            blockResponses: blockProofs,
            accountResponses: accountProofs,
            storageResponses: storageProofs,
            keccakResponses: keccakResponses
        });
    }

}