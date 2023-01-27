const ethers = require("ethers");
const fs = require("fs");
const { exec } = require("child_process");
const INFURA_ID = fs.readFileSync("INFURA_ID", "utf8").trim();
const RPC_PROVIDER_URL = "https://mainnet.infura.io/v3/" + INFURA_ID;

const provider = new ethers.providers.JsonRpcProvider(RPC_PROVIDER_URL);

let addr = "0xb47e3cd837ddf8e4c57f05d70ab865de6e193bbb";
let punkSlot =
  "13da86008ba1c6922daee3e07db95305ef49ebced9f5467a0b8613fcc6b343e3";
let blockNumber = "latest";

async function generateStorageInput(addr, dataSlot, blockNumber) {
  if (dataSlot.slice(0, 2) === "0x") dataSlot = dataSlot.slice(2);
  // sanitze dataSlot to make sure it's a hex
  if (/^[0-9A-Fa-f]+$/.test(dataSlot) === false) {
    console.log(dataSlot);
    console.log("Error: tried to input dataSlot that is not hex!");
    return;
  }

  let block = await provider.send("eth_getBlockByNumber", [blockNumber, true]);

  let params = [addr, [dataSlot], blockNumber];
  let proof = await provider.send("eth_getProof", params);

  fs.writeFileSync("punk_block.json", JSON.stringify(block), (err) => {
    if (err) throw err;
  });
  fs.writeFileSync("punk_pfs.json", JSON.stringify(proof), (err) => {
    if (err) throw err;
  });

  // spawn a child process to run shell script that runs python script to generate inputs for zk proof
  exec(
    `./generate_storage_inputs.sh ${dataSlot}`,
    { timeout: 60 * 60 * 10 },
    (error, stdout, stderr) => {
      if (error) {
        console.error(`Python script error: ${error}`);
        return;
      }
      console.log(stdout);
      console.error(stderr);
    }
  );
}

generateStorageInput(addr, punkSlot, blockNumber);
