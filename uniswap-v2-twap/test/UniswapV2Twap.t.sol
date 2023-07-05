// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import "axiom-contracts/contracts/interfaces/IAxiomV1Query.sol";
import "../src/UniswapV2Twap.sol";
import "forge-std/console.sol";
import "utils/ReadQueryData.sol";

contract UniswapV2TwapTest is Test {
    address AXIOM_QUERY_ADDRESS = 0x4Fb202140c5319106F15706b1A69E441c9536306;

    function setUp() public {
        vm.createSelectFork("goerli", 9295080);
    }

    function getTestData()
        public
        view
        returns (
            IAxiomV1Query.StorageResponse[] memory,
            IAxiomV1Query.BlockResponse[] memory,
            bytes[2] memory,
            bytes32[3] memory
        )
    {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/test/data/input.json");
        string memory json = vm.readFile(path);

        ReadQueryData.QueryResponse memory qr = ReadQueryData.readQueryResponses(json);

        bytes[] memory rlpHeaders = abi.decode(stdJson.parseRaw(json, ".blockHeaders"), (bytes[]));
        require(rlpHeaders.length == 2, "Invalid rlp headers length");
        bytes[2] memory rlpEncodedHeaders = [rlpHeaders[0], rlpHeaders[1]];

        return (qr.storageResponses, qr.blockResponses, rlpEncodedHeaders, qr.keccakResponses);
    }

    function testCalculateUniswapV2Twap() public {
        vm.pauseGasMetering();
        UniswapV2Twap uniswapV2Twap = new UniswapV2Twap(AXIOM_QUERY_ADDRESS);
        (
            IAxiomV1Query.StorageResponse[] memory storageResponses,
            IAxiomV1Query.BlockResponse[] memory blockResponses,
            bytes[2] memory rlpHeaders,
            bytes32[3] memory keccakResponses
        ) = getTestData();
        vm.resumeGasMetering();
        uniswapV2Twap.calculateUniswapV2Twap(storageResponses, blockResponses, rlpHeaders, keccakResponses);
    }
}
