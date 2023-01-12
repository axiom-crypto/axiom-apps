// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../lib/YulDeployer.sol";
import "../src/AccountAge.sol";
import "../test/MockBlockCache.sol";

contract AccountAgeTest is Test {
    YulDeployer yulDeployer = new YulDeployer();

    function testVerifyAge() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy a mock block cache contract
        MockBlockCache cache = new MockBlockCache();

        // Deploy the PLONK verifier contract
        address plonkVerifierAddress = yulDeployer.deployContract("PlonkVerifier");
        
        // Deploy the account age contact
        AccountAge app = new AccountAge(plonkVerifierAddress, address(cache));

        // Import proof and instance calldata
        string[] memory inputs = new string[](2);
        inputs[0] = "cat";
        inputs[1] = "test/data/test.calldata";
        bytes memory proof = vm.ffi(inputs);

        // Call verify function in app
        address account = 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045;
        uint256 blockNumber = 318528;
        cache.setBlockHash(
            blockNumber - 1,
            0xe08268339180818ce107d0200b23f52c18f3855065d68109d9e47eaa19580148);
        cache.setBlockHash(
            blockNumber, 
            0xb7ae60b456f7733ae3d8bb927b03470eb662f0285f6c83d545b735c35634ede3);
        app.verifyAge(account, blockNumber, proof);

        vm.stopBroadcast();
    }
}
