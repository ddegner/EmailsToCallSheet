use framework "Foundation"
use scripting additions

-- [Previous helper functions remain unchanged: removeQuotedText, replace_chars, createMessageLink, writeToFile, getAPIKeyFromKeychain, callOpenAIAPI]

-- Improved function to extract last message date from existing content
on getLastMessageDate(existingContent)
    try
        -- Look for the thread content section
        set AppleScript's text item delimiters to "------------------"
        set contentParts to text items of existingContent
        if (count of contentParts) < 2 then return missing value

        set threadContent to item 2 of contentParts

        -- Find all dates in the thread content
        set AppleScript's text item delimiters to "Date: "
        set dateItems to text items of threadContent

        -- Get the last date
        if (count of dateItems) > 1 then
            set lastDateText to paragraph 1 of item -1 of dateItems
            -- Remove any trailing text after the date
            set AppleScript's text item delimiters to linefeed
            set lastDateText to paragraph 1 of lastDateText
            return date lastDateText
        end if

        return missing value
    on error
        return missing value
    end try
end getLastMessageDate

-- New function to validate call sheet format
on validateCallSheet(content)
    try
        -- Check for required sections
        set requiredSections to {"CLIENT INFORMATION:", "PROJECT TIMELINE:", "PROJECT DESCRIPTION:", "DELIVERABLES:", "BUDGET:"}
        set foundSections to 0

        repeat with section in requiredSections
            if content contains section then
                set foundSections to foundSections + 1
            end if
        end repeat

        -- Also check for the thread content separator
        if content contains "------------------" then
            set foundSections to foundSections + 1
        end if

        -- Return true if we found most of the expected sections
        return foundSections ≥ 4
    on error
        return false
    end try
end validateCallSheet

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
            if not my writeToFile(updatePrompt, promptFilePath) then
                error "Failed to write prompt to temporary file"
            end if

            -- Get API key and make request
            set openAIAPIKey to my getAPIKeyFromKeychain("OpenAI_API_Key")
            if openAIAPIKey is missing value then
                display alert "API Key Not Found" message "Please store your OpenAI API Key in the Keychain." buttons {"OK"} default button "OK"
                return
            end if

            set apiResponse to my callOpenAIAPI(openAIAPIKey, promptFilePath)
            if apiResponse starts with "API request failed:" then
                display alert "API Error" message apiResponse buttons {"OK"} default button "OK"
                return
            end if

            -- Validate response before updating
            if not my validateCallSheet(apiResponse) then
                display alert "Invalid Response" message "The API response doesn't match the expected call sheet format." buttons {"OK"} default button "OK"
                return
            end if

            -- Update the draft
            set content of selectedDraft to apiResponse

            -- Clean up temp file
            do shell script "rm " & quoted form of promptFilePath

        end tell

    on error errMsg number errNum
        display alert "An error occurred: " & errMsg & " (Error " & errNum & ")"
    end try
end execute

execute()
