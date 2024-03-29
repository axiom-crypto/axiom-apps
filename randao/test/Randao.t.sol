// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "axiom-contracts/contracts/interfaces/core/IAxiomV1Verifier.sol";
import "../src/Randao.sol";

contract RandaoTest is Test {
    address AXIOM_ADDRESS = 0x01d5b501C1fc0121e1411970fb79c322737025c2;

    function testVerifyRandaoRecent() public {
        vm.createSelectFork("mainnet", 16_509_500);

        // Import test proof and instance calldata
        string[] memory inputs = new string[](2);
        inputs[0] = "cat";
        inputs[1] = "test/data/test.calldata";
        bytes memory proof = vm.ffi(inputs);

        IAxiomV1.BlockHashWitness memory testBlock = IAxiomV1Verifier.BlockHashWitness({
            blockNumber: 16509301,
            claimedBlockHash: bytes32(0x034ca3921f2ab605c8681288ba4c9818978a12e69c57e82350301fb58e1a9a6b),
            prevHash: bytes32(0xf21f9ac46b21ce128bf245ac8c5dcd12ab1bf6a0cb0e3c7dc4d33cc8871d8ab3),
            numFinal: 1024,
            merkleProof: [
                bytes32(0x3b4e49db58e4dab1931689ab67e24eb79660f2661034280bf8f4480071294456),
                bytes32(0xc7e1e977b5d68588e8643956ff13a20cf95c4a76e6ffb168d8faca06413d8c45),
                bytes32(0xaa558831681ec38ab0face0d6eab566ae490d8bdf00e92f27d992836c10372d3),
                bytes32(0x69384d455682d10dbc617296b17a8715d109d1b74ab74037d48e521122048810),
                bytes32(0x62d103378fc33e7f8578480846a0b5634c083167eb621bf0122cd312e34862df),
                bytes32(0x7f3a0dfb38decbb536032102f62f6786dc5c7ac3ed73b283bbc73ba3ea07406b),
                bytes32(0x8b3e437e20a1d5da7d018acfec8129a3071085fb2a14c48712e12d13ecb16014),
                bytes32(0xbe109e17256d615dc1fa6e241fa424247ede44bdadc36fa48fbfe71895f95d5d),
                bytes32(0x3afb75397f28a7fbd51498e7a109865e34edf93ecce9ba4686d7d0fb7b86c63b),
                bytes32(0x2953bc9d2dfc756b8d46e849da5971dbe1989603b06b7235627529d2e0e5df1d)
            ]
        });
        uint256 prevRandao = 0xa97f47e048f1ddf11b7a8d2c265014cfcec2506d765a393406f6046960d059dc;

        Randao randao = new Randao(AXIOM_ADDRESS, 15537393);
        randao.verifyRandao(testBlock, proof);
        require(randao.prevRandaos(testBlock.blockNumber) == prevRandao, "prevRandao not verified");
    }

    function testVerifyRandaoOld() public {
        vm.createSelectFork("mainnet", 16_513_500);

        // Import block header RLP as calldata
        string[] memory inputs = new string[](2);
        inputs[0] = "cat";
        inputs[1] = "test/data/test.calldata";
        bytes memory headerRlp = vm.ffi(inputs);

        IAxiomV1.BlockHashWitness memory testBlock = IAxiomV1Verifier.BlockHashWitness({
            blockNumber: 16509301,
            claimedBlockHash: bytes32(0x034ca3921f2ab605c8681288ba4c9818978a12e69c57e82350301fb58e1a9a6b),
            prevHash: bytes32(0xf21f9ac46b21ce128bf245ac8c5dcd12ab1bf6a0cb0e3c7dc4d33cc8871d8ab3),
            numFinal: 1024,
            merkleProof: [
                bytes32(0x3b4e49db58e4dab1931689ab67e24eb79660f2661034280bf8f4480071294456),
                bytes32(0xc7e1e977b5d68588e8643956ff13a20cf95c4a76e6ffb168d8faca06413d8c45),
                bytes32(0xaa558831681ec38ab0face0d6eab566ae490d8bdf00e92f27d992836c10372d3),
                bytes32(0x69384d455682d10dbc617296b17a8715d109d1b74ab74037d48e521122048810),
                bytes32(0x62d103378fc33e7f8578480846a0b5634c083167eb621bf0122cd312e34862df),
                bytes32(0x7f3a0dfb38decbb536032102f62f6786dc5c7ac3ed73b283bbc73ba3ea07406b),
                bytes32(0x8b3e437e20a1d5da7d018acfec8129a3071085fb2a14c48712e12d13ecb16014),
                bytes32(0xbe109e17256d615dc1fa6e241fa424247ede44bdadc36fa48fbfe71895f95d5d),
                bytes32(0x3afb75397f28a7fbd51498e7a109865e34edf93ecce9ba4686d7d0fb7b86c63b),
                bytes32(0x2953bc9d2dfc756b8d46e849da5971dbe1989603b06b7235627529d2e0e5df1d)
            ]
        });
        uint256 prevRandao = 0xa97f47e048f1ddf11b7a8d2c265014cfcec2506d765a393406f6046960d059dc;

        Randao randao = new Randao(AXIOM_ADDRESS, 15537394);
        randao.verifyRandao(testBlock, headerRlp);
        require(randao.prevRandaos(testBlock.blockNumber) == prevRandao, "prevRandao not verified");
    }
}
