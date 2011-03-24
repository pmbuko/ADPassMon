--
--  ADPassMonAppDelegate.applescript
--  ADPassMon
--
--  Created by Peter Bukowinski on 3/22/11.
--  Copyright 2011 __MyCompanyName__. All rights reserved.
--

script ADPassMonAppDelegate
    -- Classes
	property parent : class "NSObject"
    property NSMenu : class "NSMenu"
	property NSMenuItem : class "NSMenuItem"

    -- Objects
    property standardUserDefaults : missing value
    property statusMenu : missing value
    property statusMenuController : missing value
    property theWindow : missing value
    property defaults : missing value -- for saved prefs
    property theMessage : missing value
    property theTimer : missing value

    property isIdle : false
    
    property tooltip : "Waiting for data"
    property kerb : ""
    property myDNS : ""
    property mySearchBase : ""
    property expireAge : ""
    property pwdSetDate : ""
    property daysUntilExp : ""
    	
	on retrieveDefaults_(sender)
		tell defaults to set my expireAge to objectForKey_("expireAge") as integer
		tell defaults to set my pwdSetDate to objectForKey_("pwdSetDate") as integer
	end retrieveDefaults_
    
    on revertDefaults_(sender)
        tell defaults to removeObjectForKey_("menu_title")
        tell defaults to removeObjectForKey_("tooltip")
		tell defaults to removeObjectForKey_("expireAge")
		tell defaults to removeObjectForKey_("pwdSetDate")
		retrieveDefaults_(me)
        statusMenuController's updateDisplay()
	end revertDefaults_
    
    on errorOut_(theError, showErr)
        if showErr = 1 then set my theMessage to theError as text
        set isIdle to false
    end errorOut_
    
    on getDNS_(sender)
        try
            set my myDNS to (do shell script "/usr/sbin/scutil --dns | /usr/bin/awk '/nameserver\\[1\\]/{print $3}'") as text
            log "myDNS: " & myDNS
        on error theError
            log theError
            errorOut_(theError)
        end try
    end getDNS_
    
    on getSearchBase_(sender)
        try
            set my mySearchBase to (do shell script "/usr/bin/ldapsearch -LLL -Q -s base -H ldap://" & myDNS & " rootDomainNamingContext | /usr/bin/awk '/rootDomainNamingContext/{print $2}'") as text
            log "mySearchBase: " & mySearchBase
        on error theError
            log theError
            errorOut_(theError, 1)
        end try
    end getSearchBase_

    on getExpireAge_(sender)
        try
            set my expireAge to (do shell script "/usr/bin/ldapsearch -LLL -Q -s base -H ldap://" & myDNS & " -b " & mySearchBase & " maxPwdAge | /usr/bin/awk -F- '/maxPwdAge/{print $2/10000000}'") as integer
            log "Got expireAge: " & expireAge
            tell defaults to setObject_forKey_(expireAge, "expireAge")
        on error theError
            log theError
            errorOut_(theError, 1)
        end try
    end getExpireAge_
        
    on doProcess_(sender)
		try
			log "Begin"
			set my isIdle to false -- app is no longer idle
            set my theMessage to "Working…"
            
            tell theWindow to displayIfNeeded()
            
            if my expireAge = 0 then
                getDNS_(me)
                getSearchBase_(me)
                getExpireAge_(me)
            else
                log "Found expireAge in plist: " & expireAge
            end if
            
            if my pwdSetDate = 0 then
                set my pwdSetDate to ((do shell script "/usr/bin/dscl localhost read /Search/Users/$USER pwdLastSet | /usr/bin/awk '/pwdLastSet:/{print $2}'") as integer) / 10000000 - 1.16444736E+10
                log "Got pwdSetDate: "& pwdSetDate
                tell defaults to setObject_forKey_(pwdSetDate, "pwdSetDate")
            else
                log "Found pwdSetDate in plist: " & pwdSetDate
            end if
            
            set today to (do shell script "date +%s") as integer
            set my daysUntilExp to (round (expireAge - (today - pwdSetDate)) / 3600 / 24) as integer
            log "daysUntilExp: " & daysUntilExp
            updateMenuTitle_("[" & daysUntilExp & "d]", "Days until password expiration")
                        
			set my theMessage to "Your password will expire in " & daysUntilExp & " days."
            set my isIdle to true
            
			log "End"
			-- for testing
        on error theError
			log theError
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
    
    on awakeFromNib()
        tell current application's NSUserDefaults to set defaults to standardUserDefaults()
        tell defaults to registerDefaults_({menu_title:"[ ? ]", tooltip:tooltip, expireAge:0, pwdSetDate:0})
        set my theMessage to "Checking for Kerberos ticket..."
        if expireAge = 0 then
            try
                set kerb to do shell script "/usr/bin/klist"
                set my theMessage to "Idle"
                set my isIdle to true
                retrieveDefaults_(me)
                doProcess_(me)
            on error theError
                set my theMessage to "No Kerberos ticket found!"
                updateMenuTitle_("[ ! ]", "No Kerberos ticket found!")
                log theError
                errorOut_(theError, 1)
            end try
        else
            retrieveDefaults_(me)
            doProcess_(me)
        end if
    end awakeFromNib
    	
	on applicationWillFinishLaunching_(aNotification)
		--create the initial status menu
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
		menuItem's setTitle_("Change Password")
		menuItem's setTarget_(me)
		menuItem's setAction_("changePassword:")
		menuItem's setEnabled_(true)
		statusMenu's addItem_(menuItem)
		menuItem's release()
        
		set menuItem to (my NSMenuItem's alloc)'s init
		menuItem's setTitle_("Show Main Window")
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
		-- Insert code here to do any housekeeping before your application quits 
		return current application's NSTerminateNow
	end applicationShouldTerminate_
	
end script