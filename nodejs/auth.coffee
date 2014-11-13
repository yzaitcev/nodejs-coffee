User = require '../../models/User'
ResetPasswordToken = require '../../models/ResetPasswordToken'
passport = require 'passport'

exports.use = (app) ->
        
    # Login page
    app.get '/login', (req, res) ->
        res.render 'pages/Auth/login.jade'

    # Logout page
    app.get '/logout', (req, res) ->
        req.logout();
        res.redirect('/login');

    # Login handler is called via AJAX
    # Return a JSON: {status:'',message:''}
    app.post '/login', (req, res, next) ->

        # Authenticate, example from http://passportjs.org/guide/authenticate/
        passport.authenticate('local', (err, user, info) -> 
            return next(err) if err 

            # User not found
            if !user
                logger.warning "Incorrent login: #{req.body.username}"
                return res.send 
                    'status':'err'
                    'message': 'Incorrect Username or Password'

            # Login the user
            req.logIn user, (err)->
                if err 
                    return res.send 
                        'status':'err'
                        'message': err.message
                
                logger.info "Successful Login: #{req.body.username}"

                if req.body.remember
                    # Remember on 90 days
                    req.session.cookie.maxAge = app.get('cfg').web.remember*24*60*60*1000
                else
                    # Don't remember. Expire at the end of session
                    # @TODO it's expire the cookies only but not value in the redis
                    req.session.cookie.maxAge = false

                # Track the login
                await user.incrNumLogins defer()

                return res.send 
                    'status':'ok'

        )(req, res, next)

    # Failure in login
    ,(err, req, res, next) ->
        res.send 
            'status':'err'
            'message':err.message

    # Display the form to enter the email 
    # to get the reset password link
    app.get '/forgot-password', (req, res) ->
        res.render 'forgot-password.jade'
    
    # Generating the token to reset password and send to user
    # @TODO maybe generate only one token per user?
    # @TODO create pretty email body
    app.post '/forgot-password', (req, res) ->
        
        # Search the user with specified email
        await User.findOne Email: req.body.email, defer(user)

        if user

            # build the new token for the reseting password
            await ResetPasswordToken.build user.UserID, defer(token)

            # Send the Reset Password link
            await 
                app.get('mailer').sendMail
                    from: "noreply@esimplicity.com"
                    to: user.Email
                    subject: 'Password Reset'
                    html: '<a href="http://'+req.headers.host+'/reset-password/'+token+'">Click to reset password</a>'
                ,defer(error, response)
                
            if error
                res.send 
                    'status': 'err'
                    'message': error
            else
                res.send 
                    'status':'ok'
                    'message':'Link to reset password was sent to you'
                    
        else
            res.send 
                'status':'err'
                'message':'Account isn\'t registered'

    # Display the form to reset password using the token
    app.all '/reset-password/:token', (req, res, next) ->

        # Search the token to use it
        ResetPasswordToken.findToUse req.params.token, (token) ->

            if token
                req.params.token = token
                return next()
            else
                res.redirect('/login')

    , (req, res) ->

        if req.route.method is 'post'

            # Validate the password
            if (req.body.password.length == 0)

                res.send 
                    'status':'err'
                    'message':'Enter the new password'
                return

            # Validate the password confirmation
            if (req.body.repeat_password != req.body.password)
            
                res.send 
                    'status':'err'
                    'message':'Incorrect password confirmation'
                return

            # Use the token to reset password
            ResetPasswordToken.use req.params.token, req.body.password, ()->
                res.send 
                    'status':'ok'
                    'message':'Password was successfully resetted. Now you can login using the new password'
                return
        else

            res.render 'reset-password.jade'
