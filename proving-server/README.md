# zk-node-server-c

`zk-node-server-c` creates a server for zk-SNARK witness generation and proof creation. This project builds heavily on the `zk-node-server` built by the [Stealthdrop team](https://github.com/nalinbhardwaj/stealthdrop/tree/main/zk-node-server); big thanks and shoutout to them! Their server works great for most applications, so if you're just looking for a server to handle zk-SNARK witness generation and proof creation on moderately sized circuits, I recommend first checking out their work to see if it fits your needs. 

## What's the point of `zk-node-server-c`?

The `zk-node-server` built by the [Stealthdrop team](https://github.com/nalinbhardwaj/stealthdrop/tree/main/zk-node-server) runs witness generation in WASM. However, the WASM witness generator will not work for circuits above a certain constraint size (around 10 million constraints in Circom) due to memory limits, so for large circuits it is instead recommended to use C++ for witness generation, and this requires a different workflow for handling requests. 

## Setup

First, handling large zk-SNARKs requires a specialized environment using `rapidsnark` as well as a patched version of Node.js with no garbage collection. See [this document on best practices for large circuits](https://hackmd.io/V-7Aal05Tiy-ozmzTGBYPA?view) for more details. 

After performing the necessary installations in the linked document, set the `$path_to_rapidsnark_prover` environmental variable. Then clone this repo, run `npm install`, and create an `inputs` subdirectory. 

Set the `$circuit_name` environmental variable, and then build the C++ binary for your circuit's witness generation, following the steps in the best practices document. This should create a `"$circuit_name"_cpp` subdirectory with the executable inside. 

Next, follow the steps in the best practices document to create a zkey for your circuit. This should create a `"$circuit_name".zkey` file in the root directory. 

Finally, run `npm start` to start the server. 

## Acknowledgements

Big thanks again to the [Stealthdrop team](https://github.com/nalinbhardwaj/stealthdrop/tree/main/zk-node-server), who supplied most of the server code. Thanks to [Jonathan Wang](https://github.com/jonathanpwang) and [Yi Sun](https://github.com/yi-sun) as well, for figuring out the best practices for large circuits. This project was part of the [0xPARC](https://0xparc.org) effort to write an [implementation of elliptic curve pairings in Circom](https://github.com/yi-sun/circom-pairing/); the resulting circuit had over 19 million constraints, hence the need for this server. 
