http = require('http')
io   = require('socket.io')
fs   = require('fs')
sys  = require('sys')
repl = require('repl')

i = require('util').inspect
p = require('util').debug

server = http.createServer (req, res) -> 
  res.writeHead 200, 'Content-Type': 'text/html'

  s = fs.createReadStream 'shakeoff.html'
  sys.pump s, res

server.listen 9876

socket = io.listen server

#repl.start().context.server = server

freeUser = null
playArea = 25

highScores = []
highScores.update = (user, score, highScore) ->
  if highScore?.active
    highScore.score = score
  else if @length < 5 or score > @[4].score 
    @pop().active = false if @length == 5

    highScore = 
      score: score
      user: user
      active: true
    
    @push highScore
    
  @sort (a, b) -> b.score - a.score

  return highScore

class Player
  constructor: (@conn) ->    
    @pos = 0
    @score = 0
    @highScore = null
    @name = "anonymous"
    @nemesis = null

    @countdownTimer = null
    
    @conn.on 'message', @recvCmd
    @conn.on 'disconnect', @recvDisconnect
    
    @newGame()
    
  startCountdown: ->
    @stopCountdown()
    #sys.log "started countdown by #{@name}"
    @countdownTimer = setTimeout(=> 
      @stopCountdown()
      @loseGame()
    ,10*1000)

  stopCountdown: ->
    #sys.log "stopped countdown by #{@name}"
    clearTimeout @countdownTimer
    @countdownTimer = null
  
  
  startGame: (@nemesis) ->
    #p (i @nemesis)
    @pos = 0
    @sendHighScore()
    @sendCmd 'nemesis', @nemesis.name
  
  newGame: ->
    if freeUser? && freeUser != this
      freeUser.startGame(this)
      @startGame(freeUser)
      
      freeUser = null

      @startCountdown()    

    else 
      freeUser = this
      @sendCmd 'waiting'
      
      
  winGame: -> @endGame(true)
  loseGame: -> @endGame(false)
  
  endGame: (win = true) ->
    nem = @nemesis
    
    myBasis = playArea-@pos
    nemBasis = playArea-nem.pos
    if win
      nem.gameOver nemBasis*nemBasis
      @gameOver myBasis*myBasis
    else
      nem.gameOver -nemBasis*nemBasis
      @gameOver -myBasis*myBasis
      
    @newGame()
    nem.newGame()
    

  gameOver: (points) ->
    @stopCountdown() if @countdownTimer?
    @nemesis = null
    @score += points
    @pos = 0

    @sendCmd 'gameOver', points, @score
    @highScore = highScores.update this, @score, @highScore

  sendHighScore: ->
    @sendCmd 'highScores', highScores.map((x) -> score: x.score, name: x.user.name)
    
  sendCmd: (args...) ->
    @conn.send JSON.stringify(args)

  lostNemesis: ->
    @nemesis = null
    @stopCountdown()
    @newGame()


  recvDisconnect: =>
    @nemesis?.lostNemesis()
    @stopCountdown() if @countdownTimer?
    
    freeUser = null if freeUser == this
    
    #sys.log "disconnected: ", @name
    
  recvCmd: (msg) =>
    [cmd, data...] = JSON.parse(msg)
    
    #p (i @cmds)
    
    @cmds[cmd].apply(this, data);
    
  cmds:
    pos: (@pos) ->
      if (@nemesis? and @nemesis.pos + @pos >= playArea - 2) 
        @winGame()
      else 
        @nemesis?.sendCmd 'pos', @pos

    name: (@name) ->
      @nemesis?.sendCmd 'name', @name

socket.on 'connection', (client) ->  
  new Player client
  