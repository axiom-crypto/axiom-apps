#!/bin/bash

curl -X POST \
-H "Content-Type: application/json" \
-d '{"addr": "0xb47e3cd837ddf8e4c57f05d70ab865de6e193bbb", "dataSlot": "13da86008ba1c6922daee3e07db95305ef49ebced9f5467a0b8613fcc6b343e3", "blockNumber": "0xd895ce"}' \
localhost:3000/generate_storage_input
