$allowUsers = (****, ***)
$allowChats = (****, ****)
$vbToken = "*****"

$urlGet = "https://api.telegram.org/bot$vbToken/getUpdates"
$urlSet = "https://api.telegram.org/bot$vbToken/sendMessage"
$urlUpdate = "https://api.telegram.org/bot$vbToken/editMessageReplyMarkup"

$timeout = 2

#$button0 = @{"text" = "User"; callback_data = "But0" }
#$button1 = @{"text" = "Other"; callback_data = "But1" }
$button2 = @{"text" = "Unlock Acc"; callback_data = "But2" }
$button3 = @{"text" = "Renew Pass"; callback_data = "But3" }
$button4 = @{"text" = "Exit"; callback_data = "But4" }

#$buttons0 = ($button0, $button1)
$buttons1 = ($button2, $button3, $button4)

$credentUser = "user@domain" #AD Account with permissions to unlock and renew accounts
$credentPass = "****"
$secpw = ConvertTo-SecureString $credentPass -AsPlainText -Force
$credent = New-Object Management.Automation.PSCredential ($credentUser, $secpw)
$DCHostName = "domainControllerHostname"

function getUpdates($url) {

    $json = Invoke-RestMethod -Uri $url
    $data = $json.result | Select-Object -Last 1
    $text = $null
    $callback_data = $null
    
    if ($data.callback_query) {
        $chatID = $data.callback_query.message.chat.id
        $firstName = $data.callback_query.chat.first_name
        $chatName = $data.callback_query.chat.username
        $fromID = $data.callback_query.from.id
        $callback_data = $data.callback_query.data
    }
    elseif ($data.message) {
        $chatID = $data.message.chat.id
        $firstName = $data.message.chat.first_name
        $chatName = $data.message.chat.username
        $fromID = $data.message.from.id
        $text = $data.message.text
        
    }
    $ht = @{}
    $ht["chatID"] = $chatID
    $ht["text"] = $text
    $ht["firstName"] = $firstName
    $ht["username"] = $chatName
    $ht["fromID"] = $fromID
    $ht["callbackData"] = $callback_data
    Invoke-RestMethod "$($url)?offset=$($($data.update_id) + 1)" -Method Get | Out-Null
    return $ht
}

function sendMessage {
    param (
        $url, $chatID, $text
    )
    $ht = @{
        text      = $text
        parseMode = "Markdown"
        chat_id   = $chatID
    }
    $json = $ht | ConvertTo-Json -Depth 5
    Invoke-RestMethod $url -ContentType 'application/json; charset=utf-8' -Body $json -Method Post
}

function sendMessageForReply {
    param (
        $url, $chatID, $text
    )
    $force_reply = @{"force_reply" = $true }
    $ht = @{
        text         = $text
        parseMode    = "Markdown"
        chat_id      = $chatID
        reply_markup = $force_reply
    }
    $json = $ht | ConvertTo-Json -Depth 5
    Invoke-RestMethod $url -ContentType 'application/json; charset=utf-8' -Body $json -Method Post
}

function sendKeyboard {
    param (
        $url, $buttons, $chatID, $text
    )
    $keyboard = @{"inline_keyboard" = @(, $buttons) }
    $ht = @{
        parse_mode   = "Markdown"
        reply_markup = $keyboard
        chat_id      = $chatID
        text         = $text
    }

    $json = $ht | ConvertTo-Json -Depth 5
    $json
    $reply = @{} 
    Invoke-RestMethod $url -Method Post -ContentType 'application/json; charset=utf-8' -Body $json
    return $reply
}

function delKeyboard {
    param (
        $url, $chatID, $messageID
    )
    $ht = @{
        parse_mode = "Markdown"
        #reply_markup = $keyboard
        chat_id    = $chatID
        message_id = $messageID

    }
    $json = $ht | ConvertTo-Json -Depth 5 
    Invoke-RestMethod $url -ContentType 'application/json; charset=utf-8' -Body $json -Method Post
}

function getUserInfo {
    param (
        $userLogin
    )

    $ADUserInfo = Invoke-Command -ComputerName $DCHostName -Credential $credent -ScriptBlock {Param ($userLogin ) Get-ADUser -Identity $userLogin -Properties *} -ArgumentList $userLogin

    If ($ADUserInfo) {
        $pwdLastSet = $ADUserInfo.pwdLastSet
        $date = [DateTime]::FromFileTime($pwdLastSet)

        $ht = @{
            UserEnabled = $ADUserInfo.Enabled
            UserLocked = $ADUserInfo.LockedOut
            UserPWDDate  = get-date $date -format "dd/MM/yyyy"
        }
        $reply = $ht | ConvertTo-Json -Depth 5
    }
     else {
         $reply = "No such user in AD"
        }
    return $reply
}

function unlockUser {
    param (
        $userLogin
    )
    Invoke-Command -ComputerName $DCHostName -Credential $credent -ScriptBlock {Param ($userLogin ) Unlock-ADAccount -Identity $userLogin} -ArgumentList $userLogin
}

function renewUserPass {
    param (
        $userLogin
    )  
    Invoke-Command -ComputerName $DCHostName -Credential $credent -ScriptBlock {Param ($userLogin ) Set-ADUser -Identity $userLogin -Replace @{pwdLastSet=0}} -ArgumentList $userLogin
    Invoke-Command -ComputerName $DCHostName -Credential $credent -ScriptBlock {Param ($userLogin ) Set-ADUser -Identity $userLogin -Replace @{pwdLastSet=-1}} -ArgumentList $userLogin 
}

while ($true) {
    $userInput = $null
    $userInput = getUpdates $urlGet
    $userInput
    if ( ($allowUsers -contains $userInput.fromID) -and ($allowChats -contains $userInput.chatID)) {
 
        if ($userInput.text -eq "/user@bot") { #command in Botfather menu for user actions
            delKeyboard $urlUpdate $userInput.chatID $send.result.message_id
            sendMessageForReply $urlSet $userInput.chatID "User login"   
        }


        elseif ($userInput.callbackData -eq "But2") {

            delKeyboard $urlUpdate $userInput.chatID $send.result.message_id
            unlockUser $saveLogin
            $userInfo = getUserInfo $saveLogin
            sendMessage $urlSet $userInput.chatID $userInfo
            $saveLogin = $null
        }

        elseif ($userInput.callbackData -eq "But3") {

            delKeyboard $urlUpdate $userInput.chatID $send.result.message_id
            renewUserPass $saveLogin
            $userInfo = getUserInfo $saveLogin
            sendMessage $urlSet $userInput.chatID $userInfo
            $saveLogin = $null
        }

        elseif ($userInput.callbackData -eq "But4") {

            delKeyboard $urlUpdate $userInput.chatID $send.result.message_id
            sendMessage $urlSet $userInput.chatID "Bye"           
        }
        elseif ($userInput.text -like "/user*") {
        
            sendMessage $urlSet $userInput.chatID "Wrong Input"c
        }
        elseif ($userInput.text) {

            $userInfo = getUserInfo $userInput.text
            $userInfo
            sendMessage $urlSet $userInput.chatID $userInfo
            $saveLogin = $userInput.text
            
            if ($userInfo -eq "No such user in AD") {
                $saveLogin = $null
                sendMessage $urlSet $userInput.chatID "Bye"
            }
                        
            else  {
                $send = sendKeyboard $urlSet $buttons1 $userInput.chatID "Select"

            }

        }
        
    }

    Start-Sleep -s $timeout 

}


