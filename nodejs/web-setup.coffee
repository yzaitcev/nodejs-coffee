# NPM modules
http = require 'http'
express = require 'express'
assets = require 'connect-assets'
path = require 'path'
fs = require 'fs'
socketio = require 'socket.io'
ini = require 'node-ini'
RedisStore = new(require('connect-redis')(express))
nodemailer = require 'nodemailer'
expressValidator = require 'express-validator'
firewall = require './firewall'

#==================================================================================
# Default Configuration
cfg = ini.parseSync __dirname + '/../config.ini'

port = cfg.web.port

#==================================================================================
# Extending the express validator
# @TODO move this to module

# Always return false
expressValidator.Validator.prototype.dummyFalse = () ->

    this.error(this.msg || 'Dummy validation method');

    return @

#==================================================================================
# Logging

Log = require('coloured-log')
logger = new Log(Log.Debug)

#==================================================================================
# Create & configure

# Configure web server
# You can overwrite the default configuration options
#  - (bool) options.firewall
exports.configure = (options)->

    app = express()

    # Default options
    options.firewall ?= true

    basepath = path.join __dirname, '..'

    app.configure ->
        app.use assets
            src: basepath + '/public'
        app.use express.bodyParser()
        app.use expressValidator
        app.use express.cookieParser()
        app.use express.methodOverride()
        app.use express.compress()
        app.use express.static(basepath + '/public')
        app.use express.session
            key: cfg.web['session.key']
            secret: cfg.web['session.secret']
            store: RedisStore
        app.set "jsonp callback", true
        app.set 'views', basepath + '/templates'
        app.set 'cfg', cfg
        app.set 'mailer', do () ->
            nodemailer.createTransport app.get('cfg').mailer.transport,
                host: app.get('cfg').mailer['smtp.host']
                secureConnection: app.get('cfg').mailer['smtp.ssl']
                port: app.get('cfg').mailer['smtp.port']
                auth:
                    user: app.get('cfg').mailer['smtp.user']
                    pass: app.get('cfg').mailer['smtp.pass']

    #==================================================================================
    # Configure the firewall
    firewall.configure app if options.firewall

    #==================================================================================
    # Some global template variables
    app.use (req, res, next)->
        res.locals.app_globals =
            req_user: req.user
            req_path: req.path
        next()

    #==================================================================================
    # Rroutes middleware. Firewall must be initialized first, it's important
    app.configure ->
        app.use app.router

    #==================================================================================
    # Configure environments
    app.configure 'development', ->
        app.use express.errorHandler
            dumpExceptions: true
            showStack: true

    app.configure 'production', ->
        app.use (err, req, res, next) ->
            res.status(500)
            res.render 'pages/error.jade'
            console.error err.stack
        oneYear = 31557600000
        app.use express.static(__dirname + '/public', maxAge: oneYear)

    #==================================================================================
    # Routes

    # Main page
    app.get '/', (req, res) ->
        res.render 'pages/USCapital/index.jade', 
            user_role  : req.user.Role

    # Suppression and De-Duplication routes
    require('./routes/admin').use app
    require('./routes/supp').use app
    require('./routes/dedupe').use app
    require('./routes/demo').use app
    require('./routes/files').use app
    require('./routes/zips').use app
    require('./routes/import-order-file').use app
    require('./routes/zip_table').use app
    require('./routes/approve-count').use app
    # Order routes
    require('./routes/orders').use app
    require('./routes/types').use app
    # API routes (currently contains Client and User)
    require('./routes/users')(app)
    require('./routes/clients')(app)
    # Authentication routes: login, forgot password, reset password
    require('./routes/auth').use app
    # User registration
    require('./routes/register').use app
    app

#==================================================================================
# Start server
#
# You can overwrite the default configuration options
#  - (int) options.port

exports.start = (app, options, cb)->
    # Setting up custom port
    port = options.port if options.port?

    server = http.createServer app
    io = socketio.listen server

    # Attach socket.io to the Express application
    io.set 'log level', 1
    
    # Authenticate the Socket connections
    firewall.configureSocketio app, io, RedisStore if options.firewall

    io.sockets.on 'connection', (socket) ->
        
        require('./api/dpdis').use socket
        require('./api/orders').use socket

    server.listen port

    logger.notice 'Server running at http://127.0.0.1:' + port

    cb server if cb?
