
var express = require('express');
var server = express();

// This will be call by APPLE TO VERIFY THE APP-SITE-ASSOCIATION
// Make the 'apple-app-site-association' accessable to apple to verify the association
server.get('/.well-known/apple-app-site-association', function(request, response) {
    console.log("get apple-app-site-association")
  response.sendFile(__dirname +  '/apple-app-site-association.json');
});


// ABOUT PAGE
server.get('/', function(request, response) {
  response.sendFile(__dirname +  '/index.html');
});


server.listen(80, ()=>{
    
    console.log("start listen on 80")
});
