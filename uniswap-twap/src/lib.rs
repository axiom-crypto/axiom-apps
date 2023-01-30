#[cfg(feature = "display")]
use ark_std::{end_timer, start_timer};
use num_bigint::BigUint;
use num_traits::identities::One;
use axiom_eth::{
    block_header::{EthBlockHeaderChip, BLOCK_NUMBER_MAX_BYTES, EthBlockHeaderTraceWitness, EthBlockHeaderTrace},
    mpt::MPTFixedKeyProof,
    storage::{EthBlockStorageInput, EthStorageChip, EthBlockAccountStorageTraceWitness, EthBlockAccountStorageTrace},
    util::{
        bytes_be_to_u128, bytes_be_var_to_fixed, encode_h256_to_field,
        EthConfigParams, encode_u256_to_field,
    },
    EthChip, EthConfig, Field, Network,
};
use core::{iter, marker::PhantomData};
use ethers_core::types::{Address, H256, U256};
use ethers_providers::{Http, Provider};
use halo2_base::{
    gates::{GateInstructions, RangeInstructions},
    halo2_proofs::{
        circuit::{Layouter, SimpleFloorPlanner},
        plonk::{Circuit, ConstraintSystem, Error},
    },
    utils::{PrimeField},
    AssignedValue, Context, ContextParams,
    QuantumCell::Existing,
    SKIP_FIRST_PASS,
};
use serde::{Deserialize, Serialize};
use snark_verifier_sdk::CircuitExt;
use std::{env::var, fs::File};

#[cfg(test)]
mod tests;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct AppConfigParams {
    pub degree: u32,
    // number of SecondPhase advice columns used in RlcConfig
    pub num_rlc_columns: usize,
    // the number of advice columns in phase _ without lookup enabled that RangeConfig uses
    pub num_range_advice: Vec<usize>,
    // the number of advice columns in phase _ with lookup enabled that RangeConfig uses
    pub num_lookup_advice: Vec<usize>,
    pub num_fixed: usize,
    // for keccak chip you should know the number of unusable rows beforehand
    pub unusable_rows: usize,
    pub keccak_rows_per_round: usize,
}

impl Into<EthConfigParams> for AppConfigParams {
    fn into(self) -> EthConfigParams {
        EthConfigParams {
            degree: self.degree,
            num_rlc_columns: self.num_rlc_columns,
            num_range_advice: self.num_range_advice,
            num_lookup_advice: self.num_lookup_advice,
            num_fixed: self.num_fixed,
            unusable_rows: self.unusable_rows,
            keccak_rows_per_round: self.keccak_rows_per_round,
        }
    }
}

impl AppConfigParams {
    pub fn get_uniswap_twap() -> Self {
        let path =
            var("UNISWAP_TWAP_CONFIG").unwrap_or_else(|_| "configs/uniswap_twap.json".to_string());
        println!("{:?}", path);
        serde_json::from_reader(
            File::open(&path).unwrap_or_else(|e| panic!("{path} does not exist. {e:?}")),
        )
        .unwrap()
    }
}

#[derive(Clone)]
pub struct UniswapTwapInstance {
    start_block_hash: H256,
    start_block_number: u32,
    end_block_hash: H256,        
    end_block_number: u32,
    twap_pri: U256,
}

#[derive(Clone)]
pub struct UniswapTwapInput {
    start_block_input: Vec<u8>,
    start_block_storage_input: EthBlockStorageInput,
    end_block_input: Vec<u8>,
    end_block_storage_input: EthBlockStorageInput,
}

pub struct UniswapTwapInputAssigned<'v, F: Field> {
    pub start_acct_pf: MPTFixedKeyProof<'v, F>,
    pub end_acct_pf: MPTFixedKeyProof<'v, F>,
}

impl UniswapTwapInput {
    pub fn assign<'v, F: Field>(
        &self,
        ctx: &mut Context<'_, F>,
        gate: &impl GateInstructions<F>,
    ) -> UniswapTwapInputAssigned<'v, F> {
        let start_acct_pf = self.start_block_storage_input.storage.acct_pf.assign(ctx, gate);
        let end_acct_pf = self.end_block_storage_input.storage.acct_pf.assign(ctx, gate);
        UniswapTwapInputAssigned { start_acct_pf, end_acct_pf }
    }
}

#[derive(Clone)]
pub struct UniswapTwapCircuit<F> {
    input: UniswapTwapInput,
    instance: UniswapTwapInstance,
    network: Network,
    address: Address,
    _marker: PhantomData<F>,
}

impl<F: Field> UniswapTwapCircuit<F> {
    //  if (numerator == 0) return FixedPoint.uq112x112(0);
    //
    //  if (numerator <= uint144(-1)) {
    //      uint256 result = (numerator << RESOLUTION) / denominator;
    //      require(result <= uint224(-1), 'FixedPoint::fraction: overflow');
    //      return uq112x112(uint224(result));
    //  } else {
    //      uint256 result = FullMath.mulDiv(numerator, Q112, denominator);
    //      require(result <= uint224(-1), 'FixedPoint::fraction: overflow');
    //      return uq112x112(uint224(result));
    //  }
    // assumes a, b are u112, outputs a uq112x112
    pub fn div_to_uq112x112(a: U256, b: U256) -> U256 {
        assert!(b != U256::zero());
        (a * U256::from(2).pow(U256::from(112))) / b
    }

    // def currentCumulativePrice(k):
    //     increment = uint(reserve0(k) / reserve1(k)) * (blockTimestamp(k) - blockTimestampLast(k))
    //     return price0CumulativeLast(k) + increment  
    pub fn currentCumulativePrice(
        reserve0: U256,
        reserve1: U256,
        blockTimestamp: u32,
        blockTimestampLast: u32,
        price1CumulativeLast: U256
    ) -> U256 {
        let increment = Self::div_to_uq112x112(reserve0, reserve1) * (blockTimestamp - blockTimestampLast);
        price1CumulativeLast + increment
    }    

    // def TWAP(k1, k2): 
    //     return (currentCumulativePrice(k2) - currentCumulativePrice(k1)) /
    //            (blockTimestamp(k2) - blockTimestamp(k1))
    // outputs a uq112x112
    pub fn compute_twap(
        start_reserve0: U256,
        start_reserve1: U256,
        start_blockTimestampLast: u32,
        start_price1CumulativeLast: U256,
        start_blockTimestamp: u32,
        end_reserve0: U256,
        end_reserve1: U256,
        end_blockTimestampLast: u32,
        end_price1CumulativeLast: U256,
        end_blockTimestamp: u32,        
    ) -> U256 {
        let end_cumulativePrice = Self::currentCumulativePrice(
            end_reserve0, end_reserve1, end_blockTimestamp, end_blockTimestampLast, end_price1CumulativeLast
        );
        let start_cumulativePrice = Self::currentCumulativePrice(
            start_reserve0, start_reserve1, start_blockTimestamp, start_blockTimestampLast, start_price1CumulativeLast
        );
        (end_cumulativePrice - start_cumulativePrice) / (end_blockTimestamp - start_blockTimestamp)
    }

    // within a word, the layout is: blockTimestampLast (32) | reserve1 (112) | reserve0 (112)
    pub fn parse_reserves(reserves: U256) -> (U256, U256, u32) {
        let blockTimestampLast = reserves.div_mod(U256::from(2).pow(U256::from(224))).0.low_u32();        
        let reserve1 = (reserves.div_mod(U256::from(2u8).pow(U256::from(224))).1).div_mod(U256::from(2).pow(U256::from(112))).0;
        let reserve0 = reserves.div_mod(U256::from(2u8).pow(U256::from(112))).1;
        (reserve0, reserve1, blockTimestampLast)
    }

    pub fn from_provider(
        provider: &Provider<Http>,
        start_block_number: u32,
        end_block_number: u32,
        address: Address,
        network: Network,
    ) -> Self {
        use axiom_eth::block_header::{
            GOERLI_BLOCK_HEADER_RLP_MAX_BYTES, MAINNET_BLOCK_HEADER_RLP_MAX_BYTES,
        };
        use axiom_eth::providers::get_block_storage_input;

        let slots = vec![
            H256::from_low_u64_be(8u64), // reserve0, reserve1, blockTimestampLast
            H256::from_low_u64_be(10u64), // price1CumulativeLast
        ];
        let start_block_storage_input = get_block_storage_input(
            provider,
            start_block_number,
            address,
            slots.clone(), 
            8,      //acct_pf_max_depth,
            8,      //storage_pf_max_depth,
        );
        let end_block_storage_input = get_block_storage_input(
            provider,
            end_block_number,
            address,
            slots.clone(), 
            8,      //acct_pf_max_depth,
            8,      //storage_pf_max_depth,
        );        

        // Pad block header RLPs to max size
        let header_rlp_max_bytes = match network {
            Network::Mainnet => MAINNET_BLOCK_HEADER_RLP_MAX_BYTES,
            Network::Goerli => GOERLI_BLOCK_HEADER_RLP_MAX_BYTES,
        };
        let mut start_block_rlps = start_block_storage_input.block_header.clone();           
        start_block_rlps.resize(header_rlp_max_bytes, 0u8);                
        let mut end_block_rlps = end_block_storage_input.block_header.clone();
        end_block_rlps.resize(header_rlp_max_bytes, 0u8);        

        let (start_reserve0, start_reserve1, start_blockTimestampLast) = Self::parse_reserves(
            start_block_storage_input.storage.storage_pfs[0].1
        );
        let start_price1CumulativeLast = start_block_storage_input.storage.storage_pfs[1].1;
        let start_blockTimestamp = start_block_storage_input.block.timestamp;  

        let (end_reserve0, end_reserve1, end_blockTimestampLast) = Self::parse_reserves(
            end_block_storage_input.storage.storage_pfs[0].1
        );
        let end_price1CumulativeLast = end_block_storage_input.storage.storage_pfs[1].1;
        let end_blockTimestamp = end_block_storage_input.block.timestamp;
        let twap_pri = Self::compute_twap(
            start_reserve0, 
            start_reserve1, 
            start_blockTimestampLast, 
            start_price1CumulativeLast, 
            start_blockTimestamp.low_u32(), 
            end_reserve0, 
            end_reserve1, 
            end_blockTimestampLast, 
            end_price1CumulativeLast, 
            end_blockTimestamp.low_u32()
        );

        let input = UniswapTwapInput {
            start_block_input: start_block_rlps,
            start_block_storage_input: start_block_storage_input.clone(),
            end_block_input: end_block_rlps,
            end_block_storage_input: end_block_storage_input.clone(),
        };
        let instance = UniswapTwapInstance {
            start_block_number,
            start_block_hash: start_block_storage_input.block_hash,
            end_block_number,
            end_block_hash: end_block_storage_input.block_hash,
            twap_pri,
        };

        Self { input, instance, network, address, _marker: PhantomData }
    }

    pub fn to_instance(&self) -> Vec<F> {
        let mut instance = Vec::with_capacity(4);
        instance.extend(encode_h256_to_field::<F>(&self.instance.start_block_hash));
        instance.extend(encode_h256_to_field::<F>(&self.instance.end_block_hash));
        instance.push(F::from(self.instance.start_block_number as u64));
        instance.push(F::from(self.instance.end_block_number as u64));
        instance.push({
            let [twap_hi, twap_lo]: [F; 2] = encode_u256_to_field(&self.instance.twap_pri);
            twap_hi * F::from(2u64).pow(&[128, 0, 0, 0]) + twap_lo
        });
        instance
    }
}

impl<F: Field + PrimeField> Circuit<F> for UniswapTwapCircuit<F> {
    type Config = EthConfig<F>;
    type FloorPlanner = SimpleFloorPlanner;

    fn without_witnesses(&self) -> Self {
        self.clone()
    }

    fn configure(meta: &mut ConstraintSystem<F>) -> Self::Config {
        let params = AppConfigParams::get_uniswap_twap();
        EthConfig::configure(meta, params, 0)
    }

    fn synthesize(
        &self,
        config: EthConfig<F>,
        mut layouter: impl Layouter<F>,
    ) -> Result<(), Error> {
        #[cfg(feature = "display")]
        let witness_gen = start_timer!(|| "synthesize");

        let gamma = layouter.get_challenge(config.rlc().gamma);
        config.range().load_lookup_table(&mut layouter).expect("load range lookup table");
        config.keccak().load_aux_tables(&mut layouter).expect("load keccak lookup tables");

        let mut first_pass = SKIP_FIRST_PASS;
        let mut instances = vec![];
        layouter
            .assign_region(
                || "Verify Uniswap v2 TWAP from startBlock to endBlock",
                |region| {
                    if first_pass {
                        first_pass = false;
                        return Ok(());
                    }
                    let mut chip = EthChip::new(config.clone(), gamma);
                    let mut aux = Context::new(
                        region,
                        ContextParams {
                            max_rows: chip.gate().max_rows,
                            num_context_ids: 2, // ?
                            fixed_columns: chip.gate().constants.clone(),
                        },
                    );
                    let ctx = &mut aux;

                    // ================= FIRST PHASE ================
                    let input = self.input.assign(ctx, chip.gate()); // Assigned input

                    // Witness for blocks start_block and end_block
                    let [start_block_witness, end_block_witness]: [EthBlockHeaderTraceWitness<F>; 2] = 
                    [self.input.start_block_input.clone(), self.input.end_block_input.clone()].iter().map(|block_header| {
                        chip.decompose_block_header_phase0(ctx, block_header, self.network)
                    }).collect::<Vec<_>>()
                    .try_into()
                    .unwrap();

                    let [start_storage_witness, end_storage_witness]: [EthBlockAccountStorageTraceWitness<F>; 2] = 
                    [self.input.start_block_storage_input.clone(), self.input.end_block_storage_input.clone()].iter().map(|storage_input| {
                        let input = storage_input.assign(ctx, chip.gate());
                        chip.parse_eip1186_proofs_from_block_phase0(ctx, input, self.network)
                    }).collect::<Vec<_>>()
                    .try_into()
                    .unwrap();    

                    chip.assign_phase0(ctx);
                    ctx.next_phase();

                    // ================= SECOND PHASE ================
                    // Get challenge now that it has been squeezed
                    chip.get_challenge(ctx);
                    // Generate and constrain RLCs for keccak table
                    chip.keccak_assign_phase1(ctx);

                    // Traces for blocks and storage proofs
                    let [start_block_trace, end_block_trace]: [EthBlockHeaderTrace<F>; 2] = [start_block_witness, end_block_witness].iter().map(|block_witness| {
                        chip.decompose_block_header_phase1(ctx, block_witness.clone())
                    }).collect::<Vec<_>>()
                    .try_into()
                    .unwrap();
                    let [start_storage_trace, end_storage_trace]: [EthBlockAccountStorageTrace<F>; 2] = [start_storage_witness, end_storage_witness].iter().map(|storage_witness| {
                        chip.parse_eip1186_proofs_from_block_phase1(ctx, storage_witness.clone())
                    }).collect::<Vec<_>>()
                    .try_into()
                    .unwrap();
                    
                    let [start_block_hash, end_block_hash]: [Vec<AssignedValue<'_, F>>; 2] = {
                        [start_block_trace.block_hash, end_block_trace.block_hash].iter().map(|block_hash| {
                            let block_hash_bytes = (0..32)
                                .map(|idx| block_hash.values[idx].clone())
                                .collect::<Vec<_>>();
                            bytes_be_to_u128(ctx, chip.gate(), &block_hash_bytes[..])
                                .try_into()
                                .unwrap()
                        }).collect::<Vec<_>>()
                        .try_into()
                        .unwrap()
                    };                                       
                    let [start_block_number, end_block_number]: [Vec<AssignedValue<'_, F>>; 2] = {
                        [start_block_trace.number, end_block_trace.number].iter().map(|block_number| {
                            let block_number_bytes = bytes_be_var_to_fixed(
                                ctx,
                                chip.gate(),
                                &block_number.field_trace.values,
                                &block_number.field_trace.len,
                                BLOCK_NUMBER_MAX_BYTES,
                            );
                            bytes_be_to_u128(ctx, chip.gate(), &block_number_bytes[..])
                                .try_into()
                                .unwrap()
                        }).collect::<Vec<_>>()
                        .try_into()
                        .unwrap()
                    };
                    chip.range().check_less_than(ctx, Existing(&start_block_number[0]), Existing(&end_block_number[0]), 32usize);

                    let zero = chip.gate().load_zero(ctx);
                    let eight = chip.gate().load_constant(ctx, F::from(8));
                    let ten = chip.gate().load_constant(ctx, F::from(10));
                    
                    let [(start_reserves0, start_reserves1, start_blockTimestampLast, start_price1CumulativeLast), 
                         (end_reserves0, end_reserves1, end_blockTimestampLast, end_price1CumulativeLast)]: [(AssignedValue<F>, AssignedValue<F>, AssignedValue<F>, AssignedValue<F>); 2] = {
                        [start_storage_trace, end_storage_trace].iter().map(|storage_trace| {
                            // check that the queried slot at index 0 is slot 8 for reserves and then parse
                            ctx.constrain_equal(&storage_trace.digest.slots_values[0].0[0], &zero);
                            ctx.constrain_equal(&storage_trace.digest.slots_values[0].0[1], &eight);
                            // blockTimestampLast (32) || reserves1 (112) || reserves0 (112)
                            // in hi-lo form given by (h, l):
                            //      reserves0 = l % 2^112
                            //      reserves1 = (h % 2^96) * 2^16 + (l \ 2^112)
                            //      blockTimestampLast = h / 2^96
                            let reserves = &storage_trace.digest.slots_values[0].1;
                            let (blockTimestampLast, hi1) = chip.range().div_mod(
                                ctx, Existing(&reserves[0]), BigUint::one() << 96, 128usize
                            );
                            let (lo0, reserves0) = chip.range().div_mod(
                                ctx, Existing(&reserves[1]), BigUint::one() << 112, 128usize
                            );
                            let reserves1 = {
                                let pow = chip.gate().load_constant(ctx, F::from(2).pow(&[16, 0, 0, 0]));
                                chip.gate().mul_add(ctx, Existing(&hi1), Existing(&pow), Existing(&lo0))
                            };

                            // check that the queried slot at index 1 is slot 10 for price1CumulativeLast and then parse
                            ctx.constrain_equal(&storage_trace.digest.slots_values[1].0[0], &zero);
                            ctx.constrain_equal(&storage_trace.digest.slots_values[1].0[1], &ten);
                            let [hi, lo] = &storage_trace.digest.slots_values[1].1;
                            let pow = chip.gate().load_constant(ctx, F::from(2).pow(&[128, 0, 0, 0]));
                            let price1CumulativeLast = chip.gate().mul_add(
                                ctx, Existing(&hi), Existing(&pow), Existing(&lo),
                            );
                            (reserves0, reserves1, blockTimestampLast, price1CumulativeLast)
                        }).collect::<Vec<_>>()
                        .try_into()
                        .unwrap()
                    };
                    let [start_timestamp, end_timestamp]: [AssignedValue<F>; 2] = 
                    [start_block_trace.timestamp, end_block_trace.timestamp].into_iter().map(|ts| {
                        let ts_hilo = bytes_be_to_u128(ctx, chip.gate(), &ts.field_trace.values);
                        ts_hilo[0].clone()
                    }).collect::<Vec<_>>()
                    .try_into()
                    .unwrap();

                    let start_currentCumulativePrice = {
                        let numer = {
                            let pow = chip.gate().load_constant(ctx, F::from(2).pow(&[112, 0, 0, 0]));
                            chip.gate().mul(ctx, Existing(&start_reserves0), Existing(&pow))
                        };
                        let frac = chip.range().div_mod_var(ctx, Existing(&numer), Existing(&start_reserves1), 224usize, 112usize).0;
                        let time_diff = chip.gate().sub(ctx, Existing(&start_timestamp), Existing(&start_blockTimestampLast));
                        let increment = chip.gate().mul(ctx, Existing(&frac), Existing(&time_diff));
                        chip.gate().add(ctx, Existing(&start_price1CumulativeLast), Existing(&increment))
                    };
                    let end_currentCumulativePrice = {
                        let numer = {
                            let pow = chip.gate().load_constant(ctx, F::from(2).pow(&[112, 0, 0, 0]));
                            chip.gate().mul(ctx, Existing(&end_reserves0), Existing(&pow))
                        };
                        let frac = chip.range().div_mod_var(ctx, Existing(&numer), Existing(&end_reserves1), 224usize, 112usize).0;
                        let time_diff = chip.gate().sub(ctx, Existing(&end_timestamp), Existing(&end_blockTimestampLast));
                        let increment = chip.gate().mul(ctx, Existing(&frac), Existing(&time_diff));
                        chip.gate().add(ctx, Existing(&end_price1CumulativeLast), Existing(&increment))
                    };                
                    let cumulativePrice_diff = chip.gate().sub(
                        ctx, Existing(&end_currentCumulativePrice), Existing(&start_currentCumulativePrice)
                    );    
                    let timestamp_diff = chip.gate().sub(ctx, Existing(&end_timestamp), Existing(&start_timestamp));
                    let twap_pri = chip.range().div_mod_var(ctx, Existing(&cumulativePrice_diff), Existing(&timestamp_diff), 254usize, 32usize).0;

                    #[cfg(feature = "display")]
                    println!("twap_pri {:?}", twap_pri);
                    println!("twap_pri_instance {:?}", self.instance.twap_pri);
                    instances.extend(
                        iter::empty()
                            .chain([
                                &start_block_hash[0],
                                &start_block_hash[1],
                                &end_block_hash[0],
                                &end_block_hash[1],
                                &start_block_number[0],
                                &end_block_number[0],
                                &twap_pri,
                            ])
                            .map(|assigned| assigned.cell())
                            .cloned(),
                    );

                    chip.range().finalize(ctx);

                    #[cfg(feature = "display")]
                    ctx.print_stats(&["Range", "RLC"]);

                    Ok(())
                },
            )
            .ok();

        for (i, cell) in instances.into_iter().enumerate() {
            layouter.constrain_instance(cell, config.instance, i);
        }
        #[cfg(feature = "display")]
        end_timer!(witness_gen);

        Ok(())
    }
}

impl<F: Field + PrimeField> CircuitExt<F> for UniswapTwapCircuit<F> {
    fn num_instance(&self) -> Vec<usize> {
        vec![7]
    }

    fn instances(&self) -> Vec<Vec<F>> {
        vec![self.to_instance()]
    }
}
