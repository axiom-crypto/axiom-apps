use super::*;
use axiom_eth::providers::{GOERLI_PROVIDER_URL, MAINNET_PROVIDER_URL};
use halo2_base::halo2_proofs::{dev::MockProver, halo2curves::bn256::Fr};

fn get_test_circuit<F: Field>(network: Network) -> UniswapTwapCircuit<F> {
    let infura_id = std::env::var("INFURA_ID").expect("INFURA_ID environmental variable not set");
    let provider_url = match network {
        Network::Mainnet => format!("{MAINNET_PROVIDER_URL}{infura_id}"),
        Network::Goerli => format!("{GOERLI_PROVIDER_URL}{infura_id}"),
    };
    let provider = Provider::<Http>::try_from(provider_url.as_str())
        .expect("could not instantiate HTTP Provider");
    let address;
    let start_block_number;
    let end_block_number;
    match network {
        Network::Mainnet => {
            address = "0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc".parse::<Address>().unwrap();
            start_block_number = 0xf4456b;
            end_block_number = 0xfab942;
        }
        Network::Goerli => {            
            address = "0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc".parse::<Address>().unwrap();
            start_block_number = 0x304e9d;
            end_block_number = 0x304e9e;
        }
    }
    UniswapTwapCircuit::from_provider(&provider, start_block_number, end_block_number, address, network)
}

#[test]
pub fn test_mock_mainnet_uniswap() -> Result<(), Box<dyn std::error::Error>> {
    let k = AppConfigParams::get_uniswap_twap().degree;

    let circuit = get_test_circuit::<Fr>(Network::Mainnet);
    MockProver::run(k, &circuit, vec![circuit.to_instance()]).unwrap().assert_satisfied();
    Ok(())
}

#[test]
pub fn test_evm_mainnet_uniswap() {
    use std::{fs, path::Path};

    use halo2_base::utils::fs::gen_srs;
    use rand::SeedableRng;
    use snark_verifier_sdk::{
        evm::{evm_verify, gen_evm_proof_shplonk, gen_evm_verifier_shplonk, write_calldata},
        gen_pk,
        halo2::{
            aggregation::{load_verify_circuit_degree, PublicAggregationCircuit},
            gen_snark_shplonk,
        },
        CircuitExt,
    };

    let mut rng = rand_chacha::ChaChaRng::from_seed([0; 32]);

    let uniswap_twap_snark = {
        let k = AppConfigParams::get_uniswap_twap().degree;
        let circuit = get_test_circuit::<Fr>(Network::Mainnet);
        let params = gen_srs(k);
        let pk = gen_pk(&params, &circuit, Some(Path::new("data/uniswap_twap/pk_uniswap_circuit.dat")));
        gen_snark_shplonk(&params, &pk, circuit, &mut rng, None::<&str>)
    };

    let k = load_verify_circuit_degree();
    let params = gen_srs(k);
    let evm_circuit = PublicAggregationCircuit::new(
        &params,
        vec![uniswap_twap_snark],
        false,
        &mut rng,
    );
    let pk = gen_pk(&params, &evm_circuit, Some(Path::new("data/uniswap_twap/pk_evm_circuit.dat")));

    let instances = evm_circuit.instances();
    let num_instances = instances[0].len();
    let proof = gen_evm_proof_shplonk(&params, &pk, evm_circuit, instances.clone(), &mut rng);
    fs::create_dir_all("data/uniswap_twap").unwrap();
    write_calldata(&instances, &proof, Path::new("data/uniswap_twap/test.calldata")).unwrap();

    let deployment_code = gen_evm_verifier_shplonk::<PublicAggregationCircuit>(
        &params,
        pk.get_vk(),
        vec![num_instances],
        Some(Path::new("data/uniswap_twap/test.yul")),
    );

    evm_verify(deployment_code, instances, proof);
}
