// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/AxiomDemo.sol";
import "./lib/YulDeployer.sol";

contract UpdateRecent is Test {
    AxiomDemo public axiom;
    YulDeployer yulDeployer;

    function setUp() public {
        yulDeployer = new YulDeployer();
        address verifierAddress = address(yulDeployer.deployContract("mainnet_10_7"));

        axiom = new AxiomDemo(verifierAddress, verifierAddress,
            uint32(0), keccak256(abi.encodePacked(bytes32(hex"00"), bytes32(hex"00"), uint32(0))));
        emit log_bytes32(keccak256(abi.encodePacked(bytes32(hex"00"), bytes32(hex"00"), uint32(0))));
    }

    // forge test -vv --ffi --fork-url <URL> --fork-block-number <NUM>
    // where 0xf993ff=16356351 in [NUM - 256, NUM)
    function testUpdateRecent1024() public {
        require(block.number - 256 <= 0xf993ff && 0xf993ff < block.number, "try a different block number");
        string memory path = "data/mainnet_10_7_f99000_f993ff.calldata";
        string memory bashCommand = string.concat('cast abi-encode "f(bytes)" $(cat ', string.concat(path, ")"));

        string[] memory inputs = new string[](3);
        inputs[0] = "bash";
        inputs[1] = "-c";
        inputs[2] = bashCommand;

        bytes memory proofData = abi.decode(vm.ffi(inputs), (bytes));
        axiom.updateRecent(proofData);
    }

    // forge test -vv --ffi --fork-url <URL> --fork-block-number <NUM>
    // where 0xf9907f=16355455 in [NUM - 256, NUM)
    function testUpdateRecent128() public {
        require(block.number - 256 <= 0xf9907f && 0xf9907f < block.number, "try a different block number");
        string memory path = "data/mainnet_10_7_f99000_f9907f.calldata";
        string memory bashCommand = string.concat('cast abi-encode "f(bytes)" $(cat ', string.concat(path, ")"));

        string[] memory inputs = new string[](3);
        inputs[0] = "bash";
        inputs[1] = "-c";
        inputs[2] = bashCommand;

        bytes memory proofData = abi.decode(vm.ffi(inputs), (bytes));
        axiom.updateRecent(proofData);
    }

    // forge test -vv --ffi --fork-url <URL> --fork-block-number <NUM>
    // where NUM - 256 < 0xf99000=16355328 and NUM > 0xf9907f=16355455
    function testValidateBlock() public {
        uint256 start = 0xf99000;
        uint256 end = 0xf9907f;
        require(start > block.number - 256, "start number is not recent");
        require(end < block.number, "end number in not recent");
        testUpdateRecent128();
        bytes32 prevHash = blockhash(start - 1);
        bytes32[][] memory merkleRoots = new bytes32[][](TREE_DEPTH + 1);
        merkleRoots[0] = new bytes32[](2 ** TREE_DEPTH);
        for (uint256 i = 0; i < 2 ** TREE_DEPTH; i++) {
            if (i <= end - start) {
                merkleRoots[0][i] = blockhash(start + i);
            } else {
                merkleRoots[0][i] = bytes32(0);
            }
        }
        for (uint256 depth = 0; depth < TREE_DEPTH; depth++) {
            merkleRoots[depth + 1] = new bytes32[](2 ** (TREE_DEPTH - depth - 1));
            for (uint256 i = 0; i < 2 ** (TREE_DEPTH - depth - 1); i++) {
                merkleRoots[depth + 1][i] =
                    keccak256(abi.encodePacked(merkleRoots[depth][2 * i], merkleRoots[depth][2 * i + 1]));
            }
        }

        bytes32[TREE_DEPTH] memory merkleProof;
        for (uint256 side = 0; side < 128; side++) {
            bytes32 blockHash = blockhash(start + side);
            for (uint8 depth = 0; depth < TREE_DEPTH; depth++) {
                merkleProof[depth] = merkleRoots[depth][(side >> depth) ^ 1];
            }
            require(
                axiom.isBlockHashValid(uint32(start + side), blockHash, prevHash, uint32(end - start + 1), merkleProof),
                "invalid merkle proof"
            );
        }
    }

    function testUpdateRecentFallback() public {
        axiom.updateRecentFallback(uint32(block.number - block.number % NUM_LEAVES));
    }

    function testBlockNumber() public {
        emit log_uint(block.number);
    }
}
