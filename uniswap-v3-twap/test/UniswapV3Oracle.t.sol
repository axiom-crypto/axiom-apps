// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "axiom-contracts/contracts/interfaces/IAxiomV1Query.sol";
import "../src/UniswapV3Oracle.sol";
import "forge-std/console.sol";
import "utils/ReadQueryData.sol";

contract UinswapV3OracleTest is Test {
    address AXIOM_QUERY_ADDRESS = 0x4Fb202140c5319106F15706b1A69E441c9536306;

    function setUp() public {
        vm.createSelectFork("goerli", 9290313);
    }

    function getTestData() public view returns (IAxiomV1Query.StorageResponse[] memory, bytes32[3] memory) {
        string memory root = vm.projectRoot();
        //TODO: get working input data
        string memory path = string.concat(root, "/test/data/input.json");
        string memory json = vm.readFile(path);

        ReadQueryData.QueryResponse memory qr = ReadQueryData.readQueryResponses(json);

        return (qr.storageResponses, qr.keccakResponses);
    }

    function testCalculateUniswapV3Twap() public {
        vm.pauseGasMetering();
        UniswapV3Oracle uniswapV3Oracle = new UniswapV3Oracle(AXIOM_QUERY_ADDRESS);
        (IAxiomV1Query.StorageResponse[] memory storageResponses, bytes32[3] memory keccakResponses) = getTestData();
        vm.resumeGasMetering();
        uniswapV3Oracle.verifyUniswapV3TWAP(storageResponses, keccakResponses);
    }
}
