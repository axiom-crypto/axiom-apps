// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "axiom-contracts/contracts/interfaces/IAxiomV1Query.sol";
import "../src/AccountAge.sol";

contract AccountAgeTest is Test {
    address AXIOM_QUERY_ADDRESS = 0x82842F7a41f695320CC255B34F18769D68dD8aDF;

    function setUp() public {
        string memory GOERLI_RPC_URL = string.concat(
            "https://goerli.infura.io/v3/",
            vm.envString("INFURA_ID")
        ); 
        vm.createSelectFork(GOERLI_RPC_URL, 9213668);
    }

    function getTestData() public pure returns (IAxiomV1Query.AccountResponse[] memory, bytes32[3] memory) {
        IAxiomV1Query.AccountResponse memory currBlock = IAxiomV1Query.AccountResponse({
            blockNumber: uint32(9173677),
            addr: address(0x897dDbe14c9C7736EbfDC58461355697FbF70048),
            nonce: uint64(1),
            balance: uint96(0x455899e612881000),
            storageRoot: bytes32(0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421),
            codeHash: bytes32(0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470),
            leafIdx: uint32(1),
            proof: [
                bytes32(0x005fa7dafbc6cbfb8611b8832bd1e545820e4a6180087bcc8d31135d574c241e),
                bytes32(0xad3228b676f7d3cd4284a5443f17f1962b36e491b30a40b2405849e597ba5fb5),
                bytes32(0xb4c11951957c6f8f642c4af61cd6b24640fec6dc7fc607ee8206a99e92410d30),
                bytes32(0x21ddb9a356815c3fac1026b6dec5df3124afbadb485c9ba5a3e3398a04b7ba85),
                bytes32(0xe58769b32a1beaf1ea27375a44095a0d1fb664ce2dd358e7fcbfb78c26a19344),
                bytes32(0x0eb01ebfc9ed27500cd4dfc979272d1f0913cc9f66540d7e8005811109e1cf2d)
            ]
        });

        IAxiomV1Query.AccountResponse memory prevBlock = IAxiomV1Query.AccountResponse({
            blockNumber: uint32(9173676),
            addr: address(0x897dDbe14c9C7736EbfDC58461355697FbF70048),
            nonce: uint64(0),
            balance: uint96(0x4563918244f40000),
            storageRoot: bytes32(0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421),
            codeHash: bytes32(0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470),
            leafIdx: uint32(0),
            proof: [
                bytes32(0x8527a467eca5669d12e2dfdd0191cf9a641815302363e78877964b0e030c5052),
                bytes32(0xad3228b676f7d3cd4284a5443f17f1962b36e491b30a40b2405849e597ba5fb5),
                bytes32(0xb4c11951957c6f8f642c4af61cd6b24640fec6dc7fc607ee8206a99e92410d30),
                bytes32(0x21ddb9a356815c3fac1026b6dec5df3124afbadb485c9ba5a3e3398a04b7ba85),
                bytes32(0xe58769b32a1beaf1ea27375a44095a0d1fb664ce2dd358e7fcbfb78c26a19344),
                bytes32(0x0eb01ebfc9ed27500cd4dfc979272d1f0913cc9f66540d7e8005811109e1cf2d)
            ]
        });

        IAxiomV1Query.AccountResponse[] memory accountProofs = new IAxiomV1Query.AccountResponse[](2);
        accountProofs[0] = prevBlock;
        accountProofs[1] = currBlock;

        bytes32[3] memory keccakResponses;
        keccakResponses[0] = bytes32(0xe30c61ab41963c072045193073ea3fe5dbb8277f632f724d5baf8dfbe27a4b07);
        keccakResponses[1] = bytes32(0xb20db12ffe97503c747a1ce7ed61a867f1f83e34719f628c177711d1a7814c1d);
        keccakResponses[2] = bytes32(0x887c22bd8750d34016ac3c66b5ff102dacdd73f6b014e710b51e8022af9a1968);

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
