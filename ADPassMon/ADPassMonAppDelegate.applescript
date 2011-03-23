--
--  ADPassMonAppDelegate.applescript
--  ADPassMon
--
--  Created by Peter Bukowinski on 3/22/11.
--  Copyright 2011 __MyCompanyName__. All rights reserved.
--

script ADPassMonAppDelegate
	property parent : class "NSObject"
    property NSMenu : class "NSMenu"
    property NSMenuItem : class "NSMenuItem"

    property statusMenu : missing value
    property mainWindow : missing value
    property theWindow : missing value
    
    property defaults : missing value -- for saved prefs
    property progressBar : missing value
    property warningDays : missing value
    property theMessage : missing value

    property isIdle : true
    property theCounter : 0
    
    property kerb : ""
    property myDNS : ""
    property mySearchBase : ""
    property expireAge : ""
    property pwdSetDate : ""
    property daysUntilExp : ""
    	
	on retrieveDefaults_(sender)
		tell defaults to set my expireAge to objectForKey_("expireAge") as integer
		tell defaults to set my pwdSetDate to objectForKey_("pwdSetDate") as integer
        tell defaults to set my warningDays to objectForKey_("warningDays") as integer
	end retrieveDefaults_
    
    on revertDefaults_(sender)
		tell defaults to removeObjectForKey_("expireAge")
		tell defaults to removeObjectForKey_("pwdSetDate")
		retrieveDefaults_(me)
	end revertDefaults_
    
    on saveDefaults_(sender)
        set theWarning to warningDays's stringValue()
        tell defaults to setObject_ForKey_(theWarning, "warningDays")
	end saveDefaults_

    
    on doProcess_(sender)
		try -- for testing
			log "Begin" -- for testing
			set my isIdle to false -- app is no longer idle
            -- set status message for binding
            set my theMessage to "Working…"
            
            -- this where you would do your stuff
            tell theWindow to displayIfNeeded()
            
            retrieveDefaults_(me)
            
            if my expireAge = 0 then
                log "Starting first if"
                set my theCounter to 1
                
                set my myDNS to (do shell script "/usr/sbin/scutil --dns | /usr/bin/awk '/nameserver\\[1\\]/{print $3}'") as text
                log "myDNS: " & myDNS
                
                set my mySearchBase to (do shell script "/usr/bin/ldapsearch -LLL -Q -s base -H ldap://" & myDNS & " rootDomainNamingContext | /usr/bin/awk '/rootDomainNamingContext/{print $2}'") as text
                log "mySearchBase: " & mySearchBase
                
                set my expireAge to (do shell script "/usr/bin/ldapsearch -LLL -Q -s base -H ldap://" & myDNS & " -b " & mySearchBase & " maxPwdAge | /usr/bin/awk -F- '/maxPwdAge/{print $2/10000000}'") as integer
                log "expireAge: " & expireAge
                tell defaults to setObject_forKey_(expireAge, "expireAge") as integer
            else
                log "skipped first if"
            end if
            
            if my pwdSetDate = 0 then
                log "Starting second if"
                set my theCounter to 2
                
                set my pwdSetDate to ((do shell script "/usr/bin/dscl localhost read /Search/Users/$USER pwdLastSet | /usr/bin/awk '/pwdLastSet:/{print $2}'") as integer) / 10000000 - 1.16444736E+10
                log "pwdSetDate: "& pwdSetDate
                tell defaults to setObject_forKey_(pwdSetDate, "pwdSetDate") as integer
            else
                log "skipped second if"
            end if
            
            set today to (do shell script "date +%s") as integer
            set my daysUntilExp to round (expireAge - (today - pwdSetDate)) / 3600 / 24
            log "daysUntilExp: " & daysUntilExp
                        
			set my theMessage to "Your password will expire in " & daysUntilExp & " days."
			
            set my theCounter to 3
            
            set my isIdle to true
            
			log "End"
			-- for testing
        on error theError
			log theError
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
    end changePassword_
    	
	on applicationWillFinishLaunching_(aNotification)
		-- Insert code here to initialize your application before any files are opened
        tell current application's NSUserDefaults to set defaults to standardUserDefaults()
        tell defaults to registerDefaults_({expireAge:0, pwdSetDate:0, warningDays:14})
        tell progressBar to setUsesThreadedAnimation_(true)
        set my theMessage to "Checking for Kerberos ticket..."
        try
            set kerb to do shell script "/usr/bin/klist"
            set my theMessage to "Idle"
        on error theError
            set my theMessage to "No Kerberos ticket found!"
            set my isIdle to false
            log theError
        end try
        set my theMessage to "Idle"
        retrieveDefaults_(me)
        -- doProcess_(me)
	end applicationWillFinishLaunching_
	
	on applicationShouldTerminate_(sender)
		-- Insert code here to do any housekeeping before your application quits 
		return current application's NSTerminateNow
	end applicationShouldTerminate_
	
end script