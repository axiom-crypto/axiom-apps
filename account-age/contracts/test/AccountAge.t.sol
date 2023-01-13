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

        // Deploy mock block cache contract
        MockBlockCache cache = new MockBlockCache();

        // Deploy PLONK verifier contract
        address plonkVerifierAddress = yulDeployer.deployContract("PlonkVerifier");
        
        // Deploy account age contact
        AccountAge app = new AccountAge(plonkVerifierAddress, address(cache));

        // Import test proof and instance calldata
        string[] memory inputs = new string[](2);
        inputs[0] = "cat";
        inputs[1] = "test/data/test.calldata";
        bytes memory proof = vm.ffi(inputs);

        // Prepare witness data for account age proof.
        // Note that only the claimed block hash is checked in the test.
        address account = 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045;
        uint32 blockNumber = 318528;
        bytes32[4] memory prevBlockMerkleProof = [
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000)
        ];
        bytes32[4] memory currBlockMerkleProof = [
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000)
        ];
        AccountAge.BlockHashWitness memory prevBlock = AccountAge.BlockHashWitness({
            blockNumber: blockNumber - 1,
            claimedBlockHash: 0xe08268339180818ce107d0200b23f52c18f3855065d68109d9e47eaa19580148,
            prevHash: 0x0000000000000000000000000000000000000000000000000000000000000000,
            numFinal: 0,
            merkleProof: prevBlockMerkleProof
        });
        AccountAge.BlockHashWitness memory currBlock = AccountAge.BlockHashWitness({
            blockNumber: blockNumber,
            claimedBlockHash: 0xb7ae60b456f7733ae3d8bb927b03470eb662f0285f6c83d545b735c35634ede3,
            prevHash: 0x0000000000000000000000000000000000000000000000000000000000000000,
            numFinal: 0,
            merkleProof: currBlockMerkleProof
        });
        
        // Insert required block hashes into cache
        cache.setBlockHash(
            blockNumber - 1,
            0xe08268339180818ce107d0200b23f52c18f3855065d68109d9e47eaa19580148);
        cache.setBlockHash(
            blockNumber, 
            0xb7ae60b456f7733ae3d8bb927b03470eb662f0285f6c83d545b735c35634ede3);

        // Call verify function in app
        app.verifyAge(account, prevBlock, currBlock, proof);

        vm.stopBroadcast();
    }
}
