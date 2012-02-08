--
--  ADPassMonAppDelegate.applescript
--  ADPassMon
--
--  Created by Peter Bukowinski on 3/24/11.

--  This software is released under the terms of the MIT license.
--  Copyright (C) 2012 by Peter Bukowinski
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
--
-- TO DO:
-- - possibly revise getSearchBase handler (#294) to only use the last two "DC=" pieces. Comment in handler
--
-- FEATURE REQUESTS:
-- - enable mcx defaults hook for adding as login item.

script ADPassMonAppDelegate

--- PROPERTIES ---    

--- Classes
	property parent : class "NSObject"
    property NSMenu : class "NSMenu"
	property NSMenuItem : class "NSMenuItem"
    property NSTimer : class "NSTimer" -- so we can do stuff at regular intervals
    property NSWorkspace : class "NSWorkspace" -- for sleep notification

--- Objects
    property standardUserDefaults : missing value
    property statusMenu : missing value
    property statusMenuController : missing value
    property theWindow : missing value
    property defaults : missing value -- for saved prefs
    property theMessage : missing value -- for stats display in pref window -- consider removing
    property manualExpireDays : missing value
    property selectedMethod : missing value
    property warningDays : missing value
    property thePassword : missing value

--- Booleans
    property isIdle : true
    property isHidden : false
    property isManualEnabled : false
    property growlEnabled : false
    property prefsLocked : false
    property launchAtLogin : false
    property skipKerb : false
    
--- Other Properties
    property isGrowlRunning : ""
    property tooltip : "Waiting for data…"
    property osVersion : ""
    property kerb : ""
    property myDNS : ""
    property mySearchBase : ""
    property expireAge : ""
    property expireAgeUnix : ""
    property pwdSetDate : ""
    property pwdSetDateUnix : ""
    property plistPwdSetDate : ""
    property today : ""
    property todayUnix : ""
    property daysUntilExp : ""
    property daysUntilExpNice : ""
    property expirationDate : ""

--- HANDLERS ---
    
    -- General error handler
    on errorOut_(theError, showErr)
        log "Script Error: " & theError
        --if showErr = 1 then set my theMessage to theError as text
        --set isIdle to false
    end errorOut_
    
    -- Need to get the OS version so we can handle Kerberos differently in 10.7
    on getOS_(sender)
        set my osVersion to (do shell script "sw_vers -productVersion | awk -F. '{print $2}'") as integer
        log "Running on OS 10." & osVersion & ".x"
    end getOS_
    
    -- Tests if Universal Access scripting service is enabled
    on accTest_(sender)
        log "Testing Universal Access settings…"
        tell application "System Events"
            set accStatus to get UI elements enabled
        end tell
        if accStatus is true then
            log "  Already enabled"
        else
            log "  Disabled"
            accEnable_(me)
        end if
    end accTest_
    
    -- Prompts to enable Universal Access scripting service
    on accEnable_(sender)
        if "80" is in (do shell script "/usr/bin/id -G") then -- checks if user is in admin group
            activate
            set response to (display dialog "For best performance, ADPassMon requires that 'access for assistive devices' be enabled.
        
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
    
    -- Register plist default settings
    on regDefaults_(sender)
        tell current application's NSUserDefaults to set defaults to standardUserDefaults()
        tell defaults to registerDefaults_({menu_title:"[ ? ]", ¬
                                            tooltip:tooltip, ¬
                                            selectedMethod:0, ¬
                                            isManualEnabled:isManualEnabled, ¬
                                            expireAge:0, ¬
                                            pwdSetDate:0, ¬
                                            growlEnabled:growlEnabled, ¬
                                            warningDays:14, ¬
                                            prefsLocked:prefsLocked, ¬
                                            launchAtLogin:launchAtLogin})
    end regDefaults_
    
    -- Get values from plist
	on retrieveDefaults_(sender)
        tell defaults to set my selectedMethod to objectForKey_("selectedMethod") as integer
        tell defaults to set my isManualEnabled to objectForKey_("isManualEnabled") as integer
		tell defaults to set my expireAge to objectForKey_("expireAge") as integer
		tell defaults to set my pwdSetDate to objectForKey_("pwdSetDate") as integer
        tell defaults to set my growlEnabled to objectForKey_("growlEnabled")
        tell defaults to set my warningDays to objectForKey_("warningDays")
        tell defaults to set my prefsLocked to objectForKey_("prefsLocked")
        tell defaults to set my launchAtLogin to objectForKey_("launchAtLogin")
	end retrieveDefaults_
    
    -- Check if app should be added to login items via MCX
    --on loginCheck_(sender)
    --    if launchAtLogin is true then
    --        
    --    end  if
    --end loginCheck_
    
    -- Register with Growl and set up notification(s)
    on growlSetup_(sender)
        log "Testing for Growl…"
        tell application "System Events"
            set my isGrowlRunning to (count of (every process whose bundle identifier is "com.Growl.GrowlHelperApp")) > 0
        end tell
        
        if isGrowlRunning is true then
            log "  Running"
            tell application id "com.Growl.GrowlHelperApp"
                -- Make a list of all notification types that this script will ever send:
                set the allNotificationsList to ¬
                {"Password Notification"}
                
                -- Make a list of the enabled notifications. Others can be enabled in Growl prefs.
                set the enabledNotificationsList to ¬
                {"Password Notification"}
                
                -- Register with Growl
                register as application "ADPassMon" ¬
                all notifications allNotificationsList ¬
                default notifications enabledNotificationsList ¬
                icon of application "ADPassMon"
            end tell
        else -- if Growl is not running
            log "  Not running"
            set my growlEnabled to false
            tell defaults to setObject_forKey_(growlEnabled, "growlEnabled")
        end if
    end growlSetup_
    
    -- This handler is sent daysUntilExpNice and will trigger an alert if ≤ warningDays
    on growlNotify_(sender)
        if sender as integer ≤ my warningDays as integer then
            if (my isGrowlRunning and my growlEnabled) is true then
                log "Sending Growl notification"
                tell application id "com.Growl.GrowlHelperApp" -- Send a notification
                    notify with name "Password Notification" ¬
                    title "Password Expiration Warning" ¬
                    description "Your password will expire in " & sender & " days on " & expirationDate ¬
                    application name "ADPassMon" ¬
                    icon of application "ADPassMon.app"
                end tell
            end if
        end if
    end growlNotify_
        
    -- Trigger doProcess handler on wake from sleep
    on watchForWake_(sender)
        tell (NSWorkspace's sharedWorkspace())'s notificationCenter() to ¬
            addObserver_selector_name_object_(me, "doProcess:", "NSWorkspaceDidWakeNotification", missing value)
    end watchForWake_
    
    -- Checks for kerberos ticket, necessary for auto method. Also bound to Refresh Kerb menu item.
    on doKerbCheck_(sender)
        if skipKerb is false then
            if selectedMethod = 0 then
                if osVersion is less than 7 then
                    try
                        log "Testing for kerberos ticket presence…"
                        set kerb to do shell script "/usr/bin/klist | /usr/bin/grep krbtgt"
                        set renewKerb to do shell script "/usr/bin/kinit -R"
                        log "  Ticket found and renewed"
                        set my isIdle to true
                        retrieveDefaults_(me)
                        doProcess_(me)
                    on error theError
                        set my theMessage to "Kerberos ticket expired or not found"
                        log "  No ticket found"
                        --updateMenuTitle_("[ ! ]", "Kerberos ticket expired or not found")
                        -- offer to renew Kerberos ticket
                        activate
                        set response to (display dialog "No Kerberos ticket was found. Do you want to renew it?" with icon 1 buttons {"No","Yes"} default button "Yes")
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
            set kerb to do shell script "/usr/bin/klist | /usr/bin/grep krbtgt"
            set renewKerb to do shell script "/usr/bin/kinit -R"
            log "  Ticket found and renewed"
            set my isIdle to true
            retrieveDefaults_(me)
            doProcess_(me)
        on error theError
            set my theMessage to "Kerberos ticket expired or not found"
            log "  No ticket found"
            --updateMenuTitle_("[ ! ]", "Kerberos ticket expired or not found")
            -- offer to renew Kerberos ticket
            activate
            set response to (display dialog "No Kerberos ticket was found. Do you want to renew it?" with icon 2 buttons {"No","Yes"} default button "Yes")
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
			set thePassword to text returned of (display dialog "Enter your password:" default answer "" with hidden answer)
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
    
    -- Use scutil to get AD DNS info
    on getDNS_(sender)
        try
            -- "first word of" added for 10.7 compatibility, which may return more than one item
            set my myDNS to first word of (do shell script "/usr/sbin/scutil --dns | /usr/bin/awk '/nameserver\\[0\\]/{print $3}'") as text
            log "  myDNS: " & myDNS
        on error theError
            errorOut_(theError)
        end try
    end getDNS_
    
    -- Use ldapsearch to get search base
    on getSearchBase_(sender)
        try
            set my mySearchBase to (do shell script "/usr/bin/ldapsearch -LLL -Q -s base -H ldap://" & myDNS & " defaultNamingContext | /usr/bin/awk '/defaultNamingContext/{print $2}'") as text
            -- awk -F, '/rootDomainNamingContext/{print $(NF-1)","$NF}' to take only last two search base fields
            log "  mySearchBase: " & mySearchBase
        on error theError
            errorOut_(theError, 1)
        end try
    end getSearchBase_

    -- Use ldapsearch to get password expiration age
    on getExpireAge_(sender)
        try
            set my expireAgeUnix to (do shell script "/usr/bin/ldapsearch -LLL -Q -s base -H ldap://" & myDNS & " -b " & mySearchBase & " maxPwdAge | /usr/bin/awk -F- '/maxPwdAge/{print $2/10000000}'") as integer
            set my expireAge to expireAgeUnix / 86400 as integer
            log "  Got expireAge: " & expireAge
            tell defaults to setObject_forKey_(expireAge, "expireAge")
        on error theError
            errorOut_(theError, 1)
        end try
    end getExpireAge_
    
    -- Determine when the password was last changed
    on getPwdSetDate_(sender)
        set my pwdSetDateUnix to (((do shell script "/usr/bin/dscl localhost read /Search/Users/$USER pwdLastSet | /usr/bin/awk '/LastSet:/{print $2}'") as integer) / 10000000 - 1.16444736E+10)
        set my pwdSetDate to (pwdSetDateUnix / 86400) as real
        log "  The new pwdSetDate (" & pwdSetDate & ")"
        
        -- Now we compare the plist's value for pwdSetDate to the one we just calculated so
        -- we avoid using an old or bad value (i.e. when pwdLastSet can't be found by dscl)
        tell defaults to set plistPwdSetDate to objectForKey_("pwdSetDate") as real
        statusMenu's setAutoenablesItems_(false)
        if plistPwdSetDate is less than or equal to pwdSetDate then
            log "    is ≥ value in plist (" & plistPwdSetDate & ") so we use it"
            tell defaults to setObject_forKey_(pwdSetDate, "pwdSetDate")
            -- If we can get a valid pwdSetDate, then we're on the network, so enable kerb features
            set my skipKerb to false
            statusMenu's itemWithTitle_("Refresh Kerberos Ticket")'s setEnabled_(not skipKerb)
        else if plistPwdSetDate is greater than pwdSetDate then
            log "    is < value in plist (" & plistPwdSetDate & ") so we ignore it"
            set my pwdSetDate to plistPwdSetDate
             -- If we can't get a valid pwdSetDate, then we're off the network, so disable kerb features
            set my skipKerb to true
            statusMenu's itemWithTitle_("Refresh Kerberos Ticket")'s setEnabled_(not skipKerb)
        end if
    end getPwdSetDate_
    
    -- Calculate the number of days until password expiration
    on compareDates_(sender)
        try
            set todayUnix to (do shell script "/bin/date +%s") as integer
            set today to (todayUnix / 86400)
            set my daysUntilExp to (expireAge - (today - pwdSetDate)) -- removed 'as integer' to avoid rounding issue
            log "  daysUntilExp: " & daysUntilExp
            set my daysUntilExpNice to round daysUntilExp rounding toward zero
            log "  daysUntilExpNice: " & daysUntilExpNice
        on error theError
            errorOut_(theError, 1)
        end try
    end compareDates_
    
    -- Get the full date of password expiration but strip off the time. daysUntilExp is input.
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
        if selectedMethod = 0 then
            log "Starting auto process…"
        else
            log "Starting manual process…"
        end if
		try
            theWindow's displayIfNeeded()
			set my isIdle to false
            set my theMessage to "Working…"
            
            -- Do this if we haven't run before, or the defaults have been reset.
            if my expireAge = 0 and my selectedMethod = 0 then
                getDNS_(me)
                getSearchBase_(me)
                getExpireAge_(me)
            else
                log "  Found expireAge in plist: " & expireAge
            end if
            
            getPwdSetDate_(me)
            compareDates_(me)
            getExpirationDate_(daysUntilExp)
            updateMenuTitle_("[" & daysUntilExpNice & "d]", "Password expires on " & expirationDate)
            
			set my theMessage to "Your password will expire in " & daysUntilExpNice & " days on
" & expirationDate
            set my isIdle to true
            
			log "Finished process"
            growlNotify_(daysUntilExpNice)
        on error theError
            errorOut_(theError, 1)
		end try
	end doProcess_

--- INTERFACE BINDING HANDLERS ---

    -- Bound to About item
    on about_(sender)
        activate
        current application's NSApp's orderFrontStandardAboutPanel_(null)
    end about_

    -- Bound to Change Password menu item
    on changePassword_(sender)
        tell application "System Preferences"
            try -- to use UI scripting
                set current pane to pane id "com.apple.preferences.users"
                tell application "System Events"
                    tell application process "System Preferences"
                        if my osVersion is less than or equal to 6 then
                            click radio button "Password" of tab group 1 of window "Accounts"
                            click button "Change Password…" of tab group 1 of window "Accounts"
                        end if
                        if my osVersion is greater than 6 then
                            click radio button "Password" of tab group 1 of window "Users & Groups"
                            click button "Change Password…" of tab group 1 of window "Users & Groups"
                        end if
                    end tell
                end tell
            on error theError
                errorOut_(theError, 1)
            end try
            activate
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
            set my expireAge to 0
            set my manualExpireDays to ""
            tell defaults to removeObjectForKey_("expireAge")
            tell defaults to setObject_forKey_(0, "selectedMethod")
            tell defaults to setObject_forKey_(0, "expireAge")
            doKerbCheck_(me)
        end if
    end useManualMethod_

    -- Bound to warningDays box in Prefs window
    on setWarningDays_(sender)
        set my warningDays to sender's intValue() as integer
        tell defaults to setObject_forKey_(warningDays, "warningDays")
    end setWarningDays_

    -- Bound to Growl items in menu and Prefs window
    on toggleGrowl_(sender)
        if my growlEnabled is true then
            set my growlEnabled to false
            tell defaults to setObject_forKey_(growlEnabled, "growlEnabled")
            statusMenu's itemWithTitle_("Use Growl Alerts")'s setState_(0)
        else
            set my growlEnabled to true
            tell defaults to setObject_forKey_(growlEnabled, "growlEnabled")
            statusMenu's itemWithTitle_("Use Growl Alerts")'s setState_(1)
        end if
    end toggleGrowl_
    
    -- Bound to Revert button in Prefs window (REMOVE ON RELEASE)
    on revertDefaults_(sender)
        tell defaults to removeObjectForKey_("menu_title")
        tell defaults to removeObjectForKey_("tooltip")
        tell defaults to removeObjectForKey_("selectedMethod")
        tell defaults to removeObjectForKey_("expireAge")
        tell defaults to removeObjectForKey_("pwdSetDate")
        tell defaults to removeObjectForKey_("warningDays")
        tell defaults to removeObjectForKey_("growlEnabled")
        tell defaults to removeObjectForKey_("prefsLocked")
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
        menuItem's setTitle_("Use Growl Alerts")
		menuItem's setTarget_(me)
		menuItem's setAction_("toggleGrowl:")
        menuItem's setEnabled_(isGrowlRunning)
        menuItem's setState_(growlEnabled)
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
		menuItem's setEnabled_(not skipKerb)
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
		menuItem's setEnabled_(true)
		statusMenu's addItem_(menuItem)
		menuItem's release()
        
		statusMenu's addItem_(my NSMenuItem's separatorItem)
		
		set menuItem to (my NSMenuItem's alloc)'s init
		menuItem's setTitle_("Quit ADPassMon")
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
        accTest_(me)
        regDefaults_(me) -- populate plist file with defaults (will not overwrite non-default settings)
        growlSetup_(me)
        retrieveDefaults_(me)
        createMenu_(me)
        
        if my expireAge = 0 and my selectedMethod = 0 then -- if we're using Auto and we don't have the password expiration age, check for kerberos ticket
            doKerbCheck_(me)
            if prefsLocked as integer is equal to 0 then -- only display the window if Prefs are not locked
                log "in the loop"
                theWindow's makeKeyAndOrderFront_(null) -- open the prefs window when running for first (assumption?) time
                set my theMessage to "Welcome!
Please choose your configuration options."
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
        
        -- Set a timer to trigger doProcess handler every 12 hrs and spawn Growl notifications (if enabled).
        NSTimer's scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(43200, me, "doProcess:", missing value, true)
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