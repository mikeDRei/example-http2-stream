const http2 = require('http2')
const fs = require('fs')

const server = http2.createSecureServer({
  "key": fs.readFileSync("private.pem"),
  "cert": fs.readFileSync("cert.pem")
  
});
server.on("stream", (stream, headers) =>{
  stream.respond({
    "content-type":"application/json",
    "message": '{"nome":"Michael", "idade":22}'
  })
  stream.end('data ');
  console.log(JSON.stringify(headers))
});

server.listen(8443, () =>{
  console.log("server running")
});

// openssl req -x509 -newkey rsa:4096 -nodes -sha256 -subj '/CN=localhost' 
// -keyout private.pem -out cert.pem
