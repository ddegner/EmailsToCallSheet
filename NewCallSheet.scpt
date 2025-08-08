use framework "Foundation"
use framework "PDFKit"
use scripting additions

-- *** USER-ADJUSTABLE VARIABLES ***
property geminiAPIKeyName : "Gemini_API_Key" -- Name of the API key in Keychain
property geminiModel : "gemini-2.5-pro" -- Gemini model to use (e.g., "gemini-2.5-pro", "gemini-2.5-flash")
property draftsTags : {"callsheet"} -- Multiple tags to apply to the new draft in Drafts
property prompt_intro : "You are a highly skilled administrative assistant. Your task is to create a markdown call sheet for photographer David Degner.  Extract all relevant project details from the following email thread with his client to populate the call sheet sections below.

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

CLIENT INFORMATION:  List the client or company name, main contact person (and their role, if mentioned), and relevant contact details (email, phone) directly, without labels. Include the agency name and contact information if an agency is involved.

PROJECT TIMELINE: List and label relevant dates mentioned in the email, such as deadlines, shoot dates, and delivery timelines.

DELIVERABLES: List all required outputs (photos, videos) with quantity, format, and settings.

BUDGET:  Extract all mentions of budgets, costs, fees, or pricing.  Include estimates, quotes, rates, and any monetary values (e.g., '$500', 'USD', 'total cost').  Capture all financial details, even if implied or indirect. Look for keywords like 'budget', 'cost', 'estimate', 'fee', 'pricing', 'cost breakdown', 'quote', 'rate'."

property conversation_prompt_intro : "Please reconstruct the following emails into a coherent email thread, presenting the messages in the correct chronological order.  Remove any redundent quoted text or redundant email signatures.  For each message, please include the sender's name, the date, and the time the message was sent, followed by the message content.  Format each message in markdown like this:

**From:** Sender Name, Date of message, Time of message

Message Content

---

Email Thread Content:"

-- *** END USER-ADJUSTABLE VARIABLES ***

-- Function to replace characters in a string (Not strictly necessary, but kept for now)
on replace_chars(theText, searchString, replacementString)
	set AppleScript's text item delimiters to searchString
	set theItems to text items of theText
	set AppleScript's text item delimiters to replacementString
	set theText to theItems as string
	set AppleScript's text item delimiters to ""
	return theText
end replace_chars

-- Helper function to trim whitespace from a string
on trim(someText)
	set nsText to current application's NSString's stringWithString:someText
	set trimmedText to nsText's stringByTrimmingCharactersInSet:(current application's NSCharacterSet's whitespaceAndNewlineCharacterSet())
	return trimmedText as string
end trim

-- Helper function to URL-encode a string
on urlEncode(inputString)
	set NSString to current application's NSString's stringWithString:inputString
	set allowedChars to current application's NSCharacterSet's URLQueryAllowedCharacterSet()
	set encodedString to NSString's stringByAddingPercentEncodingWithAllowedCharacters:allowedChars
	return encodedString as string
end urlEncode

-- Helper to truncate long text blocks to avoid oversized prompts
on truncateText(someText, maxChars)
	try
		set textLength to (length of someText)
		if textLength ≤ maxChars then return someText
		set truncated to (text 1 thru maxChars of someText)
		return truncated & linefeed & "[... truncated ...]"
	on error
		return someText
	end try
end truncateText

-- Extract plain text from a PDF at the given POSIX path using PDFKit
on extractTextFromPDF(pdfPOSIXPath)
	try
		set pdfURL to current application's |NSURL|'s fileURLWithPath:pdfPOSIXPath
		set pdfDoc to current application's PDFDocument's alloc()'s initWithURL:pdfURL
		if pdfDoc is missing value then return ""
		set pageCount to (pdfDoc's pageCount()) as integer
		if pageCount ≤ 0 then return ""
		set collectedText to ""
		repeat with i from 0 to (pageCount - 1)
			set pageObj to (pdfDoc's pageAtIndex:i)
			if pageObj is not missing value then
				set pageText to (pageObj's string())
				if pageText is not missing value then
					set collectedText to collectedText & (pageText as string) & linefeed & linefeed
				end if
			end if
		end repeat
		return collectedText as string
	on error
		return ""
	end try
end extractTextFromPDF

-- For a Mail message, save all PDF attachments to a temp dir and return combined extracted text
on extractPDFsFromMessage(theMessage, attachmentsTempDir)
	tell application "Mail"
		set attList to mail attachments of theMessage
	end tell
	set combined to ""
	repeat with att in attList
		set attName to ""
		set attType to ""
		tell application "Mail"
			try
				set attName to name of att
			end try
			try
				set attType to mime type of att
			on error
				try
					set attType to content type of att
				on error
					set attType to ""
				end try
			end try
		end tell
		set isPDF to false
		if attName is not "" then
			set lowerName to ((current application's NSString's stringWithString:attName)'s lowercaseString()) as string
			if lowerName ends with ".pdf" then set isPDF to true
		end if
		if attType is not "" and attType contains "pdf" then set isPDF to true
		if isPDF then
			set safeName to my replace_chars(attName, "/", "_")
			set savePath to attachmentsTempDir & "/" & safeName
			tell application "Mail"
				save att in POSIX file savePath
			end tell
			set extracted to my extractTextFromPDF(savePath)
			set extractedTrimmed to my truncateText(extracted, 40000)
			if extractedTrimmed is not "" then
				set combined to combined & "Attachment (PDF): " & attName & linefeed & extractedTrimmed & linefeed & linefeed
			end if
		end if
	end repeat
	return combined
end extractPDFsFromMessage

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

-- Function to write text to a file using ASObjC
on writeToFile(theText, theFilePath)
	try
		set theNSString to current application's NSString's stringWithString:theText
		set theNSData to theNSString's dataUsingEncoding:(current application's NSUTF8StringEncoding)
		theNSData's writeToFile:theFilePath atomically:true
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

-- Function to sort messages by date using a custom sort
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
					-- Swap the messages
					set item i of sortedMessages to messageJ
					set item j of sortedMessages to messageI
				end if
			end repeat
		end repeat
	end tell
	return sortedMessages
end sortMessagesByDate

-- Function to call Gemini API using Python (Corrected quotes and error handling)
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
        # Extract text from the response, handling potential errors
        if 'candidates' in result_json and result_json['candidates']:
            first_candidate = result_json['candidates'][0]
            if 'content' in first_candidate and 'parts' in first_candidate['content']:
                parts = first_candidate['content']['parts']
                if parts and parts[0]['text']:
                    print(parts[0]['text'])
                else:
                    print(\"Error: Text content not found in API response.\", file=sys.stderr)
                    sys.exit(1)  # Exit with an error code
            else:
                print(\"Error: 'content' or 'parts' key not found in API response candidate.\", file=sys.stderr)
                sys.exit(1)  # Exit with an error code
        else:
            print(\"Error: 'candidates' key not found or empty in API response.\", file=sys.stderr)
            sys.exit(1)  # Exit with an error code


except urllib.error.HTTPError as e:
    error_info = e.read().decode('utf-8')
    print(f\"API request failed (HTTP Error): {e.code} - {error_info}\", file=sys.stderr)
    sys.exit(e.code)  # Exit with the HTTP error code

except Exception as e:
    print(f\"An unexpected error occurred: {e}\", file=sys.stderr)
    sys.exit(1) # Exit with a generic error code

"
	try
		set apiResponse to do shell script "/usr/bin/python3 -c " & quoted form of pythonScript
		set exitCode to (do shell script "echo $?") as integer -- Get the exit code
		
		if exitCode is not 0 then
			display alert "API Error" message "The Gemini API request failed.  Details:
" & apiResponse buttons {"OK"} default button "OK"
			return "" -- Or some other error indicator
		end if
		return apiResponse
		
	on error errMsg number errNum
		display alert "Python Script Error" message "An error occurred in the Python script:
" & errMsg & " (Error " & errNum & ")"
		return "" -- Or some other error indicator
	end try
end callGeminiAPI


-- Function to execute the main script
on execute()
	try
		-- Create a temp directory for saving PDF attachments during processing
		set attachmentsTempDir to do shell script "mktemp -d /tmp/callsheet_attachments.XXXXXX"
		tell application "Mail"
			-- Get the related messages
			if not (exists message viewer 1) then
				display alert "No message viewer" message "Please open Mail and select a message." buttons {"OK"} default button "OK"
				return
			end if
			
			set theRef to (selected messages of message viewer 1)
			if theRef is {} then
				display alert "No email selected" message "Please select an email thread." buttons {"OK"} default button "OK"
				return
			end if
			
			set {theSender, theSubject} to {sender, subject} of first item of theRef
			if theSubject starts with "Re: " or theSubject starts with "Réf : " then
				set AppleScript's text item delimiters to {"Re: ", "Réf : "}
				set theSubject to last text item of theSubject
			end if
			
			set relatedMessages to messages of message viewer 1 where all headers contains theSender and all headers contains theSubject
			
			-- Sort the messages by date received
			set sortedMessages to my sortMessagesByDate(relatedMessages)
			
			-- Initialize variables for thread content
			set threadContent to ""
			
			-- Process the messages in sorted order
			repeat with eachMessage in sortedMessages
				-- Get email details
				set emailSender to sender of eachMessage
				set emailSubject to subject of eachMessage
				set emailDate to date received of eachMessage
				set emailBody to content of eachMessage
				
				-- cleanedBody is now simply emailBody (no preprocessing)
				set cleanedBody to emailBody
				
				-- Extract any PDF attachments' text
				set pdfAttachmentsText to my extractPDFsFromMessage(eachMessage, attachmentsTempDir)
				
				-- Create and add the message link
				set messageLink to my createMessageLink(eachMessage)
				
				-- Append email details to threadContent, including any PDF text
				set threadContent to threadContent & "From: " & emailSender & " / Subject: " & emailSubject & " / Date: " & emailDate & linefeed & cleanedBody & linefeed & linefeed & pdfAttachmentsText & "Message Link: " & messageLink & linefeed & "---" & linefeed & linefeed
			end repeat
		end tell
		
		-- --- Conversation Reconstruction ---
		set fullConversationPrompt to conversation_prompt_intro & linefeed & threadContent
		
		-- Generate a unique temporary file path for conversation prompt
		set conversationPromptFilePath to do shell script "mktemp /tmp/email_conversation_prompt.XXXXXX"
		-- Write the full conversation prompt to the temporary file
		my writeToFile(fullConversationPrompt, conversationPromptFilePath)
		
		-- Retrieve the Gemini API key from Keychain
		set geminiAPIKey to my getAPIKeyFromKeychain(geminiAPIKeyName)
		if geminiAPIKey is missing value then
			display alert "API Key Not Found" message "Please store your Gemini API Key in the Keychain with the key name '" & geminiAPIKeyName & "'." buttons {"OK"} default button "OK"
			-- Cleanup attachments directory
			do shell script "rm -rf " & quoted form of attachmentsTempDir
			return
		end if
		
		-- Use Python3 to make the API request to Gemini for conversation reconstruction
		set reconstructedConversationResponse to my callGeminiAPI(geminiAPIKey, conversationPromptFilePath)
		if reconstructedConversationResponse starts with "API request failed:" or reconstructedConversationResponse starts with "Error:" then
			display alert "API Error (Conversation Reconstruction)" message reconstructedConversationResponse buttons {"OK"} default button "OK"
			-- Cleanup attachments directory
			do shell script "rm -rf " & quoted form of attachmentsTempDir
			return
		end if
		set reconstructedConversation to reconstructedConversationResponse
		
		-- --- Information Extraction ---
		set fullPrompt to prompt_intro & linefeed & linefeed & "Email Thread Content:" & linefeed & threadContent
		
		-- Generate a unique temporary file path for main prompt
		set promptFilePath to do shell script "mktemp /tmp/email_processor_prompt.XXXXXX"
		
		-- Write the full prompt to the temporary file
		my writeToFile(fullPrompt, promptFilePath)
		
		-- Use Python3 to make the API request to Gemini for information extraction
		set apiResponse to my callGeminiAPI(geminiAPIKey, promptFilePath) -- Re-use geminiAPIKey
		if apiResponse starts with "API request failed:" or apiResponse starts with "Error:" then
			display alert "API Error (Information Extraction)" message apiResponse buttons {"OK"} default button "OK"
			-- Cleanup attachments directory
			do shell script "rm -rf " & quoted form of attachmentsTempDir
			return
		end if
		
		-- Create a new draft in Drafts app
		tell application "Drafts"
			set fullContent to "" & my replace_chars(apiResponse, return, linefeed) & linefeed & linefeed & "------------------------------------
" & reconstructedConversation
			make new draft with properties {content:fullContent, flagged:false, tags:draftsTags} -- Use draftsTags list
		end tell
		
		-- Cleanup attachments directory
		do shell script "rm -rf " & quoted form of attachmentsTempDir
		
	on error errMsg number errNum
		-- Attempt to cleanup temp attachments directory if it exists
		try
			if attachmentsTempDir is not missing value then do shell script "rm -rf " & quoted form of attachmentsTempDir
		end try
		display alert "An error occurred: " & errMsg & " (Error " & errNum & ")"
	end try
end execute

-- Run the execute function
execute()
