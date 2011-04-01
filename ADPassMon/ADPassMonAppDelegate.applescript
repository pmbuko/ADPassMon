--
--  ADPassMonAppDelegate.applescript
--  ADPassMon
--
--  Created by Peter Bukowinski on 3/24/11.
--  Copyright 2011 Peter Bukowinski. All rights reserved.
--

-- FEATURE REQUESTS
--
-- * add a Kerberos Ticket Release/Renew function (Rich Trouton) -- Done!
-- * add Preferences lock function, leaving Growl exposed (Rusty Myers) -- Done!
--

script ADPassMonAppDelegate
    
--- Classes
	property parent : class "NSObject"
    property NSMenu : class "NSMenu"
	property NSMenuItem : class "NSMenuItem"
    property timerClass : class "NSTimer" -- so we can do stuff at regular intervals
    property pNSWorkspace : class "NSWorkspace" -- for sleep notification
    property NSBundle : class "NSBundle" of current application -- for referencing files within the app bundle

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

--- Booleans
    property isIdle : true
    property isHidden : false
    property isManualEnabled : false
    property growlEnabled : false
    property prefsLocked : false
    property skipKerb : false
    
--- Other Properties
    property isGrowlRunning : ""
    property tooltip : "Waiting for data"
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
    property expirationDate : ""
    property iAm : ""
    property myDomain : ""
    property kerbID : ""

--- HANDLERS
    
    -- General error handler
    on errorOut_(theError, showErr)
        log "Error: " & theError
        if showErr = 1 then set my theMessage to theError as text -- consider removing
        set isIdle to false
    end errorOut_
    
    -- Need to get the OS version so we can handle Kerberos differently in 10.7
    on getOS_(sender)
        set my osVersion to (do shell script "system_profiler SPSoftwareDataType | awk -F. '/System Version/{print $2}'") as integer
    end getOS_
    
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
                                            prefsLocked:prefsLocked})
    end regDefaults_
    
    -- Get values from plist
	on retrieveDefaults_(sender)
        tell defaults to set my selectedMethod to objectForKey_("selectedMethod") as integer
		tell defaults to set my expireAge to objectForKey_("expireAge") as integer
		tell defaults to set my pwdSetDate to objectForKey_("pwdSetDate") as integer
        tell defaults to set my growlEnabled to objectForKey_("growlEnabled")
        tell defaults to set my warningDays to objectForKey_("warningDays")
        tell defaults to set my prefsLocked to objectForKey_("prefsLocked")
	end retrieveDefaults_
    
    -- Revert plist values to default settings
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
	end revertDefaults_
    
    -- Called when Auto is clicked in Prefs or when a value is entered in Manual
    on useManualMethod_(sender)
        log "selectedMethod: " & sender's intValue()
        if sender's intValue() is not 1 then -- Auto sends value 1
            set my isHidden to true
            set my isManualEnabled to true
            set my selectedMethod to 1
            set my expireAge to manualExpireDays as integer
            tell defaults to setObject_forKey_(1, "selectedMethod")
            tell defaults to setObject_forKey_(manualExpireDays, "expireAge")
        else
            set my isHidden to false
            set my isManualEnabled to false
            set my selectedMethod to 0
            set my expireAge to 0
            set my manualExpireDays to ""
            tell defaults to removeObjectForKey_("expireAge")
            tell defaults to setObject_forKey_(0, "selectedMethod")
            tell defaults to setObject_forKey_(0, "expireAge")
            doKerbCheck_(me)
            doProcess_(me)
        end if
    end useManualMethod_
    
    -- Set warningDays when value is entered in prefs
    on setWarningDays_(sender)
        set my warningDays to sender's intValue() as integer
        tell defaults to setObject_forKey_(warningDays, "warningDays")
    end setWarningDays_
    
    -- Called when Growl pref is checked/unchecked
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
    
    -- Register with Growl and set up notification(s)
    on growlSetup_(sender)
        tell application "System Events"
            set my isGrowlRunning to (count of (every process whose name is "GrowlHelperApp")) > 0
        end tell
        
        if isGrowlRunning is true then
            tell application "GrowlHelperApp"
                -- Make a list of all the notification types 
                -- that this script will ever send:
                set the allNotificationsList to ¬
                {"Default Notification"}
                
                -- Make a list of the notifications 
                -- that will be enabled by default.      
                -- Those not enabled by default can be enabled later 
                -- in the 'Applications' tab of the growl prefpane.
                set the enabledNotificationsList to ¬
                {"Default Notification"}
                
                -- Register with growl
                register as application ¬
                "ADPassMon" all notifications allNotificationsList ¬
                default notifications enabledNotificationsList ¬
                icon of application "ADPassMon"
            end tell
        end if
    end growlSetup_
    
    -- This handler is sent daysUntilExp and will trigger an alert if ≤ warningDays
    on growlNotify_(sender)
        if sender as integer ≤ my warningDays as integer then
            if (my isGrowlRunning and my growlEnabled) is true then
                tell application "GrowlHelperApp"
                    --	Send a Notification...
                    notify with name "Default Notification" ¬
                    title "Password Expiration Warning" ¬
                    description "Your password will expire in " & daysUntilExp & " days on " & expirationDate ¬
                    application name "ADPassMon" icon of application "ADPassMon.app"
                end tell
            end if
        end if
    end growlNotify_
        
    -- Triggers doProcess handler on wake from sleep
    on watchForWake_(sender)
        tell (pNSWorkspace's sharedWorkspace())'s notificationCenter() to ¬
            addObserver_selector_name_object_(me, "doProcess:", "NSWorkspaceDidWakeNotification", missing value)
    end watchForWake_
    
    -- Checks for kerberos ticket, necessary for auto method
    on doKerbCheck_(sender)
        if skipKerb is false
            if selectedMethod = 0 then
                try
                    log "Testing for kerb ticket"
                    set kerb to do shell script "/usr/bin/klist -s"
                    set renewKerb to do shell script "/usr/bin/kinit -R"
                    log "Kerb ticket found"
                    set my isIdle to true
                    retrieveDefaults_(me)
                    doProcess_(me)
                on error theError
                    set my theMessage to "Kerberos ticket expired or not found!"
                    log "No kerberos ticket found"
                    updateMenuTitle_("[ ! ]", "Kerberos ticket expired or not found!")
                    -- offer to renew Kerberos ticket
                    activate
                    set response to (display dialog "No Kerberos ticket was found. Do you want to renew it?" with icon 1 buttons {"No","Yes"} default button "Yes")
                    if button returned of response is "Yes" then
                        getOS_(me)
                        if my osVersion is greater than 6 then -- need to handle 10.7 specially
                            set iAm to (do shell script "whoami") as string
                            set myDomain to (do shell script "dsconfigad -show | awk -F'= ' '/Active Directory Domain/{print $2}' | tr '[:lower:]' '[:upper:]'") as string
                            set kerbID to (iAm & "@" & myDomain) as string
                            tell application "Ticket Viewer"
                                activate
                                tell application "System Events"
                                    keystroke "n" using {command down}
                                    keystroke kerbID
                                    keystroke tab
                                end tell
                            end tell
                        else -- This trick pops up a GUI kerberos password entry window in 10.6
                            do shell script "/bin/echo '' | /usr/bin/kinit -l 24h &"
                        end if
                        doKerbCheck_(me)
                    else
                        errorOut_(theError, 1)
                    end if
                end try
            else
                doProcess_(me)
            end if
        else
            doProcess_(me)
        end if
    end doKerbCheck_
    
    -- Use scutil to get AD DNS info
    on getDNS_(sender)
        try
            -- "first word of" added for 10.7 compatibility, and still works in 10.6
            set my myDNS to first word of (do shell script "/usr/sbin/scutil --dns | /usr/bin/awk '/nameserver\\[1\\]/{print $3}'") as text
            log "  myDNS: " & myDNS
        on error theError
            errorOut_(theError)
        end try
    end getDNS_
    
    -- Use ldapsearch to get search base
    on getSearchBase_(sender)
        try
            set my mySearchBase to (do shell script "/usr/bin/ldapsearch -LLL -Q -s base -H ldap://" & myDNS & " rootDomainNamingContext | /usr/bin/awk '/rootDomainNamingContext/{print $2}'") as text
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
        set my pwdSetDateUnix to (((do shell script "/usr/bin/dscl localhost read /Search/Users/$USER pwdLastSet | /usr/bin/awk '/pwdLastSet:/{print $2}'") as integer) / 10000000 - 1.16444736E+10)
        set my pwdSetDate to (pwdSetDateUnix / 86400)
        
        -- Now we compare the plist's value for pwdSetDate to the one we just calculated so
        -- we avoid using an old or bad value (i.e. negative when pwdLastSet can't be found)
        tell defaults to set my plistPwdSetDate to objectForKey_("pwdSetDate") as integer
        if plistPwdSetDate is less than pwdSetDate then
            tell defaults to setObject_forKey_(pwdSetDate, "pwdSetDate")
            log "  Got pwdSetDate: " & pwdSetDate
            set my skipKerb to false
            statusMenu's itemWithTitle_("Get/Renew Kerberos Ticket")'s setEnabled_(true)
        else if plistPwdSetDate is greater than pwdSetDate then
            set my pwdSetDate to plistPwdSetDate
            log "  Using pwdSetDate from plist: " & pwdSetDate
            set my skipKerb to true
            statusMenu's itemWithTitle_("Get/Renew Kerberos Ticket")'s setEnabled_(false)
        end if
    end getPwdSetDate_
    
    -- Calculate the number of days until password expiration
    on compareDates_(sender)
        try
            set todayUnix to (do shell script "date +%s") as integer
            set today to (todayUnix / 86400)
            set my daysUntilExp to (expireAge - (today - pwdSetDate)) as integer
            log "  daysUntilExp: " & daysUntilExp
        on error theError
            errorOut_(theError, 1)
        end try
    end compareDates_
    
    -- Get the full date of password expiration but strip off the time 
    on getExpirationDate_(remaining)
        set fullDate to (current date) + (remaining * days) as text
        set my expirationDate to text 1 thru ((offset of ":" in fullDate) - 3) of fullDate
        log "  expirationDate: " & expirationDate
    end getExpirationDate_
    
    -- The meat of the app; gets the data and does the calculations 
    on doProcess_(sender)
		try
			log "Processing…"
			set my isIdle to false
            set my theMessage to "Working…"
            
            tell theWindow to displayIfNeeded()
            
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
            updateMenuTitle_("[" & daysUntilExp & "d]", "AD Password expires on " & expirationDate)
            
			set my theMessage to "Your password will expire in " & daysUntilExp & " days
on " & expirationDate
            set my isIdle to true
            
			log "Done"
            growlNotify_(daysUntilExp)
        on error theError
            errorOut_(theError, 1)
		end try
	end doProcess_
    
    on changePassword_(sender)
        tell application "System Preferences"
            try -- to use UI scripting
                set current pane to pane "Accounts"
                tell application "System Events"
                    tell application process "System Preferences"
                        click button "Change Password…" of tab group 1 of window "Accounts"
                    end tell
                end tell
            on error theError
                errorOut_(theError, 1)
            end try
            activate
        end tell
        doProcess_(me)
    end changePassword_
    
    on about_(sender)
		activate
		current application's NSApp's orderFrontStandardAboutPanel_(null)
	end about_
	
	on showMainWindow_(sender)
		activate
		theWindow's makeKeyAndOrderFront_(null)
	end showMainWindow_
    
    on quit_(sender)
		quit
	end quit_
    
    on updateMenuTitle_(title, tip)
		set menu_title to title as text
        set tooltip to tip as text
        --log "menu_title: " & menu_title
        --log "tooltip: " & tooltip
        tell defaults to setObject_forKey_(menu_title, "menu_title")
        tell defaults to setObject_forKey_(tooltip, "tooltip")
		statusMenuController's updateDisplay()
	end updateMenuTitle_
        
-- INITIAL LOADING SECTION --    
    
    on awakeFromNib()
        watchForWake_(me)
        regDefaults_(me) -- populate plist file with defaults (will not overwrite non-default settings)
        retrieveDefaults_(me)
        growlSetup_(me)
        if expireAge = 0 then -- if we haven't yet discovered the password expiration age, check for kerberos ticket first
            if my selectedMethod = 0 then
                set my theMessage to "Checking for Kerberos ticket..."
                doKerbCheck_(me)
            end if
        else
            retrieveDefaults_(me)
            if my selectedMethod is 1 then
                set my manualExpireDays to expireAge
                set my isHidden to true
                set my isManualEnabled to true
            else if my selectedMethod is 0 then
                set my isHidden to false
                set my isManualEnabled to false
                set my manualExpireDays to ""
            end if
            doProcess_(me)
        end if

        --set up a timer to update display data every 12 hours
        timerClass's scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(43200, me, "timerDidFire:", missing value, true)
    end awakeFromNib
    
    --what should the timer do at each interval?
    on timerDidFire_(theTimer)
        doProcess_(me)
    end timerDidFire_
    	
	on applicationWillFinishLaunching_(aNotification)
		--Create the status menu items
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
        menuItem's setEnabled_(true)
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
		menuItem's setTitle_("Get/Renew Kerberos Ticket")
		menuItem's setTarget_(me)
		menuItem's setAction_("doKerbCheck:")
		menuItem's setEnabled_(true)
		statusMenu's addItem_(menuItem)
		menuItem's release()
        
		set menuItem to (my NSMenuItem's alloc)'s init
		menuItem's setTitle_("Re-check Expiration")
		menuItem's setTarget_(me)
		menuItem's setAction_("doKerbCheck:")
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

		--instantiate the statusItemController object and set it to use the statusMenu we just created
		set statusMenuController to (current application's class "StatusMenuController"'s alloc)'s init
		statusMenuController's createStatusItemWithMenu_(statusMenu)
		statusMenu's release()
    end applicationWillFinishLaunching_
    
	on applicationShouldTerminate_(sender)
		return current application's NSTerminateNow
	end applicationShouldTerminate_
    
    on applicationWillTerminate_(notification)
        statusMenuController's releaseStatusItem()
		statusMenuController's release()
    end applicationWillTerminate_
	
end script