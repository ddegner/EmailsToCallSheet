use scripting additions

-- Helper to replace characters in a string
on replace_chars(theText, searchString, replacementString)
	set AppleScript's text item delimiters to searchString
	set theItems to text items of theText
	set AppleScript's text item delimiters to replacementString
	set theText to theItems as string
	set AppleScript's text item delimiters to ""
	return theText
end replace_chars

-- Helper to remove quoted reply text from an email body
on removeQuotedText(emailBody)
	set cleanedLines to {}
	repeat with aLine in paragraphs of emailBody
		set t to aLine as string
		if t begins with ">" then
			-- skip quoted lines
		else if t begins with "On " and t contains " wrote:" then
			-- skip header lines that introduce quoted replies
		else
			set end of cleanedLines to t
		end if
	end repeat
	set AppleScript's text item delimiters to linefeed
	set cleaned to cleanedLines as string
	set AppleScript's text item delimiters to ""
	return cleaned
end removeQuotedText

-- Function to create a message link for a given message
on createMessageLink(theMessage)
	tell application "Mail"
		set messageId to message id of theMessage
		set messageSubject to subject of theMessage
	end tell
	set messageLink to "message://%3c" & messageId & "%3e"
	set markdownLink to "[" & messageSubject & "](" & messageLink & ")"
	return markdownLink
end createMessageLink

-- Function to write text to a file (UTF-8)
on writeToFile(theText, theFilePath)
	try
		do shell script "/usr/bin/printf %s " & quoted form of theText & " > " & quoted form of theFilePath
		return true
	on error errMsg
		display alert "Failed to write to file: " & errMsg
		return false
	end try
end writeToFile

-- Function to retrieve API key from Keychain
on getAPIKeyFromKeychain(keyName)
	try
		set apiKey to do shell script "security find-generic-password -w -s " & quoted form of keyName
		return apiKey
	on error
		return missing value
	end try
end getAPIKeyFromKeychain

-- New function to sort messages by date
on sortMessagesByDate(messageList)
	set sortedMessages to messageList
	set messageCount to count of sortedMessages
	tell application "Mail"
		repeat with i from 1 to (messageCount - 1)
			repeat with j from (i + 1) to messageCount
				set messageI to item i of sortedMessages
				set messageJ to item j of sortedMessages
				if date received of messageI > date received of messageJ then
					set item i of sortedMessages to messageJ
					set item j of sortedMessages to messageI
				end if
			end repeat
		end repeat
	end tell
	return sortedMessages
end sortMessagesByDate

-- Gemini API call helper
property geminiAPIKeyName : "Gemini_API_Key"
property geminiModel : "gemini-2.5-pro"

on callGeminiAPI(apiKey, promptFilePath)
	set pythonScript to "
import json
import urllib.request
import urllib.error
import sys

api_key = '" & apiKey & "'

with open('" & promptFilePath & "', 'r', encoding='utf-8') as f:
    prompt = f.read()

url = f'https://generativelanguage.googleapis.com/v1beta/models/" & geminiModel & ":generateContent?key={api_key}'

payload = {
    \"contents\": [{
        \"parts\": [{\"text\": prompt}]
    }]
}
headers = {'Content-Type': 'application/json'}

req = urllib.request.Request(url, data=json.dumps(payload).encode('utf-8'), headers=headers)

try:
    with urllib.request.urlopen(req) as response:
        result_json = json.loads(response.read().decode('utf-8'))
        if 'candidates' in result_json and result_json['candidates']:
            first_candidate = result_json['candidates'][0]
            if 'content' in first_candidate and 'parts' in first_candidate['content']:
                parts = first_candidate['content']['parts']
                if parts and parts[0]['text']:
                    print(parts[0]['text'])
                else:
                    print(\"Error: Text content not found in API response.\", file=sys.stderr)
                    sys.exit(1)
            else:
                print(\"Error: 'content' or 'parts' key not found in API response candidate.\", file=sys.stderr)
                sys.exit(1)
        else:
            print(\"Error: 'candidates' key not found or empty in API response.\", file=sys.stderr)
            sys.exit(1)

except urllib.error.HTTPError as e:
    error_info = e.read().decode('utf-8')
    print(f\"API request failed (HTTP Error): {e.code} - {error_info}\", file=sys.stderr)
    sys.exit(e.code)

except Exception as e:
    print(f\"An unexpected error occurred: {e}\", file=sys.stderr)
    sys.exit(1)
"
	try
		set apiResponse to do shell script "/usr/bin/python3 -c " & quoted form of pythonScript
		return apiResponse
	on error errMsg number errNum
		display alert "Python Script Error" message "An error occurred in the Python script:
" & errMsg & " (Error " & errNum & ")"
		return ""
	end try
end callGeminiAPI

-- Improved function to extract last message date from existing content
on getLastMessageDate(existingContent)
	try
		-- Split off the conversation section appended by NewCallSheet
		set AppleScript's text item delimiters to "------------------------------------"
		set parts to text items of existingContent
		if (count of parts) < 2 then
			set AppleScript's text item delimiters to ""
			return missing value
		end if
		set conversationPart to item -1 of parts
		set AppleScript's text item delimiters to ""
		
		-- Find last occurrence of "Date: " in the conversation part
		set AppleScript's text item delimiters to "Date: "
		set dateItems to text items of conversationPart
		if (count of dateItems) > 1 then
			set lastDateText to paragraph 1 of item -1 of dateItems
			set AppleScript's text item delimiters to linefeed
			set lastDateText to paragraph 1 of lastDateText
			set AppleScript's text item delimiters to ""
			try
				return date lastDateText
			on error
				return missing value
			end try
		end if
		set AppleScript's text item delimiters to ""
		return missing value
	on error
		return missing value
	end try
end getLastMessageDate

-- New function to validate call sheet format
on validateCallSheet(content)
	try
		-- Check for required sections
		set requiredSections to {"LOCATION:", "CLIENT INFORMATION:", "PROJECT TIMELINE:", "PROJECT DESCRIPTION:", "DELIVERABLES:", "BUDGET:"}
		set foundSections to 0
		repeat with section in requiredSections
			if content contains section then set foundSections to foundSections + 1
		end repeat
		-- Also check for the thread content separator
		if content contains "------------------------------------" then set foundSections to foundSections + 1
		return foundSections ≥ 4
	on error
		return false
	end try
end validateCallSheet

on execute()
	try
		tell application "Drafts"
			-- Get and validate selected draft
			set selectedDraft to first draft where selected is true
			if selectedDraft is missing value then
				display alert "No draft selected" message "Please select a call sheet to update." buttons {"OK"} default button "OK"
				return
			end if
			set existingContent to content of selectedDraft
			-- Validate call sheet format
			if not my validateCallSheet(existingContent) then
				display alert "Invalid Call Sheet" message "The selected draft doesn't appear to be a valid call sheet." buttons {"OK"} default button "OK"
				return
			end if
		end tell

		-- Get the last message date
		set lastMessageDate to my getLastMessageDate(existingContent)

		tell application "Mail"
			set selectedMessages to selection
			if selectedMessages is {} then
				display alert "No email selected" message "Please select the email thread." buttons {"OK"} default button "OK"
				return
			end if
			-- Sort and filter new messages
			set sortedMessages to my sortMessagesByDate(selectedMessages)
			set newMessages to {}
			repeat with msg in sortedMessages
				if lastMessageDate is missing value or (date received of msg) > lastMessageDate then
					set end of newMessages to msg
				end if
			end repeat
			if newMessages is {} then
				display alert "No new messages" message "All selected messages are already included in the call sheet." buttons {"OK"} default button "OK"
				return
			end if
			-- Process new messages
			set newThreadContent to ""
			repeat with msg in newMessages
				set emailSender to sender of msg
				set emailSubject to subject of msg
				set emailDate to date received of msg
				set emailBody to content of msg
				set cleanedBody to my removeQuotedText(emailBody)
				set messageLink to my createMessageLink(msg)
				set newThreadContent to newThreadContent & "From: " & emailSender & " / Subject: " & emailSubject & " / Date: " & emailDate & linefeed & cleanedBody & linefeed & "Message Link: " & messageLink & linefeed & "---" & linefeed & linefeed
			end repeat
		end tell

		-- Enhanced update prompt
		set updatePrompt to "Update this call sheet with new information from the email thread. Follow these rules:

1. Keep the existing project title on the first line
2. Maintain all section headings
3. Add new information to appropriate sections
4. Only replace information if explicitly updated in new emails
5. For dates and timelines, keep historical dates and add new ones
6. For budgets, maintain history of all costs/changes
7. Keep all unchanged information exactly as is

Current Call Sheet:
" & existingContent & "

New Emails to Incorporate:
" & newThreadContent
		
		-- Generate temp file path and write prompt
		set promptFilePath to do shell script "mktemp /tmp/callsheet_update_prompt.XXXXXX"
		if not my writeToFile(updatePrompt, promptFilePath) then error "Failed to write prompt to temporary file"
		
		-- Get API key and make request (Gemini)
		set geminiAPIKey to my getAPIKeyFromKeychain(geminiAPIKeyName)
		if geminiAPIKey is missing value then
			display alert "API Key Not Found" message "Please store your Gemini API Key in the Keychain." buttons {"OK"} default button "OK"
			return
		end if
		set apiResponse to my callGeminiAPI(geminiAPIKey, promptFilePath)
		if apiResponse begins with "API request failed:" or apiResponse begins with "Error:" then
			display alert "API Error" message apiResponse buttons {"OK"} default button "OK"
			return
		end if
		
		-- Validate response before updating
		if not my validateCallSheet(apiResponse) then
			display alert "Invalid Response" message "The API response doesn't match the expected call sheet format." buttons {"OK"} default button "OK"
			return
		end if
		
		-- Update the draft
		tell application "Drafts"
			set content of selectedDraft to apiResponse
		end tell
		
		-- Clean up temp file
		do shell script "rm " & quoted form of promptFilePath
		
	on error errMsg number errNum
		display alert "An error occurred: " & errMsg & " (Error " & errNum & ")"
	end try
end execute

execute()
