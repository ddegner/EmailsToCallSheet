use framework "Foundation"
use scripting additions

-- =====================================================
-- Drafts: Mail → Call Sheet (Gemini) — clean version
-- =====================================================
-- Notes for Drafts AppleScript actions (macOS):
--  • Drafts calls `on execute(d)` automatically. Do NOT call execute() at top level.
--  • Always return only primitive values (e.g., text) to avoid serialization issues.
--  • When scripting Drafts from Drafts, don't wait for replies. Wrap creates/sets in
--    `ignoring application responses`.
--  • Avoid long UI interactions; Drafts may time out waiting on other apps.

-- *** USER SETTINGS ***
property geminiAPIKeyName : "Gemini_API_Key" -- Keychain service name for the Gemini API key
property geminiModel : "gemini-2.5-pro" -- Primary model
property draftsTags : {"callsheet"}
property maxMessagesPerThread : 50 -- Cap to limit token/latency
property showAlerts : true -- Set false to suppress display alerts when running from Drafts

property prompt_intro : "You are a highly skilled administrative assistant. Your task is to create a markdown call sheet for photographer David Degner. Extract all relevant project details from the following email thread with his client to populate the call sheet sections below.

Formatting Instructions:

Format the call sheet in markdown.
The first line should be the shoot date and the project title in the format: # YYYYMMDD - {project-title}
If the shoot date is unknown use XXXXXXXXX in place of the YYYYMMDD.
Include markdown headings for each of the sections listed below.
For sections with no information from the email thread, include only the heading and leave the content blank.
Do not include information not explicitly stated in the email thread.
Omit conversational pleasantries and sign-offs.
Do NOT use HTML; use markdown for all text formatting.

Section Headings and Information to Extract:

LOCATION: Specify the photography location or client address and start time.

PROJECT DESCRIPTION: Summarize the project's key objectives, scope, and any mentioned style, goals, or focus areas.

TEAM AND ROLES: Identify all mentioned team members, subjects and their roles.

CLIENT INFORMATION: List the client or company name, main contact person (and their role, if mentioned), and relevant contact details (email, phone) directly, without labels. Include the agency name and contact information if an agency is involved.

PROJECT TIMELINE: List and label relevant dates mentioned in the email, such as deadlines, shoot dates, and delivery timelines.

DELIVERABLES: List all required outputs (photos, videos) with quantity, format, and settings.

BUDGET: Extract all mentions of budgets, costs, fees, or pricing. Include estimates, quotes, rates, and any monetary values (e.g., '$500', 'USD', 'total cost'). Capture all financial details, even if implied or indirect. Look for keywords like 'budget', 'cost', 'estimate', 'fee', 'pricing', 'cost breakdown', 'quote', 'rate'."

property conversation_prompt_intro : "Please reconstruct the following emails into a coherent email thread, presenting the messages in the correct chronological order. Remove any redundant quoted text or redundant email signatures. For each message, include the sender's name, the date, and the time the message was sent, followed by the message content. Format each message in markdown like this:

**From:** Sender Name, Date of message, Time of message

Message Content

---

Email Thread Content:"

-- =============================
-- Utility helpers
-- =============================

on showAlert(t, m)
	if showAlerts then
		display alert t message m buttons {"OK"} default button "OK"
	end if
end showAlert

on replace_chars(theText, searchString, replacementString)
	set AppleScript's text item delimiters to searchString
	set theItems to text items of theText
	set AppleScript's text item delimiters to replacementString
	set theText to theItems as string
	set AppleScript's text item delimiters to ""
	return theText
end replace_chars

on trim(someText)
	set nsText to current application's NSString's stringWithString:someText
	set trimmedText to nsText's stringByTrimmingCharactersInSet:(current application's NSCharacterSet's whitespaceAndNewlineCharacterSet())
	return trimmedText as string
end trim

on normalizeSubject(s)
	set t to s as text
	repeat
		if t begins with "Re: " then
			set t to text 5 thru -1 of t
		else if t begins with "RE: " then
			set t to text 5 thru -1 of t
		else if t begins with "Fwd: " then
			set t to text 6 thru -1 of t
		else if t begins with "FW: " then
			set t to text 4 thru -1 of t
		else
			exit repeat
		end if
	end repeat
	return my trim(t)
end normalizeSubject

on createMessageLink(theMessage)
	tell application "Mail"
		set messageId to message id of theMessage
		set messageSubject to subject of theMessage
	end tell
	set messageLink to "message://%3c" & messageId & "%3e"
	set markdownLink to "[" & messageSubject & "](" & messageLink & ")"
	return markdownLink
end createMessageLink

on writeToFile(theText, theFilePath)
	try
		set theNSString to current application's NSString's stringWithString:theText
		set theNSData to theNSString's dataUsingEncoding:(current application's NSUTF8StringEncoding)
		theNSData's writeToFile:theFilePath atomically:true
		return true
	on error errMsg
		my showAlert("File Write Failed", errMsg)
		return false
	end try
end writeToFile

on getAPIKeyFromKeychain(keyName)
	try
		set apiKey to do shell script "security find-generic-password -w -s " & quoted form of keyName
		return apiKey
	on error
		return missing value
	end try
end getAPIKeyFromKeychain

on sortMessagesByDate(messageList)
	set sortedMessages to messageList
	set messageCount to count of sortedMessages
	tell application "Mail"
		repeat with i from 1 to (messageCount - 1)
			repeat with j from (i + 1) to messageCount
				set messageI to item i of sortedMessages
				set messageJ to item j of sortedMessages
				set dateI to date received of messageI
				set dateJ to date received of messageJ
				if dateI > dateJ then
					set item i of sortedMessages to messageJ
					set item j of sortedMessages to messageI
				end if
			end repeat
		end repeat
	end tell
	return sortedMessages
end sortMessagesByDate

on dedupeByMessageID(messageList)
	set resultList to {}
	set seenIDs to {}
	tell application "Mail"
		repeat with m in messageList
			set mid to message id of m
			if seenIDs does not contain mid then
				set end of seenIDs to mid
				set end of resultList to m
			end if
		end repeat
	end tell
	return resultList
end dedupeByMessageID

-- =============================
-- Gemini call via Python (stdout returns text)
-- Uses /usr/bin/env to find python3 across typical paths.
-- =============================

on callGeminiAPI(apiKey, promptFilePath, modelName)
	set py to "import json, sys, urllib.request, urllib.error\n" & ¬
		"api_key = " & quoted form of apiKey & "\n" & ¬
		"model = " & quoted form of modelName & "\n" & ¬
		"path = " & quoted form of promptFilePath & "\n" & ¬
		"with open(path, 'r', encoding='utf-8') as f:\n    prompt = f.read()\n" & ¬
		"url = f'https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}'\n" & ¬
		"payload = {'contents': [{'parts': [{'text': prompt}]}]}\n" & ¬
		"headers = {'Content-Type': 'application/json'}\n" & ¬
		"req = urllib.request.Request(url, data=json.dumps(payload).encode('utf-8'), headers=headers)\n" & ¬
		"try:\n" & ¬
		"    with urllib.request.urlopen(req) as response:\n" & ¬
		"        j = json.loads(response.read().decode('utf-8'))\n" & ¬
		"        print(j['candidates'][0]['content']['parts'][0]['text'])\n" & ¬
		"except urllib.error.HTTPError as e:\n" & ¬
		"    sys.stderr.write(e.read().decode('utf-8'))\n    sys.exit(e.code)\n" & ¬
		"except Exception as e:\n" & ¬
		"    sys.stderr.write(str(e))\n    sys.exit(1)\n"
	try
		set cmd to "/usr/bin/env -i PATH=/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin python3 -c " & quoted form of py
		set apiResponse to do shell script cmd
		return apiResponse
	on error errMsg number errNum
		my showAlert("Python Script Error", "An error occurred in the Python script:\n" & errMsg & " (Error " & errNum & ")")
		return ""
	end try
end callGeminiAPI

-- =============================
-- Drafts Action Entry Point
-- =============================

on execute(d)
	try
		set threadContent to ""
		set allRelated to {}
		set sel to {}

		with timeout of 600 seconds
			tell application "Mail"
				if not (exists message viewer 1) then
					my showAlert("No message viewer", "Open Mail and select one or more messages.")
					return ""
				end if

				set sel to (selected messages of message viewer 1)
				if sel is {} then
					my showAlert("No email selected", "Please select an email (or multiple emails) in the viewer.")
					return ""
				end if

				-- Collect related messages for each selection (subject-normalized), then dedupe by Message-ID
				repeat with baseMsg in sel
					set subjRaw to subject of baseMsg
					set subjCore to my normalizeSubject(subjRaw)
					set matches to (messages of message viewer 1 whose subject contains subjCore)
					repeat with m in matches
						set end of allRelated to m
					end repeat
				end repeat
			end tell
		end timeout

		set allRelated to my dedupeByMessageID(allRelated)
		set allRelated to my sortMessagesByDate(allRelated)

		-- Cap to the most recent N to keep prompts manageable
		set totalCount to (count of allRelated)
		if totalCount > maxMessagesPerThread then
			set startIndex to (totalCount - maxMessagesPerThread + 1)
			set allRelated to items startIndex thru totalCount of allRelated
		end if

		-- Build plain text thread content for the LLM (chronological)
		tell application "Mail"
			repeat with eachMessage in allRelated
				set emailSender to sender of eachMessage
				set emailSubject to subject of eachMessage
				set emailDate to date received of eachMessage
				set emailBody to content of eachMessage -- (fastest available body)
				set ds to (date string of emailDate)
				set ts to (time string of emailDate)
				set messageLink to my createMessageLink(eachMessage)

				set threadContent to threadContent & "From: " & emailSender & " / Subject: " & emailSubject & " / Date: " & ds & " " & ts & linefeed & emailBody & linefeed & linefeed & "Message Link: " & messageLink & linefeed & "---" & linefeed & linefeed
			end repeat
		end tell

		-- 1) Reconstruct the conversation for cleaner extraction
		set conversationPrompt to conversation_prompt_intro & linefeed & threadContent
		set conversationPromptFilePath to do shell script "mktemp /tmp/email_conversation_prompt.XXXXXX"
		my writeToFile(conversationPrompt, conversationPromptFilePath)

		set geminiAPIKey to my getAPIKeyFromKeychain(geminiAPIKeyName)
		if geminiAPIKey is missing value then
			my showAlert("API Key Not Found", "Store your Gemini API Key in Keychain with the service name '" & geminiAPIKeyName & "'.")
			return ""
		end if

		set reconstructedConversation to my callGeminiAPI(geminiAPIKey, conversationPromptFilePath, geminiModel)
		if reconstructedConversation is "" then return ""

		-- 2) Information extraction for the call sheet, using the reconstructed conversation
		set extractionPrompt to prompt_intro & linefeed & linefeed & "Reconstructed Email Thread:" & linefeed & reconstructedConversation
		set promptFilePath to do shell script "mktemp /tmp/email_processor_prompt.XXXXXX"
		my writeToFile(extractionPrompt, promptFilePath)

		set callSheetText to my callGeminiAPI(geminiAPIKey, promptFilePath, geminiModel)
		if callSheetText is "" then return ""

		-- Normalize line endings, compose final draft content
		set normalizedCallSheet to my replace_chars(callSheetText, return, linefeed)
		set fullContent to (normalizedCallSheet & linefeed & linefeed & "------------------------------------" & linefeed & reconstructedConversation) as text

		-- Create the Draft without waiting for a response
		tell application "Drafts"
			ignoring application responses
				make new draft with properties {content:fullContent, flagged:false, tags:draftsTags}
			end ignoring
		end tell

		return "" -- primitive return

	on error errMsg number errNum
		my showAlert("Error", ("An error occurred: " & errMsg & " (" & errNum & ")"))
		return ""
	end try
end execute
