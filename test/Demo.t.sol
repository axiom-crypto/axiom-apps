// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/AxiomDemo.sol";
import "./lib/YulDeployer.sol";

contract DemoTest is Test {
    AxiomDemo public axiom;
    YulDeployer yulDeployer;

    function setUp() public {
        yulDeployer = new YulDeployer();
        address verifierAddress = address(yulDeployer.deployContract("mainnet_10_7"));

        axiom = new AxiomDemo(verifierAddress, verifierAddress,
            uint32(16356352), keccak256(abi.encodePacked(bytes32(hex"87445763da0b6836b89b8189c4fe71861987aa9af5a715bfb222a7978d98630d"), bytes32(hex"00"), uint32(0))));
    }

    function testUpdateOld() public {
        string memory path = "data/mainnet_10_7_f99000_f993ff.calldata";
        string memory bashCommand = string.concat('cast abi-encode "f(bytes)" $(cat ', string.concat(path, ")"));

        string[] memory inputs = new string[](3);
        inputs[0] = "bash";
        inputs[1] = "-c";
        inputs[2] = bashCommand;

        bytes memory proofData = abi.decode(vm.ffi(inputs), (bytes));
        axiom.updateOld(bytes32(hex"00"), uint32(0), proofData);
    }

    function testBlockHash() public {
        emit log_uint(uint256(blockhash(block.number - 1)));
    }

    function testEmptyHashes() public view {
        bytes32 empty = bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);
        for (uint256 i = 0; i < TREE_DEPTH - 1; i++) {
            empty = keccak256(abi.encodePacked(empty, empty));
            require(axiom.getEmptyHash(i + 1) == empty, "emptyHash does not match");
        }
    }
}
