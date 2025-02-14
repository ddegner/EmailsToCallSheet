use framework "Foundation"
use scripting additions

-- Function to remove quoted text from an email body
on removeQuotedText(emailBody)
    set nsEmailBody to current application's NSString's stringWithString:emailBody
    -- Regular expression patterns to match quoted text
    set patterns to {"(?m)^(>.*)$", "(?m)^-----Original Message-----.*", "(?m)^From:.*", "(?m)^Sent:.*", "(?m)^To:.*", "(?m)^Subject:.*"}
    repeat with pattern in patterns
        set regex to current application's NSRegularExpression's regularExpressionWithPattern:pattern options:0 |error|:(missing value)
        set nsEmailBody to regex's stringByReplacingMatchesInString:nsEmailBody options:0 range:{0, nsEmailBody's |length|()} withTemplate:""
    end repeat
    return nsEmailBody as string
end removeQuotedText

-- Function to replace characters in a string
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
    set nsString to current application's NSString's stringWithString:inputString
    set allowedChars to current application's NSCharacterSet's URLQueryAllowedCharacterSet()
    set encodedString to nsString's stringByAddingPercentEncodingWithAllowedCharacters:allowedChars
    return encodedString as string
end urlEncode

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

-- Function to call OpenAI API using Python
on callOpenAIAPI(apiKey, promptFilePath)
    set pythonScript to "
import json
import urllib.request
import urllib.error
import sys

api_key = '" & apiKey & "'

with open('" & promptFilePath & "', 'r', encoding='utf-8') as f:
    prompt = f.read()

messages = [
    {\"role\": \"user\", \"content\": prompt}
]

payload = {
    \"model\": \"gpt-4o\",
    \"messages\": messages
}

headers = {
    \"Content-Type\": \"application/json\",
    \"Authorization\": f\"Bearer {api_key}\"
}

req = urllib.request.Request(\"https://api.openai.com/v1/chat/completions\", data=json.dumps(payload).encode('utf-8'), headers=headers)

try:
    with urllib.request.urlopen(req) as response:
        result = json.loads(response.read())
        print(result['choices'][0]['message']['content'])
except urllib.error.HTTPError as e:
    error_info = e.read().decode('utf-8')
    print(f\"API request failed: {error_info}\")
    sys.exit(1)
"
    try
        set apiResponse to do shell script "/usr/bin/python3 -c " & quoted form of pythonScript
        return apiResponse
    on error errMsg
        return errMsg
    end try
end callOpenAIAPI

-- Function to execute the main script
on execute()
    try
        tell application "Mail"
            -- Get the related messages using the new method
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

                -- Remove quoted text
                set cleanedBody to my removeQuotedText(emailBody)

                -- Create and add the message link
                set messageLink to my createMessageLink(eachMessage)

                -- Append email details to threadContent
                set threadContent to threadContent & "From: " & emailSender & " / Subject: " & emailSubject & " / Date: " & emailDate & linefeed & cleanedBody & linefeed & "Message Link: " & messageLink & linefeed & "---" & linefeed & linefeed
            end repeat
        end tell

        -- Combine the prompt and the thread content
        set promptText to "I am David Degner, the photographer, and this is an email thread with my client. Please extract the following information from the email thread for me. Focus on the most relevant and clear information for each section, using explicit details mentioned in the emails.

Ensure that all detailed information is included and is accurate.

Here is the format to follow:

- Format in markdown
- The first line should be the project title, written directly without a heading.
- Subsequent sections should include a heading.
- If a section has no relevant information only write the heading and leave the section blank.

CLIENT INFORMATION:
Include the client or company requesting the work, with their main contact and role if available and relevant contact details such as email or phone numbers. Do not label each piece of information.

AGENCY:
Mention any agency or intermediary company involved, if applicable, including their name and relevant contact information.

PROJECT TIMELINE:
Extract relevant dates, including deadlines, shoot dates, or delivery timelines.

LOCATION:
Where exactly will the photography take place or what is the address of the client.

PROJECT DESCRIPTION:
Summarize the key objectives and scope of the project. Include any style, goals, or focus areas mentioned.

ART DIRECTION:
Highlight any references to stylistic direction, art direction, or creative requirements.

DELIVERABLES:
List the required outputs, such as final images, edited photos, reports, or videos. Include quantity, format, and deadlines.

BUDGET:
Extract all mentions of costs, estimates, or budgets. Look for terms such as 'budget', 'cost', 'estimate', 'fee', 'pricing', 'cost breakdown', 'quote', 'rate', or any mention of monetary values (e.g., '$500', 'USD', 'total cost'). Ensure every detail about finances is captured, even if mentioned indirectly.

TEAM AND ROLES:
Identify any other team members mentioned (e.g., assistants, models, makeup artists) and their roles.

LICENSING AND USAGE RIGHTS:
Include any mentions of licensing terms, usage rights, or agreements on how the photos will be used.

REVISIONS OR FEEDBACK:
Extract any details regarding rounds of revisions, feedback processes, or client approval steps.

SPECIAL REQUIREMENTS:
Mention any additional or unique requirements related to the shoot (e.g., equipment, props, permits, travel arrangements).

EXTRA NOTES:
Capture any additional information, such as meeting schedules, important discussions, or extra tasks."

        set fullPrompt to promptText & linefeed & linefeed & "Email Thread Content:" & linefeed & threadContent

        -- Generate a unique temporary file path
        set promptFilePath to do shell script "mktemp /tmp/email_processor_prompt.XXXXXX"

        -- Write the full prompt to the temporary file using the updated writeToFile function
        my writeToFile(fullPrompt, promptFilePath)

        -- Retrieve the OpenAI API key from Keychain
        set openAIAPIKey to my getAPIKeyFromKeychain("OpenAI_API_Key")
        if openAIAPIKey is missing value then
            display alert "API Key Not Found" message "Please store your OpenAI API Key in the Keychain." buttons {"OK"} default button "OK"
            return
        end if

        -- Use Python3 to make the API request
        set apiResponse to my callOpenAIAPI(openAIAPIKey, promptFilePath)
        if apiResponse starts with "API request failed:" then
            display alert "API Error" message apiResponse buttons {"OK"} default button "OK"
            return
        end if

        -- Create a new draft in Drafts app with the extracted information and original thread content
        tell application "Drafts"
            set fullContent to my replace_chars(apiResponse, return, linefeed) & linefeed & linefeed & "------------------" & linefeed & my replace_chars(threadContent, "return", linefeed)
            make new draft with properties {content:fullContent, flagged:false, tags:{"1 commercial"}}
        end tell

    on error errMsg number errNum
        display alert "An error occurred: " & errMsg & " (Error " & errNum & ")"
    end try
end execute

-- Run the execute function
execute()
