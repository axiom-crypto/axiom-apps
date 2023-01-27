const ws = require("ws");

const client = new ws("ws://localhost:3000/generate_proof");

client.on("open", () => {
  // Causes the server to print "Hello"
  client.send('{"a":"6","b":"11"}');
  //client.send('{"a":"7","b":"51"}');
  //client.send('{"a":"5","b":"77"}');
});

client.on("message", (data) => {
  console.log(JSON.parse(data));
});

client.on("close", (code, reason) => {
  console.log("Error code: " + code);
  console.log("Reason: " + reason);
});
