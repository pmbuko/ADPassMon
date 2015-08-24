--  ADPassMonAppDelegate.applescript
--  ADPassMon
--
--  Created by Peter Bukowinski on 3/24/11 (and updated many times since)
--
--  This software is released under the terms of the MIT license.
--  Copyright (C) 2015 by Peter Bukowinski
--
--  Permission is hereby granted, free of charge, to any person obtaining a copy
--  of this software and associated documentation files (the "Software"), to deal
--  in the Software without restriction, including without limitation the rights
--  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
--  copies of the Software, and to permit persons to whom the Software is
--  furnished to do so, subject to the following conditions:
--  
--  The above copyright notice and this permission notice shall be included in
--  all copies or substantial portions of the Software.
--  
--  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
--  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
--  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
--  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
--  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
--  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
--  THE SOFTWARE.
---------------------------------------------------------------------------------
-- TO DO:
--
-- FEATURE REQUESTS:
-- - Enable mcx defaults hook for adding as login item.

script ADPassMonAppDelegate

--- PROPERTIES ---    

--- Classes
    property parent :                   class "NSObject"
    property NSMenu :                   class "NSMenu"
    property NSThread :                 class "NSThread" -- for 'sleep'-like feature
    property NSMenuItem :               class "NSMenuItem"
    property NSTimer :                  class "NSTimer" of current application -- so we can do stuff at regular intervals
    property NSUserNotificationCenter : class "NSUserNotificationCenter" -- for notification center
    property NSWorkspace :              class "NSWorkspace" -- for sleep notification

--- Objects
    property standardUserDefaults : missing value
    property statusMenu :           missing value
    property statusMenuController : missing value
    property theWindow :            missing value
    property defaults :             missing value -- for saved prefs
    property theMessage :           missing value -- for stats display in pref window
    property manualExpireDays :     missing value
    property selectedMethod :       missing value
    property thePassword :          missing value
    property toggleNotifyButton :   missing value
    property processTimer :         missing value
    property domainTimer :          missing value

--- Booleans
    property first_run :            true
    property isIdle :               true
    property isHidden :             false
    property isManualEnabled :      false
    property enableNotifications :  true
    property enableKerbMinder :     false
    property prefsLocked :          false
    property launchAtLogin :        false
    property skipKerb :             false
    property onDomain :             false
    property passExpires :          true
    property goEasy :               false
    property showChangePass :       false
    property KerbMinderInstalled :  false
    
--- Other Properties
    property warningDays :      14
    property menu_title :       "[ ? ]"
    property accTest :          1
    property tooltip :          "Waiting for data…"
    property osVersion :        ""
    property kerb :             ""
    property myLDAP :           ""
    property mySearchBase :     ""
    property expireAge :        0
    property expireAgeUnix :    ""
    property expireDate:        ""
    property expireDateUnix:    ""
    property uAC :              ""
    property pwdSetDate :       ""
    property pwdSetDateUnix :   0
    property plistPwdSetDate :  0
    property pwPolicy :         ""
    property pwPolicyButton :   "OK"
    property today :            ""
    property todayUnix :        ""
    property daysUntilExp :     ""
    property daysUntilExpNice : ""
    property expirationDate :   ""
    property mavAccStatus :     ""
    property checkInterval :    4  -- hours

--- HANDLERS ---

    -- General error handler
    on errorOut_(theError, showErr)
        log "Script Error: " & theError
        --if showErr = 1 then set my theMessage to theError as text
        --set isIdle to false
    end errorOut_

    -- Need to get the OS version so we can handle Kerberos differently in 10.7+
    on getOS_(sender)
        set my osVersion to (do shell script "sw_vers -productVersion | awk -F. '{print $2}'") as integer
        log "Running on OS 10." & osVersion & ".x"
    end getOS_

    -- Tests if Universal Access scripting service is enabled
    on accTest_(sender)
        log "Testing Universal Access settings…"
        if osVersion is less than 9 then
            tell application "System Events"
                set accStatus to get UI elements enabled
            end tell
            if accStatus is true then
                log "  Enabled"
            else
                log "  Disabled"
                accEnable_(me)
            end if
        else -- if we're running 10.9 or later, Accessibility is handled differently
            tell defaults to set my accTest to objectForKey_("accTest")
            if accTest as integer is 1 then
                if "80" is in (do shell script "/usr/bin/id -G") then -- checks if user is in admin group
                    set accessDialog to (display dialog "ADPassMon's \"Change Password\" feature requires assistive access to open the password panel.
                    
Enable it now? (requires password)" with icon 2 buttons {"No", "Yes"} default button 2)
                    if button returned of accessDialog is "Yes" then
                        log "  Prompting for password"
                        try
                            set mavAccStatus to (do shell script "sqlite3 '/Library/Application Support/com.apple.TCC/TCC.db' \"SELECT * FROM access WHERE client='org.pmbuko.ADPassMon';\"" with administrator privileges)
                        end try
                        if mavAccStatus is "" then
                            log "  Not enabled"
                            try
                                do shell script "sqlite3 '/Library/Application Support/com.apple.TCC/TCC.db' \"INSERT INTO access VALUES('kTCCServiceAccessibility','org.pmbuko.ADPassMon',0,1,1,NULL);\"" with administrator privileges
                                set my accTest to 0
                                tell defaults to setObject_forKey_(0, "accTest")
                            on error theError
                                log "Unable to set access. Error: " & theError
                            end try
                        else
                            set my accTest to 0
                            tell defaults to setObject_forKey_(0, "accTest")
                            log "  Enabled"
                        end if
                    end if
                else
                    set my accTest to 0
                    tell defaults to setObject_forKey_(0, "accTest")
                    log "  User not admin. Skipping."
                end if
            else
                log "  Enabled"
            end if
            
        end if
    end accTest_

    -- Prompts to enable Universal Access scripting service
    on accEnable_(sender)
        if "80" is in (do shell script "/usr/bin/id -G") then -- checks if user is in admin group
            activate
            set response to (display dialog "ADPassMon's \"Change Password\" feature requires assistive access to open the password panel.
            
Enable it now?" with icon 2 buttons {"No", "Yes"} default button 2)
            if button returned of response is "Yes" then
                log "  Prompting for password"
                try
                    tell application "System Events"
                        activate
                        set UI elements enabled to true
                    end tell
                    log "  Now enabled"
                    --display dialog "Access for assistive devices is now enabled." buttons {"OK"} default button 1
                on error theError
                    log "  Error: " & theError
                    activate
                    display dialog "Could not enable access for assistive devices." buttons {"OK"} default button 1
                end try
            else -- if No is clicked
                log "  User chose not to enable"
            end if
        else
            log "  Skipping because user not an admin"
        end if
    end accEnable_

    on KerbMinderTest_(sender)
        tell application "Finder"
            if exists "/Library/Application Support/crankd/KerbMinder.py" as POSIX file then
                set my KerbMinderInstalled to true
            else
                set my KerbMinderInstalled to false
            end if
        end tell
    end KerbMinderTest_

    -- Register plist default settings
    on regDefaults_(sender)
        tell current application's NSUserDefaults to set defaults to standardUserDefaults()
        tell defaults to registerDefaults_({menu_title: "[ ? ]", ¬
                                            tooltip:tooltip, ¬
                                            fist_run:first_run, ¬
                                            selectedMethod:0, ¬
                                            isManualEnabled:isManualEnabled, ¬
                                            enableNotifications:enableNotifications, ¬
                                            checkInterval:checkInterval, ¬
                                            expireAge:expireAge, ¬
                                            expireDateUnix:expireDateUnix, ¬
                                            pwdSetDate:pwdSetDate, ¬
                                            warningDays:warningDays, ¬
                                            prefsLocked:prefsLocked, ¬
                                            myLDAP:myLDAP, ¬
                                            pwPolicy:pwPolicy, ¬
                                            pwPolicyButton:pwPolicyButton, ¬
                                            accTest:accTest, ¬
                                            enableKerbMinder:enableKerbMinder, ¬
                                            launchAtLogin:launchAtLogin})
    end regDefaults_

    -- Get values from plist
    on retrieveDefaults_(sender)
        tell defaults to set my menu_title to objectForKey_("menu_title")
        tell defaults to set my first_run to objectForKey_("first_run")
        tell defaults to set my selectedMethod to objectForKey_("selectedMethod") as integer
        tell defaults to set my isManualEnabled to objectForKey_("isManualEnabled") as integer
        tell defaults to set my enableNotifications to objectForKey_("enableNotifications") as integer
        tell defaults to set my checkInterval to objectForKey_("checkInterval") as real
        tell defaults to set my expireAge to objectForKey_("expireAge") as integer
        tell defaults to set my expireDateUnix to objectForKey_("expireDateUnix") as integer
        tell defaults to set my pwdSetDate to objectForKey_("pwdSetDate") as integer
        tell defaults to set my warningDays to objectForKey_("warningDays")
        tell defaults to set my prefsLocked to objectForKey_("prefsLocked")
        tell defaults to set my myLDAP to objectForKey_("myLDAP")
        tell defaults to set my pwPolicy to objectForKey_("pwPolicy")
        tell defaults to set my pwPolicyButton to objectForKey_("pwPolicyButton")
        tell defaults to set my accTest to objectForKey_("accTest") as integer
        tell defaults to set my enableKerbMinder to objectForKey_("enableKerbMinder")
        tell defaults to set my launchAtLogin to objectForKey_("launchAtLogin")
    end retrieveDefaults_

    on notifySetup_(sender)
        if osVersion is less than 8 then
            set my enableNotifications to false
        --else
        --  set my enableNotifications to true
        end if
    end notifySetup_

    -- This handler is sent daysUntilExpNice and will trigger an alert if ≤ warningDays
    on doNotify_(sender)
        if sender as integer ≤ my warningDays as integer then
            if osVersion is greater than 7 then
                if my enableNotifications as boolean is true then
                    log "Triggering notification…"
                    set ncTitle to "Password Expiration Warning"
                    set ncMessage to "Your password will expire in " & sender & " days on " & expirationDate
                    sendNotificationWithTitleAndMessage_(ncTitle, ncMessage)
                end if
            end if
        end if
    end doNotify_

    on sendNotificationWithTitleAndMessage_(aTitle, aMessage)
        set myNotification to current application's NSUserNotification's alloc()'s init()
        set myNotification's title to aTitle
        set myNotification's informativeText to aMessage
        current application's NSUserNotificationCenter's defaultUserNotificationCenter's deliverNotification_(myNotification)
    end sendNotificationWithTitleAndMessage_

    -- Trigger doProcess handler on wake from sleep
    on watchForWake_(sender)
        tell (NSWorkspace's sharedWorkspace())'s notificationCenter() to ¬
            addObserver_selector_name_object_(me, "doProcessWithWait:", "NSWorkspaceDidWakeNotification", missing value)
    end watchForWake_

    on ticketViewer_(sender)
        tell application "Ticket Viewer" to activate
    end ticketViewer_
    
    on domainTest_(sender)
        set domain to (do shell script "/usr/sbin/dsconfigad -show | /usr/bin/awk '/Active Directory Domain/{print $NF}'") as text
        try
            set digResult to (do shell script "/usr/bin/dig +time=2 +tries=1 -t srv _ldap._tcp." & domain) as text
        on error theError
            log "Domain test timed out."
            set my onDomain to false
            my statusMenu's itemWithTitle_("Refresh Kerberos Ticket")'s setEnabled_(0)
            my statusMenu's itemWithTitle_("Change Password…")'s setEnabled_(0)
            return
        end try
        if "ANSWER SECTION" is in digResult then
            set my onDomain to true
            my statusMenu's itemWithTitle_("Refresh Kerberos Ticket")'s setEnabled_(1)
            my statusMenu's itemWithTitle_("Change Password…")'s setEnabled_(1)
        else
            set my onDomain to false
            log "Domain not reachable."
            my statusMenu's itemWithTitle_("Refresh Kerberos Ticket")'s setEnabled_(0)
            my statusMenu's itemWithTitle_("Change Password…")'s setEnabled_(0)
        end if
    end domainTest_
    
    on intervalDomainTest_(sender)
        domainTest_(me)
    end intervalDomainTest_

    -- Check if password is set to never expire
    on canPassExpire_(sender)
        log "Testing if password can expire…"
        set my uAC to (do shell script "/usr/bin/dscl localhost read /Search/Users/$USER userAccountControl | /usr/bin/awk '/:userAccountControl:/{print $2}'")
        if (count words of uAC) is greater than 1 then
            set my uAC to last word of uAC
        end if
        try
            if first character of uAC is "6" then
                set passExpires to false
                log "  Password does NOT expire."
            else
                log "  Password does expire."
            end if
        on error
            log "  Could not determine if password expires."
        end try
    end canPassExpire_

    -- Checks for kerberos ticket, necessary for auto method. Also bound to Refresh Kerb menu item.
    on doKerbCheck_(sender)
        if my onDomain is true and my skipKerb is false then
            if selectedMethod = 0 then
                if osVersion is less than 7 then
                    try
                        log "Testing for kerberos ticket presence…"
                        set kerb to do shell script "/usr/bin/klist -t"
                        set renewKerb to do shell script "/usr/bin/kinit -R"
                        log "  Ticket found and renewed"
                        set my isIdle to true
                        retrieveDefaults_(me)
                        doProcess_(me)
                    on error theError
                        set my theMessage to "Kerberos ticket expired or not found"
                        log "  No ticket found"
                        activate
                        set response to (display dialog "No Kerberos ticket for Active Directory was found. Do you want to renew it?" with icon 1 buttons {"No","Yes"} default button "Yes")
                        if button returned of response is "Yes" then
                            do shell script "/bin/echo '' | /usr/bin/kinit -l 24h -r 24h &" -- Displays a password dialog in 10.6 (and maybe 10.5?)
                            log "  Ticket acquired"
                            doKerbCheck_(me) -- Rerun the handler to verify kerb ticket and call doProcess
                        else -- if No is clicked
                            log "  User chose not to acquire"
                            errorOut_(theError, 1)
                        end if
                    end try
                else -- if osVersion is 7 or greater
                    doLionKerb_(me)
                end if
            else -- if selectedMethod = 1
                doProcess_(me)
            end if
        else -- if skipKerb is true
            doProcess_(me)
        end if
    end doKerbCheck_

    -- Need to handle Lion's kerberos differently from older OSes
    on doLionKerb_(sender)
        try
            log "Testing for Kerberos ticket presence…"
            set kerb to do shell script "/usr/bin/klist -t"
            set renewKerb to do shell script "/usr/bin/kinit -R"
            log "  Ticket found and renewed"
            set my isIdle to true
            retrieveDefaults_(me)
            doProcess_(me)
        on error theError
            set my theMessage to "Kerberos ticket expired or not found"
            log "  No ticket found"
            activate
            set response to (display dialog "No Kerberos ticket for Active Directory was found. Do you want to renew it?" with icon 2 buttons {"No","Yes"} default button "Yes")
            if button returned of response is "Yes" then
                renewLionKerb_(me)
            else -- if No is clicked
                log "  User chose not to acquire"
                errorOut_(theError, 1)
            end if
        end try
    end doLionKerb_

    -- Runs when Yes of Lion kerberos renewal dialog (from above) is clicked.
    on renewLionKerb_(sender)
        try
            set thePassword to text returned of (display dialog "Enter your Active Directory password:" default answer "" with hidden answer)
            do shell script "/bin/echo '" & thePassword & "' | /usr/bin/kinit -l 10h -r 10h --password-file=STDIN"
            log "  Ticket acquired"
            display dialog "Kerberos ticket acquired." with icon 1 buttons {"OK"} default button 1
            doLionKerb_(me)
        on error
            try
                set thePassword to text returned of (display dialog "Password incorrect. Please try again:" default answer "" with icon 2 with hidden answer)
                do shell script "/bin/echo '" & thePassword & "' | /usr/bin/kinit -l 24h -r 24h --password-file=STDIN"
                display dialog "Kerboros ticket acquired." with icon 1 buttons {"OK"} default button 1
                doLionKerb_(me)
            on error
                log "  Incorrect password. Skipping."
                display dialog "Too many incorrect attempts. Stopping to avoid account lockout." with icon 2 buttons {"OK"} default button 1
            end try
        end try
    end renewLionKerb_

    -- ad node with scutil fallback to get AD DNS info
    on getDNS_(sender)
        try
            -- find source of user node
            set originalNodeName to (do shell script "/usr/bin/dscl localhost read /Search/Users/$USER OriginalNodeName | grep -o -e '/.*'") as text
            if (count words of originalNodeName) > 0
                set my myLDAP to (do shell script "/usr/bin/dscl localhost read '" & originalNodeName & "' ServerConnection | /usr/bin/awk '/ServerConnection/{print $2}'") as text
                set my mySearchBase to (do shell script "/usr/bin/dscl localhost read '" & originalNodeName & "' LDAPSearchBaseSuffix | /usr/bin/awk '/LDAPSearchBaseSuffix/{print $2}'") as text
            end if
        
            if (count words of myLDAP) = 0
                -- "first word of" added for 10.7 compatibility, which may return more than one item
                set my myLDAP to first word of (do shell script "/usr/sbin/scutil --dns | /usr/bin/awk '/nameserver\\[0\\]/{print $3}'") as text
            end if
        on error theError
            errorOut_(theError)
        end try
        log "  myLDAP: " & myLDAP
    end getDNS_

    -- Use dsconfigad to get domain name
    -- Use dig to get AD LDAP server from domain name
    on getADLDAP_(sender)
        try
            set myDomain to (do shell script "/usr/sbin/dsconfigad -show | /usr/bin/awk '/Active Directory Domain/{print $NF}'") as text
            try
                set myLDAPresult to (do shell script "/usr/bin/dig +time=2 +tries=1 -t srv _ldap._tcp." & myDomain) as text
            on error theError
                log "Domain test timed out."
                set my onDomain to false
            end try
            if "ANSWER SECTION" is in myLDAPresult then
                set my onDomain to true
                -- using "first paragraph" to return only the first ldap server returned by the query
                set myLDAP to last paragraph of (do shell script "/usr/bin/dig -t srv _ldap._tcp." & myDomain & "| /usr/bin/awk '/^_ldap/{print $NF}'") as text
                log "  myDomain: " & myDomain
                log "  myADLDAP: " & myLDAP
            else
                set my onDomain to false
                log "  Can't reach " & myDomain & " domain"
            end if
        on error theError
            errorOut_(theError)
        end try
    end getADLDAP_

    -- Use ldapsearch to get search base if OriginalNodeName method didn't work
    on getSearchBase_(sender)
        if (count of words of my mySearchBase) > 0
            return
        end if

        try
            set my mySearchBase to (do shell script "/usr/bin/ldapsearch -LLL -Q -s base -H ldap://" & myLDAP & " defaultNamingContext | /usr/bin/awk '/defaultNamingContext/{print $2}'") as text
                -- awk -F, '/rootDomainNamingContext/{print $(NF-1)","$NF}' to take only last two search base fields
                log "  mySearchBase: " & mySearchBase
        on error theError
            errorOut_(theError, 1)
        end try
    end getSearchBase_

    -- Use ldapsearch to get password expiration age
    on getExpireAge_(sender)
        try
            set my expireAgeUnix to (do shell script "/usr/bin/ldapsearch -LLL -Q -s base -H ldap://" & myLDAP & " -b " & mySearchBase & " maxPwdAge | /usr/bin/awk -F- '/maxPwdAge/{print $NF/10000000}'") as integer
            if expireAgeUnix is equal to 0 then
                log "  Couldn't get expireAge. Trying using Manual method."
            else
                set my expireAge to expireAgeUnix / 86400 as integer
                log "  Got expireAge: " & expireAge
                tell defaults to setObject_forKey_(expireAge, "expireAge")
            end if
        on error theError
            errorOut_(theError, 1)
        end try
    end getExpireAge_

    -- Determine when the password was last changed
    on getPwdSetDate_(sender)
        -- number formatter for truncated decimal places
        set fmt to current application's NSNumberFormatter's alloc()'s init()
        fmt's setUsesSignificantDigits_(true)
        fmt's setMaximumSignificantDigits_(7)
        fmt's setMinimumSignificantDigits_(1)
        fmt's setDecimalSeparator_(".")
        
        set my pwdSetDateUnix to (do shell script "/usr/bin/dscl localhost read /Search/Users/\"$USER\" SMBPasswordLastSet | /usr/bin/awk '/LastSet:/{print $2}'")
        if (count words of pwdSetDateUnix) is greater than 0 then
            set my pwdSetDateUnix to last word of pwdSetDateUnix
            set my pwdSetDateUnix to ((pwdSetDateUnix as integer) / 10000000 - 11644473600)
            set my pwdSetDate to fmt's stringFromNumber_(pwdSetDateUnix / 86400)
        else if (count words of pwdSetDateUnix) is equal to 0 then
            set my pwdSetDate to -1
        end if
        log "  New pwdSetDate (" & pwdSetDate & ")"
        
        
        -- Now we compare the plist's value for pwdSetDate to the one we just calculated so
        -- we avoid using an old or bad value (i.e. when SMBPasswordLastSet can't be found by dscl)
        tell defaults to set plistPwdSetDate to objectForKey_("pwdSetDate") as real
        statusMenu's setAutoenablesItems_(false)
        if plistPwdSetDate is equal to 0 then
            set my skipKerb to true
            log "  will be saved to plist."
            tell defaults to setObject_forKey_(pwdSetDate, "pwdSetDate")
            statusMenu's itemWithTitle_("Refresh Kerberos Ticket")'s setEnabled_(not skipKerb)
            statusMenu's itemWithTitle_("Change Password…")'s setEnabled_(not skipKerb)
        else if plistPwdSetDate is less than or equal to pwdSetDate then
            log "  ≥ plist value (" & plistPwdSetDate & ") so we use it"
            tell defaults to setObject_forKey_(pwdSetDate, "pwdSetDate")
            -- If we can get a valid pwdSetDate, then we're on the network, so enable kerb features
            set my skipKerb to false
            statusMenu's itemWithTitle_("Refresh Kerberos Ticket")'s setEnabled_(not skipKerb)
            statusMenu's itemWithTitle_("Change Password…")'s setEnabled_(not skipKerb)
        else if plistPwdSetDate is greater than pwdSetDate then
            log "  < plist value (" & plistPwdSetDate & ") so we ignore it"
            set my pwdSetDate to plistPwdSetDate
             -- If we can't get a valid pwdSetDate, then we're off the network, so disable kerb features
            set my skipKerb to true
            statusMenu's itemWithTitle_("Refresh Kerberos Ticket")'s setEnabled_(not skipKerb)
            statusMenu's itemWithTitle_("Change Password…")'s setEnabled_(not skipKerb)
        end if
    end getPwdSetDate_

    -- Uses 'msDS-UserPasswordExpiryTimeComputed' value from AD to get expiration date.
    on easyMethod_(sender)
        try
            set userName to short user name of (system info)
            set expireDateResult to  (do shell script "/usr/bin/dscl localhost read /Search/Users/" & userName & " msDS-UserPasswordExpiryTimeComputed")
            if "msDS-UserPasswordExpiryTimeComputed" is in expireDateResult then
                set my goEasy to true
                set my expireDate to last word of expireDateResult
            else
                set my goEasy to false
                return
            end if
            set my expireDateUnix to do shell script "echo '(" & expireDate & "/10000000)-11644473600' | /usr/bin/bc"
            log "  Got expireDateUnix: " & expireDateUnix
            tell defaults to setObject_forKey_(expireDateUnix, "expireDateUnix")
        on error theError
            errorOut_(theError, 1)
        end try
    end easyMethod_
    
    on easyDate_(timestamp)
        set my expirationDate to do shell script "/bin/date -r " & timestamp
        set todayUnix to do shell script "/bin/date +%s"
        set my daysUntilExp to ((timestamp - todayUnix) / 86400)
        log "    daysUntilExp: " & daysUntilExp
        set my daysUntilExpNice to round daysUntilExp rounding toward zero
        --log "    daysUntilExpNice: " & daysUntilExpNice
    end easyDate_
    

    -- Calculate the number of days until password expiration
    on compareDates_(sender)
        -- number formatter for truncated decimal places
        set fmt to current application's NSNumberFormatter's alloc()'s init()
        fmt's setUsesSignificantDigits_(true)
        fmt's setMaximumSignificantDigits_(7)
        fmt's setMinimumSignificantDigits_(1)
        fmt's setDecimalSeparator_(".")
        try
            set todayUnix to (do shell script "/bin/date +%s")
            set today to (todayUnix / 86400)
            set my daysUntilExp to fmt's stringFromNumber_(expireAge - (today - pwdSetDate)) as real -- removed 'as integer' to avoid rounding issue
            log "  daysUntilExp: " & daysUntilExp
            set my daysUntilExpNice to round daysUntilExp rounding toward zero
            --log "  daysUntilExpNice: " & daysUntilExpNice
        on error theError
            errorOut_(theError, 1)
        end try
    end compareDates_

    -- Get the full date of password expiration. daysUntilExp is input.
    on getExpirationDate_(remaining)
        set fullDate to (current date) + (remaining * days) as text
        --set my expirationDate to text 1 thru ((offset of ":" in fullDate) - 3) of fullDate -- this truncates the time
        set my expirationDate to fullDate
        log "  expirationDate: " & expirationDate
    end getExpirationDate_

    -- Updates the menu's title and tooltip
    on updateMenuTitle_(menu_title, tooltip)
        tell defaults to setObject_forKey_(menu_title, "menu_title")
        tell defaults to setObject_forKey_(tooltip, "tooltip")
        statusMenuController's updateDisplay()
    end updateMenuTitle_

    -- The meat of the app; gets the data and does the calculations 
    on doProcess_(sender)
        domainTest_(me)
        if selectedMethod = 0 then
            log "Starting auto process…"
        else
            log "Starting manual process…"
        end if
        
        try
            if my onDomain is true then
                theWindow's displayIfNeeded()
                set my isIdle to false
                set my theMessage to "Working…"
            
                -- Do this if we haven't run before, or the defaults have been reset.
                if my expireDateUnix = 0 and my selectedMethod = 0 then
                    getADLDAP_(me)
                    easyMethod_(me)
                    if my goEasy is false then
                        getSearchBase_(me)
                        getExpireAge_(me)
                    end if
                else
                    log "  Found expireDateUnix in plist: " & expireDateUnix
                    easyMethod_(me)
                end if

                if my goEasy is true and my selectedMethod = 0 then
                    log "  Using msDS method"
                    easyDate_(expireDateUnix)
                else
                    log "  Using alt method"
                    getPwdSetDate_(me)
                    compareDates_(me)
                    getExpirationDate_(daysUntilExp)
                end if
                
                updateMenuTitle_((daysUntilExpNice as string) & "d", "Your password expires\n" & expirationDate)
                
                set my theMessage to "Your password expires in " & daysUntilExpNice & " days\non " & expirationDate
                set my isIdle to true
                
                doNotify_(daysUntilExpNice)
            
            else
                log " Stopping."
            end if
        on error theError
            errorOut_(theError, 1)
        end try
    end doProcess_
    
    on doProcessWithWait_(sender)
        tell current application's NSThread to sleepForTimeInterval_(15)
        doProcess_(me)
    end doProcessWithWait_

    on intervalDoProcess_(sender)
        doProcess_(me)
    end intervalDoProcess_

--- INTERFACE BINDING HANDLERS ---

    -- Bound to About item
    on about_(sender)
        activate
        current application's NSApp's orderFrontStandardAboutPanel_(null)
    end about_

    -- Bound to Change Password menu item
    on changePassword_(sender)
        tell defaults to set my pwPolicy to objectForKey_("pwPolicy") as string
        tell defaults to set my pwPolicyButton to objectForKey_("pwPolicyButton") as string
        if my pwPolicy is not "" then
            tell application "System Events"
                display dialog pwPolicy with icon 2 buttons {pwPolicyButton}
            end tell
        end if
        tell application "System Preferences"
            try -- to use UI scripting
                set current pane to pane id "com.apple.preferences.users"
                activate
                tell application "System Events"
                    tell application process "System Preferences"
                        if my osVersion is less than or equal to 6 then
                            tell current application's NSThread to sleepForTimeInterval_(1)
                            click radio button "Password" of tab group 1 of window "Accounts"
                            click button "Change Password…" of tab group 1 of window "Accounts"
                        end if
                        if my osVersion is greater than 6 then
                            tell current application's NSThread to sleepForTimeInterval_(1)
                            click radio button "Password" of tab group 1 of window "Users & Groups"
                            click button "Change Password…" of tab group 1 of window "Users & Groups"
                        end if
                    end tell
                end tell
            on error theError
                errorOut_(theError, 1)
            end try
        end tell
    end changePassword_
    
    -- Bound to Prefs menu item
    on showMainWindow_(sender)
        activate
        theWindow's makeKeyAndOrderFront_(null)
    end showMainWindow_
    
    -- Bound to Quit menu item
    on quit_(sender)
        quit
    end quit_

    -- Bound to Auto radio buttons and Manual text field in Prefs window
    on useManualMethod_(sender)
        log "selectedMethod: " & sender's intValue()
        if sender's intValue() is not 1 then -- Auto sends value 1 (on), so Manual is selected
            set my isHidden to true
            set my isManualEnabled to true
            set my selectedMethod to 1
            set my expireAge to manualExpireDays as integer
            tell defaults to setObject_forKey_(1, "selectedMethod")
            tell defaults to setObject_forKey_(manualExpireDays, "expireAge")
            doProcess_(me)
        else -- Auto is selected
            set my isHidden to false
            set my isManualEnabled to false
            set my selectedMethod to 0
            set my expireAge to ""
            set my expireDateUnix to 0
            set my manualExpireDays to ""
            tell defaults to removeObjectForKey_("expireAge")
            tell defaults to removeObjectForKey_("expireDateUnix")
            tell defaults to setObject_forKey_(0, "selectedMethod")
            tell defaults to setObject_forKey_("", "expireAge")
            tell defaults to setObject_forKey_(0, "expireDateUnix")
            doKerbCheck_(me)
        end if
    end useManualMethod_

    -- Bound to warningDays box in Prefs window
    on setWarningDays_(sender)
        set my warningDays to sender's intValue() as integer
        tell defaults to setObject_forKey_(warningDays, "warningDays")
    end setWarningDays_

    -- Bound to checkInterval box in Prefs window
    on setCheckInterval_(sender)
        processTimer's invalidate() -- kills the existing timer
        set my checkInterval to sender's intValue() as real
        tell defaults to setObject_forKey_(checkInterval, "checkInterval")
        -- start a timer with the new interval
        set my processTimer to current application's NSTimer's scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_((my checkInterval * 3600) as integer, me, "intervalDoProcess:", missing value, true)
    end setCheckInterval_

    -- Bound to Notify items in menu and Prefs window
    on toggleNotify_(sender)
        if my enableNotifications as boolean is true then
            set my enableNotifications to false
            my statusMenu's itemWithTitle_("Use Notifications")'s setState_(0)
            tell defaults to setObject_forKey_(enableNotifications, "enableNotifications")
            log "Disabled notifications."
        else
            set my enableNotifications to true
            my statusMenu's itemWithTitle_("Use Notifications")'s setState_(1)
            tell defaults to setObject_forKey_(enableNotifications, "enableNotifications")
            log "Enabled notifications."
        end if
    end toggleNotify_
    
    on toggleKerbMinder_(sender)
        if my enableKerbMinder as boolean is true then
            set my enableKerbMinder to false
            my statusMenu's itemWithTitle_("Use KerbMinder")'s setState_(0)
            tell defaults to setObject_forKey_(enableKerbMinder, "enableKerbMinder")
            log "Disabled KerbMinder."
        else
            set my enableKerbMinder to true
            my statusMenu's itemWithTitle_("Use KerbMinder")'s setState_(1)
            tell defaults to setObject_forKey_(enableKerbMinder, "enableKerbMinder")
            log "Enabled KerbMinder."
        end if
    end toggleKerbMinder_

    -- Bound to Revert button in Prefs window
    on revertDefaults_(sender)
        tell defaults to removeObjectForKey_("menu_title")
        tell defaults to removeObjectForKey_("first_run")
        tell defaults to removeObjectForKey_("tooltip")
        tell defaults to removeObjectForKey_("selectedMethod")
        tell defaults to removeObjectForKey_("enableNotifications")
        tell defaults to removeObjectForKey_("checkInterval")
        tell defaults to removeObjectForKey_("expireAge")
        tell defaults to removeObjectForKey_("expireDateUnix")
        tell defaults to removeObjectForKey_("pwdSetDate")
        tell defaults to removeObjectForKey_("warningDays")
        tell defaults to removeObjectForKey_("prefsLocked")
        tell defaults to removeObjectForKey_("myLDAP")
        tell defaults to removeObjectForKey_("pwPolicy")
        tell defaults to removeObjectForKey_("pwPolicyButton")
        tell defaults to removeObjectForKey_("accTest")
        tell defaults to removeObjectForKey_("enableKerbMinder")
        do shell script "defaults delete org.pmbuko.ADPassMon"
        retrieveDefaults_(me)
        statusMenuController's updateDisplay()
        set my theMessage to "ADPassMon has been reset.
Please choose your configuration options."
    end revertDefaults_

--- INITIAL LOADING SECTION ---
    
    -- Creates the status menu and its items, using some values determined by other handlers
    on createMenu_(sender)
        set statusMenu to (my NSMenu's alloc)'s initWithTitle_("statusMenu")
        statusMenu's setAutoenablesItems_(false)
        
        set menuItem to (my NSMenuItem's alloc)'s init
        menuItem's setTitle_("About ADPassMon…")
        menuItem's setTarget_(me)
        menuItem's setAction_("about:")
        menuItem's setEnabled_(true)
        statusMenu's addItem_(menuItem)
        menuItem's release()

        set menuItem to (my NSMenuItem's alloc)'s init
        menuItem's setTitle_("Use Notifications")
        menuItem's setTarget_(me)
        menuItem's setAction_("toggleNotify:")
        menuItem's setEnabled_(true)
        menuItem's setState_(enableNotifications as integer)
        statusMenu's addItem_(menuItem)
        menuItem's release()
        
        set menuItem to (my NSMenuItem's alloc)'s init
        menuItem's setTitle_("Use KerbMinder")
        menuItem's setTarget_(me)
        menuItem's setAction_("toggleKerbMinder:")
        menuItem's setEnabled_(true)
        menuItem's setHidden_(not KerbMinderInstalled)
        menuItem's setState_(enableKerbMinder as integer)
        statusMenu's addItem_(menuItem)
        menuItem's release()
        
        set menuItem to (my NSMenuItem's alloc)'s init
        menuItem's setTitle_("Preferences…")
        menuItem's setTarget_(me)
        menuItem's setAction_("showMainWindow:")
        menuItem's setEnabled_(not prefsLocked)
        statusMenu's addItem_(menuItem)
        menuItem's release()
        
        statusMenu's addItem_(my NSMenuItem's separatorItem)
		
        set menuItem to (my NSMenuItem's alloc)'s init
        menuItem's setTitle_("Refresh Kerberos Ticket")
        menuItem's setTarget_(me)
        menuItem's setAction_("doKerbCheck:")
        menuItem's setEnabled_(onDomain as boolean)
        statusMenu's addItem_(menuItem)
        menuItem's release()
        
        set menuItem to (my NSMenuItem's alloc)'s init
        menuItem's setTitle_("Launch Ticket Viewer")
        menuItem's setTarget_(me)
        menuItem's setAction_("ticketViewer:")
        menuItem's setEnabled_(true)
        statusMenu's addItem_(menuItem)
        menuItem's release()
        
        set menuItem to (my NSMenuItem's alloc)'s init
        menuItem's setTitle_("Re-check Expiration")
        menuItem's setTarget_(me)
        menuItem's setAction_("doProcess:")
        menuItem's setEnabled_(true)
        statusMenu's addItem_(menuItem)
        menuItem's release()

        set menuItem to (my NSMenuItem's alloc)'s init
        menuItem's setTitle_("Change Password…")
        menuItem's setTarget_(me)
        menuItem's setAction_("changePassword:")
        menuItem's setEnabled_(onDomain as boolean)
        statusMenu's addItem_(menuItem)
        menuItem's release()
        
        statusMenu's addItem_(my NSMenuItem's separatorItem)
		
        set menuItem to (my NSMenuItem's alloc)'s init
        menuItem's setTitle_("Exit")
        menuItem's setTarget_(me)
        menuItem's setAction_("quit:")
        menuItem's setEnabled_(true)
        statusMenu's addItem_(menuItem)
        menuItem's release()
        
        -- Instantiate the statusItemController object and set it to use the statusMenu we just created
        set statusMenuController to (current application's class "StatusMenuController"'s alloc)'s init
        statusMenuController's createStatusItemWithMenu_(statusMenu)
        statusMenu's release()
    end createMenu_
    
    -- Do processes necessary for app initiation
    on applicationWillFinishLaunching_(aNotification)
        getOS_(me)
        regDefaults_(me) -- populate plist file with defaults (will not overwrite non-default settings))
        accTest_(me)
        KerbMinderTest_(me)
        notifySetup_(me)
        retrieveDefaults_(me) -- load defaults
        createMenu_(me)  -- build and display the status menu item
        domainTest_(me)  -- test domain connectivity
        if my onDomain is false then
            return  -- stop the process if no domain connectivity
        end if
        canPassExpire_(me)
        if passExpires then
            -- if we're using Auto and we don't have the password expiration age, check for kerberos ticket
            if my expireDateUnix = 0 and my selectedMethod = 0 then
                doKerbCheck_(me)
                if first_run then -- only display prefs window if running for first time
                    if prefsLocked as integer is equal to 0 then -- only display the window if prefs are not locked
                        log "First launch, waiting for settings..."
                        theWindow's makeKeyAndOrderFront_(null)
                        set my theMessage to "Welcome!\nPlease choose your configuration options."
                        set first_run to false
                    end if
                end if
            else if my selectedMethod is 1 then
                set my manualExpireDays to expireAge
                set my isHidden to true
                set my isManualEnabled to true
                doProcess_(me)
            else if my selectedMethod is 0 then
                set my isHidden to false
                set my isManualEnabled to false
                set my manualExpireDays to ""
                doProcess_(me)
            end if
        
            watchForWake_(me)
            
            -- Set a timer to check for domain connectivity every five minutes. (300)
            set my domainTimer to current application's NSTimer's scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(300, me, "intervalDomainTest:", missing value, true)
        
            -- Set a timer to trigger doProcess handler on an interval and spawn notifications (if enabled).
            set my processTimer to current application's NSTimer's scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_((my checkInterval * 3600), me, "intervalDoProcess:", missing value, true)
        else
            log "Password does not exipire. Stopping."
            updateMenuTitle_("[--]", "Your password does not expire.")
            set my theMessage to "Your password does not expire."
        end if
    end applicationWillFinishLaunching_
    
    on applicationShouldTerminate_(sender)
        return current application's NSTerminateNow
    end applicationShouldTerminate_

    -- This will immediately release the space in the menubar on quit
    on applicationWillTerminate_(notification)
        statusMenuController's releaseStatusItem()
        statusMenuController's release()
    end applicationWillTerminate_
end script