const http2 = require('node:http2');
const fs = require('node:fs');
const client = http2.connect('https://localhost:/8443', {
  ca: fs.readFileSync('cert.pem')
});
client.on('error', (err) => console.error(err));

const req = client.request({ ':path': '/' });

req.on('response', (headers, flags) => {
  for (const name in headers) {
    console.log(`${name}: ${headers[name]}`);
  }
  console.log("mensagem vindo do servidor");
  console.log(JSON.parse(headers.message));
});

req.setEncoding('utf8');
let data = '';
req.on('data', (chunk) => { data += chunk; });
req.on('end', () => {
  console.log(`\n${data}`);
  // client.close();
});
req.end();
