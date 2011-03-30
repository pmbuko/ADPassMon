--
--  ADPassMonAppDelegate.applescript
--  ADPassMon
--
--  Created by Peter Bukowinski on 3/24/11.
--  Copyright 2011 Peter Bukowinski. All rights reserved.
--

-- FEATURE REQUESTS
--
-- * add a Kerberos Ticket Release/Renew function (Rich Trouton)
--

script ADPassMonAppDelegate
    
    -- Classes
	property parent : class "NSObject"
    property NSMenu : class "NSMenu"
	property NSMenuItem : class "NSMenuItem"
    property timerClass : class "NSTimer"
    property pNSWorkspace : class "NSWorkspace"

    -- Objects
    property standardUserDefaults : missing value
    property statusMenu : missing value
    property statusMenuController : missing value
    property theWindow : missing value
    property defaults : missing value -- for saved prefs
    property theMessage : missing value
    property manualExpireDays : missing value
    property selectedMethod : missing value

    property isIdle : true
    property isHidden : false
    property isManualEnabled : false
    property growlEnabled : false
    
    property tooltip : "Waiting for data"
    property kerb : ""
    property myDNS : ""
    property mySearchBase : ""
    property expireAge : ""
    property expireAgeUnix : ""
    property pwdSetDate : ""
    property pwdSetDateUnix : ""
    property today : ""
    property todayUnix : ""
    property daysUntilExp : ""
    property expirationDate : ""
    
    
    on regDefaults_(sender)
        tell current application's NSUserDefaults to set defaults to standardUserDefaults()
        tell defaults to registerDefaults_({menu_title:"[ ? ]", ¬
                                            tooltip:tooltip, ¬
                                            selectedMethod:0, ¬
                                            isManualEnabled:isManualEnabled, ¬
                                            expireAge:0, ¬
                                            pwdSetDate:0, ¬
                                            growlEnabled:growlEnabled})
    end regDefaults_
    	
	on retrieveDefaults_(sender)
        tell defaults to set my selectedMethod to objectForKey_("selectedMethod") as integer
		tell defaults to set my expireAge to objectForKey_("expireAge") as integer
		tell defaults to set my pwdSetDate to objectForKey_("pwdSetDate") as integer
        tell defaults to set my growlEnabled to objectForKey_("growlEnabled")
	end retrieveDefaults_
    
    on revertDefaults_(sender)
        tell defaults to removeObjectForKey_("menu_title")
        tell defaults to removeObjectForKey_("tooltip")
        tell defaults to removeObjectForKey_("selectedMethod")
		tell defaults to removeObjectForKey_("expireAge")
		tell defaults to removeObjectForKey_("pwdSetDate")
        tell defaults to removeObjectForKey_("growlEnabled")
		retrieveDefaults_(me)
        statusMenuController's updateDisplay()
	end revertDefaults_
    
    on useManualMethod_(sender)
        log sender's intValue()
        if sender's intValue() is not 1 then
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
            doProcess_(me)
        end if
    end useManualMethod_
    
    -- General error handler
    on errorOut_(theError, showErr)
        log "Error: " & theError
        if showErr = 1 then set my theMessage to theError as text
        set isIdle to false
    end errorOut_
    
    -- This handler will let us know when the computer wakes up. Extra functions we don't need are commented out.
    on watchForWake_(sender)
        tell (pNSWorkspace's sharedWorkspace())'s notificationCenter() to ¬
            addObserver_selector_name_object_(me, "computerDidWake:", "NSWorkspaceDidWakeNotification", missing value)
    end watchForWake_
    
    -- Recalc expiration when the computer wakes
    on computerDidWake_(sender)
        doProcess_(me)
    end computerDidWake_
    
    -- Use scutil to get AD DNS info
    on getDNS_(sender)
        try
            -- "first word of" added for 10.7 compatibility, and still works in 10.6
            set my myDNS to first word of (do shell script "/usr/sbin/scutil --dns | /usr/bin/awk '/nameserver\\[1\\]/{print $3}'") as text
            log "myDNS: " & myDNS
        on error theError
            errorOut_(theError)
        end try
    end getDNS_
    
    -- Use ldapsearch to get search base
    on getSearchBase_(sender)
        try
            set my mySearchBase to (do shell script "/usr/bin/ldapsearch -LLL -Q -s base -H ldap://" & myDNS & " rootDomainNamingContext | /usr/bin/awk '/rootDomainNamingContext/{print $2}'") as text
            log "mySearchBase: " & mySearchBase
        on error theError
            errorOut_(theError, 1)
        end try
    end getSearchBase_

    -- Use ldapsearch to get password expiration age
    on getExpireAge_(sender)
        try
            set my expireAgeUnix to (do shell script "/usr/bin/ldapsearch -LLL -Q -s base -H ldap://" & myDNS & " -b " & mySearchBase & " maxPwdAge | /usr/bin/awk -F- '/maxPwdAge/{print $2/10000000}'") as integer
            set my expireAge to expireAgeUnix / 86400 as integer
            log "Got expireAge: " & expireAge
            tell defaults to setObject_forKey_(expireAge, "expireAge")
        on error theError
            errorOut_(theError, 1)
        end try
    end getExpireAge_
    
    -- Calculate the number of days until password expiration
    on compareDates_(sender)
        try
            set todayUnix to (do shell script "date +%s") as integer
            set today to (todayUnix / 86400)
            set my daysUntilExp to (expireAge - (today - pwdSetDate)) as integer
            log "daysUntilExp: " & daysUntilExp
        on error theError
            errorOut_(theError, 1)
        end try
    end compareDates_
    
    -- Get the full date of password expiration but strip off the time 
    on getExpirationDate_(remaining)
        set fullDate to (current date) + (remaining * days) as text
        set my expirationDate to text 1 thru ((offset of ":" in fullDate) - 3) of fullDate
        log "expirationDate: " & expirationDate
    end getExpirationDate_
    
    -- Do most of the calculations. This is the main handler.
    on doProcess_(sender)
		try
			log "Processing…"
			set my isIdle to false
            set my theMessage to "Working…"
            
            tell theWindow to displayIfNeeded()
            
            -- Do this if we haven't run before, or the defaults have been reset.
            if my expireAge = 0
                getDNS_(me)
                getSearchBase_(me)
                getExpireAge_(me)
            else
                log "Found expireAge in plist: " & expireAge
            end if
            
            -- Do this if we haven't run before, or the defaults have been reset.
            if my pwdSetDate = 0 then
                --set my pwdSetDateUnix to (((do shell script "/usr/bin/dscl /Active\\ Directory/All\\ Domains/ read /Users/$USER pwdLastSet | /usr/bin/awk '/pwdLastSet:/{print $2}'") as integer) / 10000000 - 1.16444736E+10)
                set my pwdSetDateUnix to (((do shell script "/usr/bin/dscl localhost read /Search/Users/$USER pwdLastSet | /usr/bin/awk '/pwdLastSet:/{print $2}'") as integer) / 10000000 - 1.16444736E+10)
                set my pwdSetDate to (pwdSetDateUnix / 86400)
                log "Got pwdSetDate: "& pwdSetDate
                tell defaults to setObject_forKey_(pwdSetDate, "pwdSetDate")
            else
                log "Found pwdSetDate in plist: " & pwdSetDate
            end if
            
            compareDates_(me)
            getExpirationDate_(daysUntilExp)
            updateMenuTitle_("[" & daysUntilExp & "d]", "AD Password expires on " & expirationDate)
            
			set my theMessage to "Your password will expire in " & daysUntilExp & " days
on " & expirationDate
            set my isIdle to true
            
			log "Done"
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
                log theError
            end try
            activate
        end tell
        revertDefaults_(me)
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

    on doKerbCheck_(sender)
        try
            log "Testing for kerb ticket"
            set kerb to do shell script "/usr/bin/klist"
            log "Kerb ticket found"
            set my isIdle to true
            retrieveDefaults_(me)
            doProcess_(me)
        on error theError
            set my theMessage to "No Kerberos ticket found!"
            log "No kerberos ticket found"
            updateMenuTitle_("[ ! ]", "No Kerberos ticket found!")
            errorOut_(theError, 1)
        end try
    end doKerbCheck_
    
-- INITIAL LOADING SECTION --    
    
    on awakeFromNib()
        watchForWake_(me)
        regDefaults_(me) -- populate plist file with defaults (will not overwrite non-default settings)
        retrieveDefaults_(me)
        set my theMessage to "Checking for Kerberos ticket..."
        if pwdSetDate = 0 then -- if we haven't yet discovered the password set date, check for kerberos ticket first
            doKerbCheck_(me)
        else
            retrieveDefaults_(me)
            if selectedMethod is 1 then
                set my manualExpireDays to expireAge
                set my isHidden to true
                set my isManualEnabled to true
            else if selectedMethod is 0 then
                set my isHidden to false
                set my isManualEnabled to false
                set my manualExpireDays to ""
            end if
            doProcess_(me)
        end if

        --set up a timer to update display data every three hours
        timerClass's scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(10800, me, "timerDidFire:", missing value, true)

    end awakeFromNib
    
    --what should the timer do at each interval?
    on timerDidFire_(theTimer)
        doProcess_(me)
    end timerDidFire_
    	
	on applicationWillFinishLaunching_(aNotification)
		--Create the status menu items
		set statusMenu to (my NSMenu's alloc)'s initWithTitle_("statusMenu")
		set menuItem to (my NSMenuItem's alloc)'s init
		menuItem's setTitle_("About ADPassMon")
		menuItem's setTarget_(me)
		menuItem's setAction_("about:")
		menuItem's setEnabled_(true)
		statusMenu's addItem_(menuItem)
		menuItem's release()
        
		statusMenu's addItem_(my NSMenuItem's separatorItem)
		
		set menuItem to (my NSMenuItem's alloc)'s init
		menuItem's setTitle_("Recalculate Expiration")
		menuItem's setTarget_(me)
		menuItem's setAction_("doProcess:")
		menuItem's setEnabled_(true)
		statusMenu's addItem_(menuItem)
		menuItem's release()

		set menuItem to (my NSMenuItem's alloc)'s init
		menuItem's setTitle_("Change Password")
		menuItem's setTarget_(me)
		menuItem's setAction_("changePassword:")
		menuItem's setEnabled_(true)
		statusMenu's addItem_(menuItem)
		menuItem's release()
        
		set menuItem to (my NSMenuItem's alloc)'s init
		menuItem's setTitle_("Preferences…")
		menuItem's setTarget_(me)
		menuItem's setAction_("showMainWindow:")
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