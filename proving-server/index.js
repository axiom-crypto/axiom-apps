const express = require("express");
const rateLimit = require("express-rate-limit");
const http = require("http");
const WebSocket = require("ws");
const hash = require("object-hash");
const fs = require("fs");
const { spawn, exec } = require("child_process");
const cors = require("cors");
const path = require("path");

const { ethers, BigNumber } = require("ethers");
const { nextTick, send } = require("process");
const INFURA_ID = fs.readFileSync("INFURA_ID", "utf8").trim();
const MAINNET_RPC_PROVIDER_URL = "https://mainnet.infura.io/v3/" + INFURA_ID;
const GOERLI_RPC_PROVIDER_URL = "https://goerli.infura.io/v3/" + INFURA_ID;
const mainnetProvider = new ethers.providers.JsonRpcProvider(
  MAINNET_RPC_PROVIDER_URL
);
const goerliProvider = new ethers.providers.JsonRpcProvider(
  GOERLI_RPC_PROVIDER_URL
);

const app = express();

app.use(express.static("public"));
app.use(express.json());

// rate limit rule
/*const apiRequestLimiter = rateLimit({
  windowMs: 1000,
  max: 2,
  handler: (req, res) => {
    return res.status(429).json({
      error: "You sent too many requests. Please wait a while then try again",
    });
  },
});

app.use(apiRequestLimiter);*/

// initialize a simple http server
const server = http.createServer(app);

// initialize a headless WebSocket server instance
const wss = new WebSocket.Server({ clientTracking: false, noServer: true });

app.get("/", (req, res) => res.send("Im a teapot"));

// store cached proofs in "root/outputs" directory
const outputDataPath = path.resolve(__dirname, "data");
if (!fs.existsSync(outputDataPath)) {
  fs.mkdirSync(outputDataPath);
}

app.use(cors({ origin: "*" }));

var currentProcessesRunning = new Set();
var queue = [];

const sendProof = (ws, proofFilePath) => {
  try {
    const resultProof = fs.readFileSync(proofFilePath, "utf8");
    // console.log(resultProof);
    const result = {
      proof: resultProof,
    };
    ws.send(JSON.stringify(result), () => {
      ws.close(1000);
    });
  } catch (e) {
    console.log("error", e);
    ws.close(1007, "Error occurred in trying to fetch proof.");
  }
};

const inQueue = (ws, id) => {
  // check if hash is in queue
  return queue.includes([ws, id]);
};

const startNewProcess = (ws, id) => {
  let { blockNumber: blockNumber, address: address, slot: slot } = id;
  if (!blockNumber || !address || !slot) {
    return ws.close(1011, "Queue process malformed.");
  }

  const proofName = `calldata_storage_${blockNumber}_${address}_${slot}.dat`;
  const proofFilePath = path.join(outputDataPath, proofName);
  // no need to start new process if cached file already exists
  if (fs.existsSync(proofFilePath)) {
    return sendProof(ws, proofFilePath);
  }

  console.log(id);
  // spawn a child process to run the proof generation
  const prover = spawn(
    "sh",
    ["exec_prover_job.sh", blockNumber, address, slot],
    {
      timeout: 0, // 60 * 60 * 1000,
    }
  );
  if (!prover.pid) {
    return ws.close(1011, "Server side error.");
  }
  currentProcessesRunning.add(id);

  /*
  prover.stdout.on("data", (data) => {
    currentProcessesRunning.delete(id);
    console.log("proof done");
    sendProof(ws, proofFilePath);
    processQueue();
    prover.kill();
  });

  prover.stderr.on("data", (data) => {
    console.error(`stderr: ${data}`);
    fs.writeFile(proofFilePath, '{"result": "Proof failed."}', (err) => {
      if (err) console.log(err);
    });
    currentProcessesRunning.delete(id);
    sendProof(ws, proofFilePath);
    processQueue();
    prover.kill();
  });
  */

  prover.on("close", (code) => {
    currentProcessesRunning.delete(id);
    sendProof(ws, proofFilePath);
    prover.kill();
    processQueue();
    console.log(`child process exited with code ${code}`);
  });
  return true;
};

const processQueue = () => {
  if (currentProcessesRunning.size >= 1) return null;

  // remove duplicates from queue
  queue = queue.filter(
    (item, index, self) => index === self.findIndex((t) => t === item)
  );

  // get top element from queue
  const nextProcess = queue.shift();
  if (!nextProcess) return;
  let ws = nextProcess[0];
  let id = nextProcess[1];
  if (!id || ws.readyState !== WebSocket.OPEN) {
    console.log("Something weird is in the queue, skipping.");
    return;
  }

  const status = startNewProcess(ws, id);
  return status;
};

// if client sends /generate_proof GET request, upgrade to websocket
server.on("upgrade", (request, socket, head) => {
  const { pathname } = require("url").parse(request.url);

  if (pathname === "/generate_proof") {
    wss.handleUpgrade(request, socket, head, (ws) => {
      wss.emit("connection", ws, request);
    });
  } else {
    socket.destroy();
  }
});

wss.on("connection", (ws) => {
  ws.on("message", (data) => {
    try {
      let input = JSON.parse(data);
      let { blockNumber: blockNumber, address: address, slot: slot } = input;
      blockNumber = BigNumber.from(blockNumber).toHexString().substring(2);
      address = BigNumber.from(address).toHexString().substring(2);
      slot = BigNumber.from(slot).toHexString().substring(2);
      if (blockNumber[0] == "0") {
        blockNumber = blockNumber.substring(1);
      }
      if (address[0] == "0") {
        address = address.substring(1);
      }
      if (slot[0] == "0") {
        slot = slot.substring(1);
      }
      input = { blockNumber: blockNumber, address: address, slot: slot };
      const inputHash = hash(input);
      //console.log("input", input);
      //console.log("inputFilePath", inputFilePath);

      // input is already being processed, so do nothing
      if (inQueue(ws, inputHash)) {
        return;
      }

      // otherwise add to queue
      queue.push([ws, input]);
      const status = processQueue();
    } catch (error) {
      console.error(error);
      ws.close(1003, "Input is misformatted");
    }
  });
});

app.post("/generate_proof_slow", async function (req, res) {
  const input = req.body["id"];

  const { proof, publicSignals } = await snarkjs.groth16.fullProve(
    input,
    "./circuit.wasm",
    "./circuit.zkey"
  );

  const genCalldata = await genSolidityCalldata(publicSignals, proof);

  res.json(genCalldata);
});

const port = process.env.PORT || 3002;

server.listen(port, () => {
  console.log(`Server started on port ${server.address().port} :)`);
});
