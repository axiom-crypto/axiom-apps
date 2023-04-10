#![feature(return_position_impl_trait_in_trait)]
#![allow(incomplete_features)]
use axiom_scaffold::{
    axiom_eth::{
        rlp::builder::{RlcThreadBreakPoints, RlcThreadBuilder},
        util::{
            circuit::{PinnableCircuit, PreCircuit},
            AssignedH256, EthConfigPinning,
        },
        Field,
    },
    containers::ByteString,
    halo2_base::{
        gates::{builder::CircuitBuilderStage, GateInstructions},
        halo2_proofs::{
            halo2curves::bn256::{Bn256, Fr},
            poly::{commitment::Params, kzg::commitment::ParamsKZG},
        },
        AssignedValue,
        QuantumCell::Constant,
    },
    scaffold::AxiomChip,
};
use ethers_core::types::Address;
use ethers_providers::{Http, Provider};
use std::{env::set_var, iter, sync::Arc};

pub mod helpers;
#[cfg(test)]
mod tests;

#[derive(Clone, Debug)]
pub struct AccountAgeInstanceAssigned<F: Field> {
    prev_block_hash: AssignedH256<F>,
    curr_block_hash: AssignedH256<F>,
    curr_block_number: AssignedValue<F>,
    address: AssignedValue<F>,
}

/// `claimed_block_number` is the claimed block number where account `address` made its first transaction,
/// i.e., the first block where the account nonce becomes nonzero.
///
/// We also check that the address is an EOA account by checking that the codehash is EMPTYCODEHASH
///
/// Returns assigned instance but does not expose instance to be public.
pub fn prove_account_age<F: Field>(
    axiom: &mut AxiomChip<F>,
    provider: &Provider<Http>,
    address: Address,
    claimed_block_number: u32,
) -> AccountAgeInstanceAssigned<F> {
    assert!(
        claimed_block_number > 0,
        "We do not support accounts that made a transaction in the genesis block"
    );

    let prev_pf = axiom.eth_getProof(provider, address, vec![], claimed_block_number - 1);
    let prev_witness = axiom.storage_witness().last().unwrap();
    let prev_nonce: ByteString<F> = prev_witness.acct_witness.get("nonce").into();

    let curr_pf = axiom.eth_getProof(provider, address, vec![], claimed_block_number);
    let curr_witness = axiom.storage_witness().last().unwrap();

    let ctx = &mut axiom.ctx();
    // address should not be empty
    axiom.gate().assert_is_const(ctx, &curr_pf.address_is_empty, &F::zero());
    let curr_nonce: ByteString<F> = curr_witness.acct_witness.get("nonce").into();
    // @dev: it would be more efficient to work with the RLC value of curr_nonce, but for code simplicity we just evaluate
    let curr_nonce = curr_nonce.evaluate(ctx, axiom.gate());

    // Check nonce at block k is nonzero
    let is_nonce_zero = axiom.gate().is_zero(ctx, curr_nonce);
    axiom.gate().assert_is_const(ctx, &is_nonce_zero, &F::zero());

    // Check codehash of account at block `claimed_block_number` is EMPTYCODEHASH
    let empty_code_hash = [
        0xc5, 0xd2, 0x46, 0x01, 0x86, 0xf7, 0x23, 0x3c, 0x92, 0x7e, 0x7d, 0xb2, 0xdc, 0xc7, 0x03,
        0xc0, 0xe5, 0x00, 0xb6, 0x53, 0xca, 0x82, 0x27, 0x3b, 0x7b, 0xfa, 0xd8, 0x04, 0x5d, 0x85,
        0xa4, 0x70,
    ];
    const EMPTYCODEHASH_LEN: usize = 32;
    let code_hash: ByteString<F> = curr_witness.acct_witness.get("codeHash").into();
    axiom.gate().assert_is_const(ctx, &code_hash.len, &F::from(EMPTYCODEHASH_LEN as u64));
    assert!(code_hash.bytes.len() >= EMPTYCODEHASH_LEN);
    for (empty_code_hash_byte, byte) in empty_code_hash.into_iter().zip(code_hash.bytes.iter()) {
        axiom.gate().assert_is_const(ctx, byte, &F::from(empty_code_hash_byte));
    }

    let curr_block_number = curr_pf.block_number;
    let address = curr_pf.address;

    // Check queried address is the same in each block
    ctx.constrain_equal(&address, &prev_pf.address);

    let prev_block_number = prev_pf.block_number;
    // Check prev_block_number = curr_block_number - 1
    let prev_plus_one = axiom.gate().add(ctx, prev_block_number, Constant(F::one()));
    ctx.constrain_equal(&curr_block_number, &prev_plus_one);
    // Check nonce at block curr_block_number - 1 is zero
    let prev_nonce = prev_nonce.evaluate(ctx, axiom.gate());
    axiom.gate().assert_is_const(ctx, &prev_nonce, &F::zero());

    AccountAgeInstanceAssigned {
        prev_block_hash: prev_pf.block_hash,
        curr_block_hash: curr_pf.block_hash,
        curr_block_number,
        address,
    }
}

#[derive(Clone, Debug)]
/// Circuit to prove the age of an EOA address.
/// Age is defined (for now) as the first block this address created a transaction.
///
/// Circuit public instances: total 6 field elements:
// TODO: parent hash is not necessary
/// * 0..2: `prev_block_hash` (32 bytes), the parent hash of `curr_block_number`, split into two field elements (hi, lo u128)
/// * 2..4: `curr_block_hash` (32 bytes), the block hash of `curr_block_number`, split into two field elements (hi, lo u128)
/// * 4: `curr_block_number` (4 bytes), the block of the first transaction
/// * 5: `address` (20 bytes), the EOA address

pub struct AccountAgeCircuit {
    pub provider: Arc<Provider<Http>>,
    pub address: Address,
    pub claimed_block_number: u32,
}

impl AccountAgeCircuit {
    pub fn create<F: Field>(
        self,
        builder: RlcThreadBuilder<F>,
        break_points: Option<RlcThreadBreakPoints>,
    ) -> impl PinnableCircuit<F> {
        let mut axiom = AxiomChip::new(builder);
        let AccountAgeInstanceAssigned {
            prev_block_hash,
            curr_block_hash,
            curr_block_number,
            address,
        } = prove_account_age(&mut axiom, &self.provider, self.address, self.claimed_block_number);

        for instance in iter::empty()
            .chain(prev_block_hash)
            .chain(curr_block_hash)
            .chain([curr_block_number, address])
        {
            axiom.expose_public(instance);
        }

        axiom.create(break_points)
    }
}

impl PreCircuit for AccountAgeCircuit {
    type Pinning = EthConfigPinning;

    fn create_circuit(
        self,
        stage: CircuitBuilderStage,
        pinning: Option<Self::Pinning>,
        params: &ParamsKZG<Bn256>,
    ) -> impl PinnableCircuit<Fr> {
        let builder = match stage {
            CircuitBuilderStage::Prover => RlcThreadBuilder::new(true),
            _ => RlcThreadBuilder::new(false),
        };
        let break_points = pinning.map(|p| p.break_points);
        set_var("DEGREE", params.k().to_string());
        self.create::<Fr>(builder, break_points)
    }
}
