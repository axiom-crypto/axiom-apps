export prover_dir="../../halo2-mpt"
export path_to_prover="target/release/single_storage_proof"

cd $prover_dir
taskset -c 2-31 $path_to_prover --block-number "0x$1" --address "0x$2" --slot "0x$3" &>> server.log
cat data/calldata_storage_"$1"_"$2"_"$3".dat
