// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import "axiom-contracts/contracts/interfaces/IAxiomV1Query.sol";
import "../src/AccountAge.sol";
import "forge-std/console.sol";
import "utils/ReadQueryData.sol";

contract AccountAgeTest is Test {
    address AXIOM_QUERY_ADDRESS = 0x82842F7a41f695320CC255B34F18769D68dD8aDF;

    function setUp() public {
        string memory GOERLI_RPC_URL = string.concat(
            "https://goerli.infura.io/v3/",
            vm.envString("INFURA_ID")
        ); 
        vm.createSelectFork(GOERLI_RPC_URL, 9213668);
    }

    function getTestData() public view returns (IAxiomV1Query.AccountResponse[] memory, bytes32[3] memory) {

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/test/data/input.json");
        string memory json = vm.readFile(path);

        IAxiomV1Query.AccountResponse memory currBlock = ReadQueryData.readAccountResponse(stdJson.parseRaw(json, ".currBlock"));
        IAxiomV1Query.AccountResponse memory prevBlock = ReadQueryData.readAccountResponse(stdJson.parseRaw(json, ".prevBlock"));
        bytes32[3] memory keccakResponses = ReadQueryData.readKeccakResponses(stdJson.parseRaw(json, ".keccakResponses"));
        
        IAxiomV1Query.AccountResponse[] memory accountProofs = new IAxiomV1Query.AccountResponse[](2);
        accountProofs[0] = prevBlock;
        accountProofs[1] = currBlock;

        return (accountProofs, keccakResponses);
    }

    function testCheckAccountAge() public {
        vm.pauseGasMetering();
        AccountAge accountAge = new AccountAge(AXIOM_QUERY_ADDRESS);
        (IAxiomV1Query.AccountResponse[] memory accountProofs, bytes32[3] memory keccakResponses) = getTestData();
        vm.resumeGasMetering();
        accountAge.verifyAge(accountProofs, keccakResponses);
    }
}
