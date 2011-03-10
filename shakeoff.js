var http = require('http'),  
    io   = require('socket.io'),
    fs   = require('fs'),
    sys  = require('sys'),
    repl = require('repl');

var server = http.createServer(function(req, res){ 
  res.writeHead(200, {'Content-Type': 'text/html'}); 

  s = fs.createReadStream('shakeoff.html');
  sys.pump(s, res);
}); 

server.listen(9876);

var socket = io.listen(server); 

//repl.start().context.server = server;

var freeClient = null;
var playArea = 25;

var highScores = [];


socket.on('connection', function(client){
  var pos = 0;
  var score = 0;
  var highScore = null;
  var name = "anonymous";
  client.username = name;
  var nemesis = null;

  var countdownTimer = null;
  startCountdown = function() {
    stopCountdown();
    countdownTimer = setTimeout(function() {
      stopCountdown();
      nemesis && nemesis.emit('gameOver', -100);
      client.emit('gameOver', -100);      
    },10*1000);
  };
  stopCountdown = function() {
    clearTimeout(countdownTimer);
  };

  function getNewNemesis(){
    if (freeClient) {
      var nemesis = freeClient;
      freeClient = null;
    
      client.emit('nemesis', nemesis);
      nemesis.emit('nemesis', client);
      
      startCountdown();
    }
    else {
      freeClient = client;
      client.send(JSON.stringify(['waiting']));
    }
  }
  
  function updateHighScore() {
    if (highScore && !highScore.stale) {
      highScore.score = score;
    }
    else if (highScores.length < 5 || score > highScores[4].score) {
      highScores.length == 5 && (highScores.pop().stale = true);
      highScore = {score: score, client: client};
      highScores.push(highScore);
    }
    highScores.sort(function(a, b) { return b.score - a.score; });
  }
  
  client.on('nemesis', function(newNemesis) {
    nemesis = newNemesis;
    
    pos = 0;
    client.emit('getHighScore');
    client.send(JSON.stringify(['nemesis', nemesis.username]));
  });
  
  
  client.on('gameOver', function(points) {
    nemesis = null;
    score += points;
    pos = 0;
    client.send(JSON.stringify(['gameOver', points, score]));
    stopCountdown();
    updateHighScore();
    getNewNemesis();
  });
  
  client.on('pos', function(nemPos) {
    if (nemPos + pos >= playArea - 2) {
      nemesis.emit('gameOver', (playArea-nemPos)*(playArea-nemPos));
      client.emit('gameOver', (playArea-pos)*(playArea-pos));
    }
    else {
      client.send(JSON.stringify(['pos', nemPos]));
    }
  });

  client.on('message', function(msg) {
    data = JSON.parse(msg);
    sys.log(msg);
    switch(data[0]) {
      case "pos":
        pos = data[1];
        nemesis && nemesis.emit('pos', pos);
        break;
      case "name":
        name = data[1];
        client.username = name;
        nemesis && nemesis.emit('name', name);
        break;
    }
  });

  client.on('getHighScore', function(name) {
    client.send(JSON.stringify(['highScores',highScores.map(function(x) { return {score: x.score, name: x.client.username}; })]));
  });

  client.on('name', function(name) {
    client.send(JSON.stringify(['name', name]));    
  });
  
  client.on('lostNemesis', function() {
    nemesis = null;
    stopCountdown();
    getNewNemesis();
  });
  
  client.on('disconnect', function() {
    nemesis && nemesis.emit('lostNemesis');
    sys.log("disconnected: ", client.username)
    freeClient && freeClient === client && (freeClient = null);
  });
  
  updateHighScore();
  getNewNemesis();
});
