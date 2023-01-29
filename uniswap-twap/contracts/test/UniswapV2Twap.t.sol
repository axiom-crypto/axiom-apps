// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../lib/YulDeployer.sol";
import "../src/IAxiomV0.sol";
import "../src/UniswapV2Twap.sol";

contract UniswapTwapTest is Test {
    YulDeployer yulDeployer;
    address verifierAddress;
    address AXIOM_ADDRESS = 0x01d5b501C1fc0121e1411970fb79c322737025c2;

    function setUp() public {
        yulDeployer = new YulDeployer();
        verifierAddress = address(yulDeployer.deployContract("mainnet"));
    }    

    function testVerifyTwapForkRecent() public {
        string memory MAINNET_RPC_URL = string.concat("https://mainnet.infura.io/v3/", vm.envString("INFURA_ID"));
        vm.createSelectFork(MAINNET_RPC_URL, 16_509_500);

        // Import test proof and instance calldata
        string[] memory inputs = new string[](2);
        inputs[0] = "cat";
        inputs[1] = "test/data/test.calldata";
        bytes memory proof = vm.ffi(inputs);

        // Prepare witness data for Uniswap TWAP proof.
        IAxiomV0.BlockHashWitness memory startBlock = IAxiomV0.BlockHashWitness({
            blockNumber: 10008566,
            claimedBlockHash: bytes32(0x4ba33a650f9e3d8430f94b61a382e60490ec7a06c2f4441ecf225858ec748b78),
            prevHash: bytes32(0x9b714087625d2463e518c34a497fbe1410456d6716d65f04d93c1cb241a68331),
            numFinal: 1024,
            merkleProof: [bytes32(0xde070395104149caf62754d14993be5c368ef8c62a13b6eb9f005c64f7126585),
                          bytes32(0x121c1dab28f80bf9f0189a2eb9aa3873632601673256e41bc1a68838d091278d),
                          bytes32(0x764d59137586effec496b05d810055d453b76d00291342f9d9a50c3b2d33edb5),
                          bytes32(0x5f97f6fd0b3686010297f8fb16cebbeddea0cbf7befe853c88955f43df93bb8c),
                          bytes32(0x6a97be2fe63b80f4a7e86b47634c885d389482c52e6f428fdef80494cad0d376),
                          bytes32(0xf40b18980e4b3123e524fb887e4b8c65de1542c4e74f0b7aefd1d42c885d341e),
                          bytes32(0xa5a4fc1dcd4b55ef337f0cce8818b44e06fd49d9edd483980e5441b75bf93292),
                          bytes32(0xf09bb021623924ababf079def64ccacd1a70b1b9b95a68e6fad7092bc3b40843),
                          bytes32(0x0f309c480034b539183d0c87c79d380ad97eba011a04d9074eba1009493e8aee),
                          bytes32(0xd8a815fbbaafef9dfbc11c72d99d9df3f021761c7dbd9d9dc4f90b1edf46b50b)]
        });
        IAxiomV0.BlockHashWitness memory endBlock = IAxiomV0.BlockHashWitness({
            blockNumber: 16509300,
            claimedBlockHash: bytes32(0x3b4e49db58e4dab1931689ab67e24eb79660f2661034280bf8f4480071294456),
            prevHash: bytes32(0xf21f9ac46b21ce128bf245ac8c5dcd12ab1bf6a0cb0e3c7dc4d33cc8871d8ab3),
            numFinal: 1024,
            merkleProof: [bytes32(0x034ca3921f2ab605c8681288ba4c9818978a12e69c57e82350301fb58e1a9a6b),
                          bytes32(0xc7e1e977b5d68588e8643956ff13a20cf95c4a76e6ffb168d8faca06413d8c45),
                          bytes32(0xaa558831681ec38ab0face0d6eab566ae490d8bdf00e92f27d992836c10372d3),
                          bytes32(0x69384d455682d10dbc617296b17a8715d109d1b74ab74037d48e521122048810),
                          bytes32(0x62d103378fc33e7f8578480846a0b5634c083167eb621bf0122cd312e34862df),
                          bytes32(0x7f3a0dfb38decbb536032102f62f6786dc5c7ac3ed73b283bbc73ba3ea07406b),
                          bytes32(0x8b3e437e20a1d5da7d018acfec8129a3071085fb2a14c48712e12d13ecb16014),
                          bytes32(0xbe109e17256d615dc1fa6e241fa424247ede44bdadc36fa48fbfe71895f95d5d),
                          bytes32(0x3afb75397f28a7fbd51498e7a109865e34edf93ecce9ba4686d7d0fb7b86c63b),
                          bytes32(0x2953bc9d2dfc756b8d46e849da5971dbe1989603b06b7235627529d2e0e5df1d)]
        });
        // twapPri in uq112x112 format, test value computed independently
        uint256 twapPri = 0x0808c0ac56e0d8ad85091a;

        UniswapV2Twap uniswap = new UniswapV2Twap(AXIOM_ADDRESS, verifierAddress);
        uniswap.verifyUniswapV2Twap(startBlock, endBlock, proof);
        require(uniswap.twapPris((uint64(startBlock.blockNumber) << 32) | endBlock.blockNumber) == twapPri, 
                "TwapPri not verified");
    }
}