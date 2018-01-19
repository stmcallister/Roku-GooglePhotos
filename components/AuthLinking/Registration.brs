
Sub init()
    m.buttongroup   = m.top.findNode("buttonGroup")
    m.Row1          = m.top.findNode("Row1")
    m.Row2          = m.top.findNode("Row2")
    m.Row3          = m.top.findNode("Row3")
    m.Row4          = m.top.findNode("Row4")
    m.Row5          = m.top.findNode("Row5")
    m.LoginTimer    = m.top.findNode("LoginTimer")
    
    m.Row4.font.size = 45
    
    m.UriHandler = createObject("roSGNode","Authlinking UrlHandler")
    m.UriHandler.observeField("gen_token_response","onNewToken")
    m.LoginTimer.observeField("fire","onCheckAuth")

    m.buttongroup.buttons = [ "Get a new code", "About Channel" ]
    m.buttongroup.setFocus(true)
    m.buttongroup.observeField("buttonSelected","onButtonPress")
    
    'Load common variables
    loadCommon()

    'Load privlanged variables
    loadPrivlanged()
   
    'Kick off token generation
    loadReg()
    doGenerateToken()
    
End Sub


Sub doGenerateToken()
    print "Registration.brs [doGenerateToken]"

    params = "client_id="        + m.clientId
    params = params + "&scope="  + m.oauth_scope

    makeRequest({}, m.oauth_prefix+"/device/code", "POST", params, 0)
End Sub


Sub doQueryUserInfo()
    print "Registration.brs [doQueryUserInfo]"

    m.UriHandler.observeField("userinfo_response","onStoreUser")
    userIndex = m.accessToken.Count()-1
    makeRequest({}, "https://www.googleapis.com/oauth2/v3/userinfo?access_token="+m.accessToken[userIndex], "GET", "", 2)
End Sub


Sub onNewToken(event as object)
    print "Registration.brs [onNewToken]"
  
    tokenData = event.getData()
    
    json = ParseJson(tokenData.content)
    if json = invalid
        m.errorMsg = "Unable to parse Json response"
        m.oa.status = 1
    else if type(json) <> "roAssociativeArray"
        m.errorMsg = "Json response is not an associative array"
        m.oa.status = 1
    else if json.DoesExist("error")
        m.errorMsg = "Json error response: " + json.error
        m.oa.status = 1
    else
        m.userCode              = getString(json,"user_code")
        m.deviceCode            = getString(json,"device_code")
        m.verificationUrl       = getString(json,"verification_url")
        m.pollExpiresIn         = getInteger(json,"expires_in")
        m.interval              = getInteger(json,"interval")
        if m.userCode           = ""    then m.errorMsg = "Missing user_code"           : m.oa.status = 1
        if m.deviceCode         = ""    then m.errorMsg = "Missing device_code"         : m.oa.status = 1
        if m.verificationUrl    = ""    then m.errorMsg = "Missing verification_url"    : m.oa.status = 1
        if m.pollExpiresIn      = 0     then m.errorMsg = "Missing expires_in"          : m.oa.status = 1
        if m.interval           = 0     then m.errorMsg = "Missing interval"            : m.oa.status = 1    
    end if
  
    m.Row2.text = m.verificationUrl
    m.Row4.text = m.userCode
    
    m.LoginTimer.repeat = true
    m.LoginTimer.control = "start"
End Sub


Sub onCheckAuth(event as object)
    print "Registration.brs [onCheckAuth]"
    status = -1   ' 0 => Finished (got tokens), < 0 => Retry needed, > 0 => fatal error
        
    pollData = m.UriHandler.poll_token_response
        
    if pollData <> invalid
        json = ParseJson(pollData.content)
        if json = invalid
            m.errorMsg = "Unable to parse Json response"
            status = 1
        else if type(json) <> "roAssociativeArray"
            m.errorMsg = "Json response is not an associative array"
            status = -1
        else if json.DoesExist("error")
            if json.error = "authorization_pending"
                status = -1    ' Retry
            else if json.error = "slow_down"
                m.LoginTimer.duration = m.LoginTimer.duration + 2        ' Increase polling interval
                status = -1    ' Retry
            else
                m.errorMsg = "Json error response: " + json.error
                status = 1
            end if
        else
            'Stop the polling
            status = 0
            
            'Stop watching for field changes
            m.UriHandler.unobserveField("gen_token_response")
            m.LoginTimer.unobserveField("fire")
            
            ' We have our tokens    
            m.accessToken.Push(getString(json,"access_token"))
            m.refreshToken.Push(getString(json,"refresh_token"))
            m.tokenType          = getString(json,"token_type")
            m.tokenExpiresIn     = getInteger(json,"expires_in")

            'Query User info
            doQueryUserInfo()
            'status = m.RequestUserInfo(m.accessToken.Count()-1, false)

            'if m.tokenType       = "" then m.errorMsg = "Missing token_type"      : status = 1
            'if m.tokenExpiresIn  = 0  then m.errorMsg = "Missing expires_in"      : status = 1
                
        end if   
    end if
    
    if status = 0 then
        m.LoginTimer.repeat = false
        m.LoginTimer.control = "stop"
    else
        params = "client_id="                 + m.clientId
        params = params + "&client_secret="   + m.clientSecret
        params = params + "&code="            + m.deviceCode
        params = params + "&grant_type="      + "http://oauth.net/grant_type/device/1.0"
    
        makeRequest({}, m.oauth_prefix+"/token", "POST", params, 1)

        m.LoginTimer.repeat = true
        m.LoginTimer.control = "start"
    end if
End Sub


Sub onStoreUser(event as object)
    print "Registration.brs [onCheckAuth]"
    status = -1   ' 0 => Finished (got tokens), < 0 => Retry needed, > 0 => fatal error
        
    userData = m.UriHandler.userinfo_response
    isrefresh = false
    
    if userData <> invalid
        json = ParseJson(userData.content)
        if json = invalid
            m.errorMsg = "Unable to parse Json response"
            status = 1
        else if type(json) <> "roAssociativeArray"
            m.errorMsg = "Json response is not an associative array"
            status = -1
        else if json.DoesExist("error")
            m.errorMsg = "Json error response: " + json.error
            status = 1
        else
            infoName  = getString(json,"name")
            infoEmail = getString(json,"email")
            infoPhoto = getString(json,"picture")

            'Special Charactor management
            infoName  = infoName.Replace(".", "")
            infoName  = strReplaceSpecial(infoName)
            infoEmail = strReplaceSpecial(infoEmail)

            if infoName  = "" then infoName  = "Google Photos User"
            if infoEmail = "" then infoName  = "No email on file"
            if infoPhoto = "" then infoPhoto = "pkg:/images/userdefault.png"
            
            if isrefresh = true then
                m.userInfoName[m.global.selectedUser]  = infoName
                m.userInfoEmail[m.global.selectedUser] = infoEmail
                m.userInfoPhoto[m.global.selectedUser] = infoPhoto
            else
            
                if infoEmail <> "No email on file" then
                    for i = 0 to m.userInfoEmail.Count()-1
                        'if m.userInfoEmail[i] = infoEmail then
                        '    m.accessToken.Pop()
                        '    m.refreshToken.Pop()
                        '    'ShowDialog1Button("Notice", "Account '"+infoEmail+"' already linked to device", "OK")
                        'end if
                    end for
                end if
            
                m.userInfoName.Push(infoName)
                m.userInfoEmail.Push(infoEmail)
                m.userInfoPhoto.Push(infoPhoto)
            end if
            
            if infoEmail = "" then m.errorMsg = "Missing User Data (Email)" : status = 1
            if infoName  = "" then m.errorMsg = "Missing User Data (Name)" : status = 1
            if infoPhoto = "" then m.errorMsg = "Missing User Data (Photo" : status = 1       

            'Save cached values to registry
            saveReg()
            
            m.Row1.text = ""  
            m.Row2.text = "Successfully Linked Account!"
            m.Row3.text = infoName + "'s Google Photos account has been successfully linked this Roku device"
            m.Row4.text = ""
            m.Row5.text = ""
            
            m.buttongroup.buttons = [ "Continue" ]
            m.buttongroup.setFocus(true)
                
        end if   
    end if
End Sub


Sub onButtonPress(event as object)
    if (event.getData() = 0) and (m.buttongroup.buttons[0] = "Get a new code")
        'GENERATE NEW TOKEN
        doGenerateToken()
    else if (event.getData() = 0) and (m.buttongroup.buttons[0] = "Continue")
        m.global.selectedUser = -2
    end if
End Sub


Function onKeyEvent(key as String, press as Boolean) as Boolean
    if press then
        print "KEY (reg): "; key
    end if

    'If nothing above is true, we'll fall back to the previous screen.
    return false
End Function
