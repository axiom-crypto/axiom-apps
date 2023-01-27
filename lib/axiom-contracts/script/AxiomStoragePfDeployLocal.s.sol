// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/AxiomStoragePf.sol";

contract AxiomStoragePfDeployLocal is Script {
    Axiom axiom;
    AxiomStoragePf axiomStorage;

    function deployContract(string memory fileName) public returns (address) {
        string memory bashCommand = string.concat(
            'cast abi-encode "f(bytes)" $(solc --yul yul/', string.concat(fileName, ".yul --bin | tail -1)")
        );

        string[] memory inputs = new string[](3);
        inputs[0] = "bash";
        inputs[1] = "-c";
        inputs[2] = bashCommand;

        bytes memory bytecode = abi.decode(vm.ffi(inputs), (bytes));

        ///@notice deploy the bytecode with the create instruction
        address deployedAddress;
        assembly {
            deployedAddress := create(0, add(bytecode, 0x20), mload(bytecode))
        }

        ///@notice check that the deployment was successful
        require(deployedAddress != address(0), "Could not deploy Yul contract");

        ///@notice return the address that the contract was deployed to
        return deployedAddress;
    }

    // Put proof for block ending in 0xf993ff=16356351 into Axiom smart contract
    function updateRecent1024() public {
        string memory path = "data/mainnet_10_7_f99000_f993ff.calldata";
        string memory bashCommand = string.concat('cast abi-encode "f(bytes)" $(cat ', string.concat(path, ")"));

        string[] memory inputs = new string[](3);
        inputs[0] = "bash";
        inputs[1] = "-c";
        inputs[2] = bashCommand;

        bytes memory proofData = abi.decode(vm.ffi(inputs), (bytes));
        axiom.updateRecent(proofData);
    }    

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address verifierAddress = address(deployContract("mainnet_10_7"));
        address storageVerifierAddress = address(deployContract("storage"));

        axiom = new Axiom(verifierAddress, verifierAddress);
        axiomStorage = new AxiomStoragePf(address(axiom), storageVerifierAddress);

        updateRecent1024();
        vm.stopBroadcast();
    }
}
