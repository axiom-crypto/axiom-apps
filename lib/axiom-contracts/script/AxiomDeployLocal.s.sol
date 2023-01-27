// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/Axiom.sol";

contract AxiomDeployLocal is Script {
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

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address verifierAddress = address(deployContract("mainnet_10_7"));
        address historicalVerifierAddress = address(deployContract("mainnet_17_7"));
        Axiom axiom = new Axiom(verifierAddress, historicalVerifierAddress);

        vm.stopBroadcast();
    }
}
