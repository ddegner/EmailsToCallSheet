use framework "Foundation"
use scripting additions

-- ==========================================
-- Drafts-only AppleScript Action (macOS)
-- Amend current call sheet from selected Mail messages via Gemini
-- Clean version: URL-scheme writeback only (no object refs)
-- ==========================================

-- === USER SETTINGS ===
property geminiAPIKeyName : "Gemini_API_Key" -- Keychain service name
property geminiModel : "gemini-2.5-pro-preview-03-25" -- Gemini model id

on execute(d)
	try
		-- Current draft content + uuid from Drafts-supplied record
		set callsheetText to ""
		try
			set callsheetText to (content of d)
		on error
			set callsheetText to ""
		end try
		set theUUID to my getUUIDFromRecord(d)
		if theUUID is "" then error "Could not read the current draft UUID."

		-- Gather selected Mail messages as plain text
		set mailText to my getSelectedMailThreadText()
		if mailText is "" then error "No messages are selected in Mail."

		-- Build prompt merging existing call sheet and new emails
		set promptText to my buildPrompt(callsheetText, mailText)

		-- Call Gemini for updated call sheet markdown
		set updatedText to my callGemini(promptText)
		if updatedText is "" then error "Gemini returned empty text."

		-- Write back to THIS draft using Drafts URL scheme only
		set encodedText to my encodeURIComponent(updatedText)
		set L to (length of callsheetText)
		if L < 0 then set L to 0
		set u to "drafts://x-callback-url/replaceRange?uuid=" & theUUID & "&text=" & encodedText & "&start=0&length=" & (L as text)
		open location u

		return ""
	on error errMsg number errNum
		display dialog ("An error occurred: " & errMsg & " (" & errNum & ")") buttons {"OK"} default button 1 with icon caution
		return ""
	end try
end execute


on getSelectedMailThreadText()
	-- Returns concatenated plain text for selected messages in Mail.
	set msgList to {}
	tell application "Mail"
		try
			set msgList to selected messages of message viewer 1
		on error
			set msgList to {}
		end try
		if msgList is {} then return ""
		set collected to {}
		repeat with msg in msgList
			set fromLine to "From: " & (sender of msg as text)
			set dateLine to "Date: " & ((date sent of msg) as text)
			set subjLine to "Subject: " & (subject of msg as text)
			set bodyText to (content of msg as text)
			set entry to fromLine & return & dateLine & return & subjLine & return & return & bodyText
			set end of collected to entry
		end repeat
	end tell
	set oldTID to AppleScript's text item delimiters
	set AppleScript's text item delimiters to (return & return & "----- EMAIL BREAK -----" & return & return)
	set joined to collected as text
	set AppleScript's text item delimiters to oldTID
	return joined
end getSelectedMailThreadText


on buildPrompt(existingCallsheet, newEmails)
	set intro to "You are a meticulous production coordinator. Update the EXISTING CALL SHEET with any new information found in the NEW EMAIL THREAD. Keep the existing structure and formatting. Only change fields when the new emails provide definitive updates; otherwise leave them as-is. If a field is missing and the emails provide new information, fill it in."
	set rules to "Update the section titled 'Chronological Email List' by appending only entries for emails NOT already present. Do not duplicate existing items. Preserve and replicate current markdown headings, formatting and spacing and order emails oldest→newest. Output ONLY the updated call sheet and emails; no extra commentary."
	set s to intro & return & return & rules & return & return & "===== EXISTING CALL SHEET =====" & return & existingCallsheet & return & "===== END EXISTING CALL SHEET =====" & return & return & "===== NEW EMAIL THREAD =====" & return & newEmails & return & "===== END NEW EMAIL THREAD ====="
	return s
end buildPrompt


on callGemini(promptText)
	set apiKey to my readKeychain(geminiAPIKeyName)
	if apiKey is "" then error "Gemini API key not found in Keychain (service: " & geminiAPIKeyName & ")."

	-- Build request JSON with Cocoa (safe escaping)
	set dict to current application's NSMutableDictionary's dictionary()
	set contentsArr to current application's NSMutableArray's array()

	set partsArr to current application's NSMutableArray's array()
	set partDict to current application's NSMutableDictionary's dictionary()
	partDict's setObject:promptText forKey:"text"
	partsArr's addObject:partDict

	set contentDict to current application's NSMutableDictionary's dictionary()
	contentDict's setObject:"user" forKey:"role"
	contentDict's setObject:partsArr forKey:"parts"
	contentsArr's addObject:contentDict

	dict's setObject:contentsArr forKey:"contents"

	set genCfg to current application's NSMutableDictionary's dictionary()
	genCfg's setObject:(current application's NSNumber's numberWithDouble:0.2) forKey:"temperature"
	genCfg's setObject:(current application's NSNumber's numberWithInteger:16384) forKey:"maxOutputTokens"
	dict's setObject:genCfg forKey:"generationConfig"

	set jsonData to current application's NSJSONSerialization's dataWithJSONObject:dict options:0 |error|:(missing value)
	set jsonString to (current application's NSString's alloc()'s initWithData:jsonData encoding:(current application's NSUTF8StringEncoding)) as text

	-- Header-based API key; avoid 'url' var name
	set endpointStr to "https://generativelanguage.googleapis.com/v1beta/models/" & geminiModel & ":generateContent"
	set curlCmd to "/usr/bin/curl -sS -X POST -H 'Content-Type: application/json' -H " & quoted form of ("x-goog-api-key: " & apiKey) & " --data " & quoted form of jsonString & " " & quoted form of endpointStr
	set respText to do shell script curlCmd

	-- Parse response JSON and extract concatenated text parts
	set respNSString to current application's NSString's stringWithString:respText
	set respData to respNSString's dataUsingEncoding:(current application's NSUTF8StringEncoding)
	set respObj to current application's NSJSONSerialization's JSONObjectWithData:respData options:0 |error|:(missing value)

	set candidates to respObj's objectForKey:"candidates"
	if (candidates = missing value) or ((candidates's |count|()) = 0) then error "Gemini returned no candidates."
	set firstCand to candidates's objectAtIndex:0
	set contentDict2 to firstCand's objectForKey:"content"
	set partsArray2 to contentDict2's objectForKey:"parts"
	if (partsArray2's |count|()) = 0 then error "Gemini returned no text parts."
	set outText to ""
	repeat with i from 0 to ((partsArray2's |count|()) - 1)
		set p to (partsArray2's objectAtIndex:i)
		set t to p's objectForKey:"text"
		if t is not missing value then set outText to outText & (t as text)
	end repeat
	return outText as text
end callGemini


on readKeychain(serviceName)
	set cmd to "security find-generic-password -s " & quoted form of serviceName & " -w"
	try
		set k to do shell script cmd
		return k
	on error
		return ""
	end try
end readKeychain


on encodeURIComponent(t)
	set ns to current application's NSString's stringWithString:t
	set allowed to current application's NSCharacterSet's URLQueryAllowedCharacterSet()
	set m to allowed's mutableCopy()
	m's removeCharactersInString:"&=?+" -- conservative for query values
	set enc to ns's stringByAddingPercentEncodingWithAllowedCharacters:m
	return enc as text
end encodeURIComponent


on getUUIDFromRecord(r)
	try
		return |uuid| of r
	on error
		try
			return uuid of r
		on error
			return ""
		end try
	end try
end getUUIDFromRecord
