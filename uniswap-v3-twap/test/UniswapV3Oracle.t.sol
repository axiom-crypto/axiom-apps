// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "axiom-contracts/contracts/interfaces/IAxiomV1Query.sol";
import "../src/UniswapV3Oracle.sol";
import "forge-std/console.sol";
import "utils/ReadQueryData.sol";

contract UinswapV3OracleTest is Test {
    address AXIOM_QUERY_ADDRESS = 0x82842F7a41f695320CC255B34F18769D68dD8aDF;

    function setUp() public {
        string memory GOERLI_RPC_URL = string.concat(
            "https://goerli.infura.io/v3/",
            vm.envString("INFURA_ID")
        ); 
        vm.createSelectFork(GOERLI_RPC_URL, 9217410);
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
