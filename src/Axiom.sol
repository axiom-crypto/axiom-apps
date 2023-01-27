// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

uint8 constant TREE_DEPTH = 10;
uint32 constant NUM_LEAVES = 2 ** 10;
uint32 constant PUBLIC_START_IDX = 4 * 3 * 32;
uint32 constant ROOT_START_IDX = PUBLIC_START_IDX + 5 * 32;

// constants for batch import of historical block hashes
uint8 constant HISTORICAL_TREE_DEPTH = 17;
uint32 constant HISTORICAL_NUM_LEAVES = 2 ** 17;
uint32 constant HISTORICAL_NUM_ROOTS = 2 ** 7; // HISTORICAL_NUM_LEAVES / NUM_LEAVES

function calcMerkleRoot(bytes32[] calldata leaves) pure returns (bytes32) {
    if (leaves.length == 0) return bytes32(0);
    if (leaves.length == 1) return leaves[0];
    require(leaves.length & 1 == 0);
    uint256 len = leaves.length >> 1;
    bytes32[] memory roots = new bytes32[](len);
    for (uint256 i = 0; i < len; i++) {
        roots[i] = keccak256(abi.encodePacked(leaves[i << 1], leaves[(i << 1) | 1]));
    }
    while (len > 1) {
        len >>= 1;
        for (uint256 i = 0; i < len; i++) {
            roots[i] = keccak256(abi.encodePacked(roots[i << 1], roots[(i << 1) | 1]));
        }
    }
    return roots[0];
}

contract Axiom {
    address private verifierAddress;
    address private historicalVerifierAddress;

    // historicalRoots[startBlockNumber] is 0 unless (startBlockNumber % NUM_LEAVES == 0)
    // historicalRoots[startBlockNumber] holds the hash of
    //   prevHash || root || numFinal
    // where
    // - prevHash is the parent hash of block startBlockNumber
    // - root is the partial Merkle root of blockhashes of block numbers
    //   [startBlockNumber, startBlockNumber + NUM_LEAVES)
    //   where unconfirmed block hashes are 0's
    // - numFinal is the number of confirmed consecutive roots in [startBlockNumber, startBlockNumber + NUM_LEAVES)
    mapping(uint32 => bytes32) public historicalRoots;

    event UpdateEvent(uint32 startBlockNumber, bytes32 prevHash, bytes32 root, uint32 numFinal);

    struct BlockHashWitness {
        uint32 blockNumber;
        bytes32 claimedBlockHash;
        bytes32 prevHash;
        uint32 numFinal;
        bytes32[TREE_DEPTH] merkleProof;
    }

    constructor(address _verifierAddress, address _historicalVerifierAddress) {
        verifierAddress = _verifierAddress;
        historicalVerifierAddress = _historicalVerifierAddress;
    }

    function verifyRaw(bytes calldata input) private returns (bool) {
        (bool success,) = verifierAddress.call(input);
        return success;
    }

    function verifyHistoricalRaw(bytes calldata input) private returns (bool) {
        (bool success,) = historicalVerifierAddress.call(input);
        return success;
    }

    function getEmptyHash(uint256 depth) public pure returns (bytes32) {
        // emptyHashes[idx] is the Merkle root of a tree of depth idx with 0's as leaves
        bytes32[TREE_DEPTH] memory emptyHashes = [
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
            bytes32(0xad3228b676f7d3cd4284a5443f17f1962b36e491b30a40b2405849e597ba5fb5),
            bytes32(0xb4c11951957c6f8f642c4af61cd6b24640fec6dc7fc607ee8206a99e92410d30),
            bytes32(0x21ddb9a356815c3fac1026b6dec5df3124afbadb485c9ba5a3e3398a04b7ba85),
            bytes32(0xe58769b32a1beaf1ea27375a44095a0d1fb664ce2dd358e7fcbfb78c26a19344),
            bytes32(0x0eb01ebfc9ed27500cd4dfc979272d1f0913cc9f66540d7e8005811109e1cf2d),
            bytes32(0x887c22bd8750d34016ac3c66b5ff102dacdd73f6b014e710b51e8022af9a1968),
            bytes32(0xffd70157e48063fc33c97a050f7f640233bf646cc98d9524c6b92bcf3ab56f83),
            bytes32(0x9867cc5f7f196b93bae1e27e6320742445d290f2263827498b54fec539f756af),
            bytes32(0xcefad4e508c098b9a7e1d8feb19955fb02ba9675585078710969d3440f5054e0)
        ];
        return emptyHashes[depth];
    }

    // Compute the forward Merkle root of block hashes of block numbers
    //   [startBlockNumber, startBlockNumber + 2 ** depth)
    // which is a mix of EVM blockhashes and 0s
    // TODO: optimize by not hashing empty parts of the tree
    function forwardMerkleRoot(uint256 startBlockNumber, uint256 depth) public view returns (bytes32) {
        if (startBlockNumber > block.number - 1) {
            return getEmptyHash(depth);
        } else {
            bytes32[] memory hashes = new bytes32[](2**(depth - 1));
            bytes32 blockHash1;
            bytes32 blockHash2;
            for (uint256 round = 0; round < depth; round++) {
                if (round == 0) {
                    for (uint256 idx = 0; idx < 2 ** (depth - 1 - round); idx++) {
                        if (startBlockNumber + 2 * idx < block.number) {
                            blockHash1 = blockhash(startBlockNumber + 2 * idx);
                        } else {
                            blockHash1 = bytes32(0);
                        }
                        if (startBlockNumber + 1 + 2 * idx < block.number) {
                            blockHash2 = blockhash(startBlockNumber + 1 + 2 * idx);
                        } else {
                            blockHash2 = bytes32(0);
                        }
                        hashes[idx] = keccak256(abi.encodePacked(blockHash1, blockHash2));
                    }
                } else {
                    for (uint256 idx = 0; idx < 2 ** (depth - 1 - round); idx++) {
                        hashes[idx] = keccak256(abi.encodePacked(hashes[2 * idx], hashes[2 * idx + 1]));
                    }
                }
            }
            return hashes[0];
        }
    }

    // the proof has block headers for [startBlockNumber, endBlockNumber] blocks
    function getBoundaryBlockData(bytes calldata proofData)
        internal
        pure
        returns (bytes32 prevHash, bytes32 endHash, uint32 startBlockNumber, uint32 endBlockNumber, bytes32 root)
    {
        prevHash = bytes32(
            uint256(bytes32(proofData[PUBLIC_START_IDX:PUBLIC_START_IDX + 32])) << 128
                | uint128(bytes16(proofData[PUBLIC_START_IDX + 32 + 16:PUBLIC_START_IDX + 2 * 32]))
        );
        endHash = bytes32(
            uint256(bytes32(proofData[PUBLIC_START_IDX + 2 * 32:PUBLIC_START_IDX + 3 * 32])) << 128
                | uint128(bytes16(proofData[PUBLIC_START_IDX + 3 * 32 + 16:PUBLIC_START_IDX + 4 * 32]))
        );
        startBlockNumber = uint32(bytes4(proofData[PUBLIC_START_IDX + 5 * 32 - 8:PUBLIC_START_IDX + 5 * 32 - 4]));
        endBlockNumber = uint32(bytes4(proofData[PUBLIC_START_IDX + 5 * 32 - 4:PUBLIC_START_IDX + 5 * 32]));
        root = bytes32(
            uint256(bytes32(proofData[ROOT_START_IDX:ROOT_START_IDX + 32])) << 128
                | uint128(bytes16(proofData[ROOT_START_IDX + 48:ROOT_START_IDX + 64]))
        );
    }

    function updateRecentFallback(uint32 startBlockNumber) external {
        require(startBlockNumber % NUM_LEAVES == 0, "startBlockNumber not a multiple of NUM_LEAVES");
        require(block.number - startBlockNumber <= 256, "Not a recent startBlock");
        require(startBlockNumber < block.number, "Not a recent startBlock");

        bytes32 prevHash = blockhash(startBlockNumber - 1);
        bytes32 root = forwardMerkleRoot(startBlockNumber, 8);
        for (uint256 depth = 8; depth < TREE_DEPTH; depth++) {
            root = keccak256(abi.encodePacked(root, getEmptyHash(depth)));
        }
        historicalRoots[startBlockNumber] =
            keccak256(abi.encodePacked(prevHash, root, uint32(block.number) - startBlockNumber));
        emit UpdateEvent(startBlockNumber, prevHash, root, uint32(block.number) - startBlockNumber);
    }

    // update blocks in the "backward" direction, anchoring on a "recent" end blockhash that is within last 256 blocks
    // * startBlockNumber must be a multiple of NUM_LEAVES
    // * roots[idx] is the root of a Merkle tree of height 2**(TREE_DEPTH - idx) in a Merkle mountain
    //   range which stores block hashes in the interval [startBlockNumber, endBlockNumber)
    function updateRecent(bytes calldata proofData) external {
        (bytes32 prevHash, bytes32 endHash, uint32 startBlockNumber, uint32 endBlockNumber, bytes32 root) =
            getBoundaryBlockData(proofData);
        bytes32[TREE_DEPTH] memory roots;
        for (uint256 idx = 1; idx <= TREE_DEPTH; idx++) {
            roots[idx - 1] = bytes32(
                uint256(bytes32(proofData[ROOT_START_IDX + idx * 64:ROOT_START_IDX + idx * 64 + 32])) << 128
                    | uint128(bytes16(proofData[ROOT_START_IDX + idx * 64 + 16 + 32:ROOT_START_IDX + idx * 64 + 64]))
            );
        }

        uint32 numFinal = endBlockNumber - startBlockNumber + 1;
        require(numFinal <= NUM_LEAVES, "Updating too many blocks at once");
        require(startBlockNumber % NUM_LEAVES == 0, "startBlockNumber not a multiple of NUM_LEAVES");
        require(block.number - endBlockNumber <= 256, "Not a recent endBlock");
        require(endBlockNumber < block.number, "Not a recent endBlock");
        require(blockhash(endBlockNumber) == endHash, "endHash does not match");
        require(verifyRaw(proofData), "ZKP does not verify");
        require(block.number - 1 - startBlockNumber >= 0, "No new blocks");

        if (root == bytes32(0)) {
            // compute Merkle root of completed Merkle mountain range with 0s for unconfirmed blockhashes
            for (uint256 round = 1; round <= TREE_DEPTH; round++) {
                if (roots[TREE_DEPTH - round] != 0) {
                    root = keccak256(abi.encodePacked(roots[TREE_DEPTH - round], root));
                } else {
                    root = keccak256(abi.encodePacked(root, getEmptyHash(round - 1)));
                }
            }
        }
        historicalRoots[startBlockNumber] = keccak256(abi.encodePacked(prevHash, root, numFinal));
        emit UpdateEvent(startBlockNumber, prevHash, root, numFinal);
    }

    // update older blocks in "backwards" direction, anchoring on more recent trusted blockhash
    // must be batch of NUM_LEAVES blocks
    function updateOld(bytes32 nextRoot, uint32 nextNumFinal, bytes calldata proofData) external {
        (bytes32 prevHash, bytes32 endHash, uint32 startBlockNumber, uint32 endBlockNumber, bytes32 root) =
            getBoundaryBlockData(proofData);

        require(startBlockNumber % NUM_LEAVES == 0, "startBlockNumber not a multiple of NUM_LEAVES");
        require(endBlockNumber - startBlockNumber == NUM_LEAVES - 1, "Updating with incorrect number of blocks");

        require(
            historicalRoots[endBlockNumber + 1] == keccak256(abi.encodePacked(endHash, nextRoot, nextNumFinal)),
            "endHash does not match"
        );
        require(verifyRaw(proofData), "ZKP does not verify");

        historicalRoots[startBlockNumber] = keccak256(abi.encodePacked(prevHash, root, NUM_LEAVES));
        emit UpdateEvent(startBlockNumber, prevHash, root, NUM_LEAVES);
    }

    // update older blocks in "backwards" direction, anchoring on more recent trusted blockhash
    // must be batch of NUM_LEAVES blocks
    function updateHistorical(bytes32 nextRoot, uint32 nextNumFinal, bytes32[] calldata roots, bytes calldata proofData)
        external
    {
        (bytes32 _prevHash, bytes32 _endHash, uint32 startBlockNumber, uint32 endBlockNumber, bytes32 aggregateRoot) =
            getBoundaryBlockData(proofData);

        require(startBlockNumber % NUM_LEAVES == 0, "startBlockNumber not a multiple of NUM_LEAVES");
        require(
            endBlockNumber - startBlockNumber == HISTORICAL_NUM_LEAVES - 1,
            "Updating with incorrect number of historical blocks"
        );
        require(
            roots.length == HISTORICAL_NUM_ROOTS,
            "There should be HISTORICAL_NUM_ROOTS historical merkle roots, each of depth TREE_DEPTH"
        );
        require(
            historicalRoots[endBlockNumber + 1] == keccak256(abi.encodePacked(_endHash, nextRoot, nextNumFinal)),
            "endHash does not match"
        );
        require(
            calcMerkleRoot(roots) == aggregateRoot,
            "Aggregate merkle root of supplied historical roots does not match the ZKP root"
        );

        require(verifyHistoricalRaw(proofData), "ZKP does not verify");

        for (uint256 i = 0; i < HISTORICAL_NUM_ROOTS; i++) {
            bytes32 prevHash = i == 0 ? _prevHash : roots[i - 1];
            uint32 start = uint32(startBlockNumber + i * NUM_LEAVES);
            historicalRoots[start] = keccak256(abi.encodePacked(prevHash, roots[i], NUM_LEAVES));
            emit UpdateEvent(start, prevHash, roots[i], NUM_LEAVES);
        }
    }

    function isRecentBlockHashValid(uint32 blockNumber, bytes32 claimedBlockHash) public view returns (bool) {
        bytes32 blockHash = blockhash(blockNumber);
        require(blockHash != 0x0, "Must supply block hash of one of 256 most recent blocks");
        return (blockHash == claimedBlockHash);
    }

    function isBlockHashValid(
        uint32 blockNumber,
        bytes32 claimedBlockHash,
        bytes32 prevHash,
        uint32 numFinal,
        bytes32[TREE_DEPTH] calldata merkleProof
    ) public view returns (bool) {
        require(claimedBlockHash != 0x0, "Claimed block hash cannot be 0");
        uint32 startBlockNumber = blockNumber - (blockNumber % NUM_LEAVES);
        uint32 side = blockNumber % NUM_LEAVES;
        bytes32 merkleRoot = historicalRoots[startBlockNumber];
        require(merkleRoot != 0, "Merkle root must be stored already");
        // compute Merkle root of blockhash
        bytes32 root = claimedBlockHash;
        for (uint8 depth = 0; depth < TREE_DEPTH; depth++) {
            // 0 for left, 1 for right
            if ((side >> depth) & 1 == 0) {
                root = keccak256(abi.encodePacked(root, merkleProof[depth]));
            } else {
                root = keccak256(abi.encodePacked(merkleProof[depth], root));
            }
        }
        return (merkleRoot == keccak256(abi.encodePacked(prevHash, root, numFinal)));
    }
}
