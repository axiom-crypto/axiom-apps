#[cfg(feature = "display")]
use ark_std::{end_timer, start_timer};
use axiom_eth::{
    block_header::{EthBlockHeaderChip, BLOCK_NUMBER_MAX_BYTES},
    mpt::MPTFixedKeyProof,
    storage::{EthBlockStorageInput, EthStorageChip},
    util::{
        bytes_be_to_u128, bytes_be_var_to_fixed, encode_addr_to_field, encode_h256_to_field,
        uint_to_bytes_be, EthConfigParams,
    },
    EthChip, EthConfig, Field, Network,
};
use core::{iter, marker::PhantomData};
use ethers_core::types::{Address, H256};
use ethers_providers::{Http, Provider};
use halo2_base::{
    gates::GateInstructions,
    halo2_proofs::{
        circuit::{Layouter, SimpleFloorPlanner, Value},
        plonk::{Circuit, ConstraintSystem, Error},
    },
    utils::PrimeField,
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
    pub fn get_account_age() -> Self {
        let path =
            var("ACCOUNT_AGE_CONFIG").unwrap_or_else(|_| "configs/account_age.json".to_string());
        println!("{:?}", path);
        serde_json::from_reader(
            File::open(&path).unwrap_or_else(|e| panic!("{path} does not exist. {e:?}")),
        )
        .unwrap()
    }
}

#[derive(Clone)]
pub struct AccountAgeInstance {
    prev_block_hash: H256,
    curr_block_hash: H256,
    curr_block_number: u32,
    addr: Address,
}

#[derive(Clone)]
pub struct AccountAgeInput {
    block_inputs: [Vec<u8>; 2],
    block_storage_inputs: [EthBlockStorageInput; 2],
}

pub struct AccountAgeInputAssigned<'v, F: Field> {
    pub address: [AssignedValue<'v, F>; 2],
    pub acct_pf: [MPTFixedKeyProof<'v, F>; 2],
}

impl AccountAgeInput {
    pub fn assign<'v, F: Field>(
        &self,
        ctx: &mut Context<'_, F>,
        gate: &impl GateInstructions<F>,
    ) -> AccountAgeInputAssigned<'v, F> {
        // TODO: Refactor assignment to be less verbose
        let address: [_; 2] = (0..2)
            .map(|i| {
                let address = encode_addr_to_field(&self.block_storage_inputs[i].storage.addr);
                gate.load_witness(ctx, Value::known(address))
            })
            .collect::<Vec<_>>()
            .try_into()
            .unwrap();
        let acct_pf: [_; 2] = (0..2)
            .map(|i| self.block_storage_inputs[i].storage.acct_pf.assign(ctx, gate))
            .collect::<Vec<_>>()
            .try_into()
            .unwrap();
        AccountAgeInputAssigned { address, acct_pf }
    }
}

#[derive(Clone)]
pub struct AccountAgeCircuit<F> {
    input: AccountAgeInput,
    instance: AccountAgeInstance,
    network: Network,
    _marker: PhantomData<F>,
}

impl<F: Field> AccountAgeCircuit<F> {
    pub fn from_provider(
        provider: &Provider<Http>,
        block_number: u32,
        address: Address,
        network: Network,
    ) -> Self {
        use axiom_eth::block_header::{
            GOERLI_BLOCK_HEADER_RLP_MAX_BYTES, MAINNET_BLOCK_HEADER_RLP_MAX_BYTES,
        };
        use axiom_eth::providers::get_block_storage_input;

        // Retrieve block storage proofs from provider
        let block_storage_inputs: [_; 2] = (0..2)
            .map(|i| {
                get_block_storage_input(
                    provider,
                    block_number - i,
                    address,
                    vec![], // no slots
                    8,      //acct_pf_max_depth,
                    8,      //storage_pf_max_depth,
                )
            })
            .rev()
            .collect::<Vec<_>>()
            .try_into()
            .unwrap();

        // Pad block header RLPs to max size
        let header_rlp_max_bytes = match network {
            Network::Mainnet => MAINNET_BLOCK_HEADER_RLP_MAX_BYTES,
            Network::Goerli => GOERLI_BLOCK_HEADER_RLP_MAX_BYTES,
        };
        let mut block_rlps: [Vec<u8>; 2] = block_storage_inputs
            .iter()
            .map(|i| i.block_header.clone())
            .collect::<Vec<_>>()
            .try_into()
            .unwrap();
        for block_rlp in block_rlps.iter_mut() {
            block_rlp.resize(header_rlp_max_bytes, 0u8);
        }

        let input = AccountAgeInput {
            block_inputs: block_rlps,
            block_storage_inputs: block_storage_inputs.clone(),
        };
        let instance = AccountAgeInstance {
            prev_block_hash: block_storage_inputs[0].block_hash,
            curr_block_hash: block_storage_inputs[1].block_hash,
            curr_block_number: block_number,
            addr: address,
        };

        Self { input, instance, network, _marker: PhantomData }
    }

    pub fn to_instance(&self) -> Vec<F> {
        let mut instance = Vec::with_capacity(4);
        instance.extend(encode_h256_to_field::<F>(&self.instance.prev_block_hash));
        instance.extend(encode_h256_to_field::<F>(&self.instance.curr_block_hash));
        instance.push(F::from(self.instance.curr_block_number as u64));
        instance.push(encode_addr_to_field(&self.instance.addr));
        instance
    }
}

impl<F: Field + PrimeField> Circuit<F> for AccountAgeCircuit<F> {
    type Config = EthConfig<F>;
    type FloorPlanner = SimpleFloorPlanner;

    fn without_witnesses(&self) -> Self {
        self.clone()
    }

    fn configure(meta: &mut ConstraintSystem<F>) -> Self::Config {
        let params = AppConfigParams::get_account_age();
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
                || "Verify account age in block",
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

                    // Witness for blocks k and k-1
                    let block_witnesses = chip.decompose_block_header_chain_phase0(
                        ctx,
                        &self.input.block_inputs,
                        self.network,
                    );

                    // Witness for account at blocks k and k-1
                    let acct_witnesses = (0..2)
                        .map(|i| {
                            let state_root =
                                &block_witnesses[i].rlp_witness.field_witness[3].field_cells;
                            let addr_bytes =
                                uint_to_bytes_be(ctx, chip.range(), &input.address[i], 20);
                            let acct_witness = chip.parse_account_proof_phase0(
                                ctx,
                                state_root,
                                addr_bytes,
                                input.acct_pf[i].clone(),
                            );
                            acct_witness
                        })
                        .collect::<Vec<_>>();

                    chip.assign_phase0(ctx);
                    ctx.next_phase();

                    // ================= SECOND PHASE ================
                    // Get challenge now that it has been squeezed
                    chip.get_challenge(ctx);
                    // Generate and constrain RLCs for keccak table
                    chip.keccak_assign_phase1(ctx);

                    // Traces for blocks k and k-1, and account
                    let block_traces =
                        chip.decompose_block_header_chain_phase1(ctx, block_witnesses, None);
                    let acct_traces = acct_witnesses
                        .into_iter()
                        .map(|acct| chip.parse_account_proof_phase1(ctx, acct))
                        .collect::<Vec<_>>();

                    // Check queried address is the same in each block
                    ctx.constrain_equal(&input.address[0], &input.address[1]);

                    // Check nonce at block k-1 is zero
                    let zero = chip.gate().load_zero(ctx);
                    ctx.constrain_equal(&acct_traces[0].nonce_trace.rlc_val, &zero);

                    // Check nonce at block k is nonzero
                    let is_nonce_zero = chip.gate().is_equal(
                        ctx,
                        Existing(&acct_traces[1].nonce_trace.rlc_val),
                        Existing(&zero),
                    );
                    ctx.constrain_equal(&is_nonce_zero, &zero);

                    // Check codehash of account at block k is EMPTYCODEHASH
                    let empty_code_hash_bytes = [
                        0xc5, 0xd2, 0x46, 0x01, 0x86, 0xf7, 0x23, 0x3c, 0x92, 0x7e, 0x7d, 0xb2,
                        0xdc, 0xc7, 0x03, 0xc0, 0xe5, 0x00, 0xb6, 0x53, 0xca, 0x82, 0x27, 0x3b,
                        0x7b, 0xfa, 0xd8, 0x04, 0x5d, 0x85, 0xa4, 0x70,
                    ];
                    let empty_code_hash = empty_code_hash_bytes
                        .into_iter()
                        .map(|b| chip.gate().load_constant(ctx, F::from(b)))
                        .collect::<Vec<_>>();
                    let empty_code_hash_len = chip.gate().load_constant(ctx, F::from(32));
                    let empty_code_hash_rlc_val = chip
                        .rlc()
                        .compute_rlc(ctx, chip.gate(), empty_code_hash, empty_code_hash_len)
                        .rlc_val;
                    ctx.constrain_equal(
                        &acct_traces[1].code_hash_trace.rlc_val,
                        &empty_code_hash_rlc_val,
                    );

                    // Extract assigned values from block hashes and current block number to
                    // constrain the instance
                    let prev_block_hash: [_; 2] = {
                        let block_hash_bytes = (0..32)
                            .map(|idx| block_traces[0].block_hash.values[idx].clone())
                            .collect::<Vec<_>>();
                        bytes_be_to_u128(ctx, chip.gate(), &block_hash_bytes[..])
                            .try_into()
                            .unwrap()
                    };
                    let curr_block_hash: [_; 2] = {
                        let block_hash_bytes = (0..32)
                            .map(|idx| block_traces[1].block_hash.values[idx].clone())
                            .collect::<Vec<_>>();
                        bytes_be_to_u128(ctx, chip.gate(), &block_hash_bytes[..])
                            .try_into()
                            .unwrap()
                    };
                    let curr_block_number: [_; 1] = {
                        let block_hash_bytes = bytes_be_var_to_fixed(
                            ctx,
                            chip.gate(),
                            &block_traces[1].number.field_trace.values,
                            &block_traces[1].number.field_trace.len,
                            BLOCK_NUMBER_MAX_BYTES,
                        );
                        bytes_be_to_u128(ctx, chip.gate(), &block_hash_bytes[..])
                            .try_into()
                            .unwrap()
                    };
                    let address = input.address[0].clone();
                    instances.extend(
                        iter::empty()
                            .chain([
                                &prev_block_hash[0],
                                &prev_block_hash[1],
                                &curr_block_hash[0],
                                &curr_block_hash[1],
                                &curr_block_number[0],
                                &address,
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

impl<F: Field + PrimeField> CircuitExt<F> for AccountAgeCircuit<F> {
    fn num_instance(&self) -> Vec<usize> {
        vec![6]
    }

    fn instances(&self) -> Vec<Vec<F>> {
        vec![self.to_instance()]
    }
}
