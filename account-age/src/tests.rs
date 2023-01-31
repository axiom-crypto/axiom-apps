use super::*;
use axiom_eth::providers::{GOERLI_PROVIDER_URL, MAINNET_PROVIDER_URL};
use halo2_base::halo2_proofs::{dev::MockProver, halo2curves::bn256::Fr};

fn get_test_circuit<F: Field>(network: Network) -> AccountAgeCircuit<F> {
    let infura_id = std::fs::read_to_string("configs/INFURA_ID").expect("Infura ID not found");
    let provider_url = match network {
        Network::Mainnet => format!("{MAINNET_PROVIDER_URL}{infura_id}"),
        Network::Goerli => format!("{GOERLI_PROVIDER_URL}{infura_id}"),
    };
    let provider = Provider::<Http>::try_from(provider_url.as_str())
        .expect("could not instantiate HTTP Provider");
    let addr;
    let block_number;
    match network {
        Network::Mainnet => {
            // vitalik.eth
            addr = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045".parse::<Address>().unwrap();
            block_number = 0x4dc40;
        }
        Network::Goerli => {
            // vitalik.eth
            addr = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045".parse::<Address>().unwrap();
            block_number = 0x304e9d;
        }
    }
    const ACCOUNT_PROOF_MAX_DEPTH: usize = 10;
    AccountAgeCircuit::from_provider(
        &provider,
        block_number,
        addr,
        network,
        ACCOUNT_PROOF_MAX_DEPTH,
    )
}

#[test]
pub fn test_mock_mainnet_account_age() -> Result<(), Box<dyn std::error::Error>> {
    let k = AppConfigParams::get_account_age().degree;

    let circuit = get_test_circuit::<Fr>(Network::Mainnet);
    MockProver::run(k, &circuit, vec![circuit.to_instance()]).unwrap().assert_satisfied();
    Ok(())
}

#[test]
pub fn test_evm_mainnet_account_age() {
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

    let account_age_snark = {
        let k = AppConfigParams::get_account_age().degree;
        let circuit = get_test_circuit::<Fr>(Network::Mainnet);
        let params = gen_srs(k);
        let pk = gen_pk(&params, &circuit, Some(Path::new("data/account_age/pk_age_circuit.dat")));
        gen_snark_shplonk(&params, &pk, circuit, &mut rng, None::<&str>)
    };

    let k = load_verify_circuit_degree();
    let params = gen_srs(k);
    let evm_circuit =
        PublicAggregationCircuit::new(&params, vec![account_age_snark], false, &mut rng);
    let pk = gen_pk(&params, &evm_circuit, Some(Path::new("data/account_age/pk_evm_circuit.dat")));

    let instances = evm_circuit.instances();
    let num_instances = instances[0].len();
    let proof = gen_evm_proof_shplonk(&params, &pk, evm_circuit, instances.clone(), &mut rng);
    fs::create_dir_all("data/account_age").unwrap();
    write_calldata(&instances, &proof, Path::new("data/account_age/test.calldata")).unwrap();

    let deployment_code = gen_evm_verifier_shplonk::<PublicAggregationCircuit>(
        &params,
        pk.get_vk(),
        vec![num_instances],
        Some(Path::new("data/account_age/test.yul")),
    );

    evm_verify(deployment_code, instances, proof);
}
