//! A ZK oracle for a Uniswap V2 Pair.
//! See https://docs.uniswap.org/contracts/v2/concepts/core-concepts/oracles for contract documentation.
#![feature(return_position_impl_trait_in_trait)]
#![allow(incomplete_features)]
#![allow(non_snake_case)]
use std::{env::set_var, iter, sync::Arc};

use axiom_scaffold::{
    axiom_eth::{
        rlp::builder::{RlcThreadBreakPoints, RlcThreadBuilder},
        storage::EIP1186ResponseDigest,
        util::{
            circuit::{PinnableCircuit, PreCircuit},
            AssignedH256, EthConfigPinning,
        },
        Field,
    },
    containers::ByteString,
    halo2_base::gates::GateInstructions,
    halo2_base::{
        gates::{builder::CircuitBuilderStage, RangeInstructions},
        halo2_proofs::{
            halo2curves::bn256::{Bn256, Fr},
            poly::{commitment::Params, kzg::commitment::ParamsKZG},
        },
        AssignedValue,
        QuantumCell::Constant,
    },
    scaffold::AxiomChip,
};
use ethers_core::types::{Address, H256};
use ethers_providers::{Http, Provider};
use num_bigint::BigUint;
use num_traits::One;

pub mod helpers;
#[cfg(test)]
mod tests;

/// Smart contract storage slot for reserves
pub const UNISWAP_V2_RESERVES_SLOT: u64 = 8;
/// Smart contract storage slot for price1CumulativeLast
pub const UNISWAP_V2_PRICE1CUMULATIVELAST_SLOT: u64 = 10;
// we assume that price1CumulativeLast fits in 253 bits (can probably be even smaller) since it is bounded by maxPrice * timestamp
const PRICECUMULATIVE_CAPACITY: usize = 253;

#[derive(Clone, Copy, Debug)]
pub struct OracleObservation<F: Field> {
    pub block_hash: AssignedH256<F>,
    pub block_number: AssignedValue<F>,
    pub timestamp: AssignedValue<F>,
    pub address: AssignedValue<F>,
    pub reserves0: AssignedValue<F>,
    pub reserves1: AssignedValue<F>,
    pub blockTimestampLast: AssignedValue<F>,
    pub price1CumulativeLast: AssignedValue<F>,
}

#[derive(Clone, Copy, Debug)]
pub struct UniswapV2TwapResponse<F: Field> {
    pub start_block_hash: AssignedH256<F>,
    pub start_block_number: AssignedValue<F>,
    pub pair_address: AssignedValue<F>,
    pub end_block_hash: AssignedH256<F>,
    pub end_block_number: AssignedValue<F>,
    pub twap_pri: AssignedValue<F>,
}

pub trait UniswapV2TwapOracle<F: Field> {
    fn observe_single(
        &mut self,
        provider: &Provider<Http>,
        pair_address: Address,
        block_number: u32,
    ) -> OracleObservation<F>;

    fn compute_twap(
        &mut self,
        provider: &Provider<Http>,
        pair_address: Address,
        start_block_number: u32,
        end_block_number: u32,
    ) -> UniswapV2TwapResponse<F>;
}

impl<F: Field> UniswapV2TwapOracle<F> for AxiomChip<F> {
    fn observe_single(
        &mut self,
        provider: &Provider<Http>,
        pair_address: Address,
        block_number: u32,
    ) -> OracleObservation<F> {
        let reserves_slot = H256::from_low_u64_be(UNISWAP_V2_RESERVES_SLOT);
        let price1CumulativeLast_slot = H256::from_low_u64_be(UNISWAP_V2_PRICE1CUMULATIVELAST_SLOT);
        let EIP1186ResponseDigest {
            block_hash,
            block_number,
            address,
            slots_values,
            address_is_empty,
            slot_is_empty,
        } = self.eth_getProof(
            provider,
            pair_address,
            vec![reserves_slot, price1CumulativeLast_slot],
            block_number,
        );
        let [(slot0, value0), (slot1, value1)]: [_; 2] = slots_values.try_into().unwrap();
        assert_eq!(slot_is_empty.len(), 2);

        let ctx = &mut self.ctx();
        // address should not be empty
        self.gate().assert_is_const(ctx, &address_is_empty, &F::zero());
        // slots should not be empty
        self.gate().assert_is_const(ctx, &slot_is_empty[0], &F::zero());
        self.gate().assert_is_const(ctx, &slot_is_empty[1], &F::zero());
        // constrain slots to be the known constants
        for (slot_const, slot) in [UNISWAP_V2_RESERVES_SLOT, UNISWAP_V2_PRICE1CUMULATIVELAST_SLOT]
            .into_iter()
            .zip([slot0, slot1])
        {
            self.gate().assert_is_const(ctx, &slot[0], &F::zero());
            self.gate().assert_is_const(ctx, &slot[1], &F::from(slot_const));
        }

        let _witness = self.storage_witness().last().unwrap();
        let timestamp: ByteString<F> = _witness.block_witness.get("timestamp").into();
        let timestamp = timestamp.evaluate(ctx, self.gate());

        // parse queries value0: this is a 256-bit value that is concatenation of
        // blockTimestampLast (32) . reserves1 (112) . reserves0 (112)
        // in hi-lo form given by (h, l):
        //      reserves0 = l % 2^112
        //      reserves1 = (h % 2^96) * 2^16 + (l \ 2^112)
        //      blockTimestampLast = h / 2^96
        let [hi, lo] = value0;
        let (blockTimestampLast, hi1) =
            self.range().div_mod(ctx, hi, BigUint::one() << 96, 128usize);
        let (lo0, reserves0) = self.range().div_mod(ctx, lo, BigUint::one() << 112, 128usize);
        let reserves1 = {
            let pow = self.gate().pow_of_two()[16];
            self.gate().mul_add(ctx, hi1, Constant(pow), lo0)
        };

        // parse query value1: price1CumulativeLast in hi-lo form
        let [hi, lo] = value1;
        assert!(
            F::CAPACITY as usize >= PRICECUMULATIVE_CAPACITY,
            "Field needs to have at least {PRICECUMULATIVE_CAPACITY} bits capacity"
        );
        assert!(
            hi.value().get_lower_128() < (1u128 << (PRICECUMULATIVE_CAPACITY - 128)),
            "Error: price1CumulativeLast has more than 253 bits"
        );
        let price1CumulativeLast = {
            let pow = self.gate().pow_of_two()[128];
            self.gate().mul_add(ctx, hi, Constant(pow), lo)
        };

        OracleObservation {
            block_hash,
            block_number,
            timestamp,
            address,
            reserves0,
            reserves1,
            blockTimestampLast,
            price1CumulativeLast,
        }
    }

    fn compute_twap(
        &mut self,
        provider: &Provider<Http>,
        pair_address: Address,
        start_block_number: u32,
        end_block_number: u32,
    ) -> UniswapV2TwapResponse<F> {
        let [start_obs, end_obs] = [start_block_number, end_block_number]
            .map(|block_number| self.observe_single(provider, pair_address, block_number));
        let ctx = &mut self.ctx();
        ctx.constrain_equal(&start_obs.address, &end_obs.address);

        let [start_currentCumulativePrice, end_currentCumulativePrice] =
            [start_obs, end_obs].map(|obs| {
                /*
                def currentCumulativePrice(k):
                    increment = uint(reserveX(k) / reserveY(k)) * (blockTimestamp(k) - blockTimestampLast(k))
                    return priceXCumulativeLast(k) + increment
                */
                let pow112 = self.gate().pow_of_two()[112];
                let numer = self.gate().mul(ctx, obs.reserves0, Constant(pow112));
                let frac = self.range().div_mod_var(ctx, numer, obs.reserves1, 224, 112).0;
                let time_diff = self.gate().sub(ctx, obs.timestamp, obs.blockTimestampLast);
                let increment = self.gate().mul(ctx, frac, time_diff);
                self.gate().add(ctx, obs.price1CumulativeLast, increment)
            });
        let cumulativePrice_diff =
            self.gate().sub(ctx, end_currentCumulativePrice, start_currentCumulativePrice);
        let timestamp_diff = self.gate().sub(ctx, end_obs.timestamp, start_obs.timestamp);
        let twap_pri = self
            .range()
            .div_mod_var(ctx, cumulativePrice_diff, timestamp_diff, PRICECUMULATIVE_CAPACITY, 32)
            .0;
        UniswapV2TwapResponse {
            start_block_hash: start_obs.block_hash,
            start_block_number: start_obs.block_number,
            pair_address: start_obs.address,
            end_block_hash: end_obs.block_hash,
            end_block_number: end_obs.block_number,
            twap_pri,
        }
    }
}

#[derive(Clone, Debug)]
/// Circuit to prove the TWAP between two blocks for a specific UniswapV2Pair
///
/// Public instances: total 6 field elements
/// * 0: `pair_address . start_block_number . end_block_number` is `20 + 4 + 4 = 28` bytes, packed into a single field element
/// * 1..3: `start_block_hash` (32 bytes) is split into two field elements (hi, lo u128)
/// * 3..5: `end_block_hash` (32 bytes) is split into two field elements (hi, lo u128)
/// * 5: `twap_pri` (32 bytes) is single field element representing the computed TWAP
pub struct UniswapV2TwapCircuit {
    pub provider: Arc<Provider<Http>>,
    pub pair_address: Address,
    pub start_block_number: u32,
    pub end_block_number: u32,
}

impl UniswapV2TwapCircuit {
    pub fn create<F: Field>(
        self,
        builder: RlcThreadBuilder<F>,
        break_points: Option<RlcThreadBreakPoints>,
    ) -> impl PinnableCircuit<F> {
        let mut axiom = AxiomChip::new(builder);
        let twap = axiom.compute_twap(
            &self.provider,
            self.pair_address,
            self.start_block_number,
            self.end_block_number,
        );

        assert!(F::CAPACITY >= 248, "Field needs to have at least 248 bits capacity");
        let mut aux = axiom.ctx();
        let ctx = &mut aux;
        let gate = axiom.gate();
        let pow2 = gate.pow_of_two();
        let mut packed =
            gate.mul_add(ctx, twap.start_block_number, Constant(pow2[32]), twap.end_block_number);
        packed = gate.mul_add(ctx, twap.pair_address, Constant(pow2[64]), packed);
        drop(aux);

        for elt in iter::once(packed)
            .chain(twap.start_block_hash)
            .chain(twap.end_block_hash)
            .chain(iter::once(twap.twap_pri))
        {
            axiom.expose_public(elt);
        }

        axiom.create(break_points)
    }
}

impl PreCircuit for UniswapV2TwapCircuit {
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
