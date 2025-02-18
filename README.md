# EmailsToCallSheet Script

## Overview
EmailsToCallSheet is an AppleScript that automates the creation of call sheets from email threads in Mail.app using the Google Gemini API. It's specifically designed for photographers to streamline their pre-production workflow.

## Features
- Extracts relevant project information from email threads in Mail.app
- Reconstructs email conversations in chronological order
- Generates structured call sheets with standardized sections
- Creates a new draft in the Drafts app with the call sheet and conversation history
- Uses Google Gemini AI for intelligent information extraction

## Prerequisites
- macOS with Mail.app and Drafts app installed
- Python 3
- Google Gemini API key stored in Keychain
- Active internet connection

## Setup
1. Store your Gemini API key in Keychain with the name "Gemini_API_Key"
2. Ensure Python 3 is installed on your system
3. Install the script in your AppleScript folder

## Configuration
Adjust these variables in the script as needed:
- `geminiAPIKeyName`: Name of your API key in Keychain
- `geminiModel`: Gemini model to use (e.g., "gemini-2.0-flash")
- `draftsTag`: Tag to apply to new drafts in the Drafts app

## Usage
1. Open Mail.app and select an email from the thread you want to process
2. Run the script
3. The script will:
   - Collect all related emails
   - Process them through Gemini API
   - Generate a formatted call sheet
   - Create a new draft in Drafts app with the result

## Output Sections
The generated call sheet includes:
- Client Information
- Agency Details
- Project Timeline
- Location
- Project Description
- Art Direction
- Deliverables
- Budget
- Team and Roles
- Licensing and Usage Rights
- Revisions/Feedback
- Special Requirements
- Extra Notes

## Error Handling
- Validates email selection
- Checks for API key presence
- Handles API response errors
- Provides error messages for troubleshooting

## Requirements
- macOS
- Mail.app
- Drafts app
- Python 3
- Google Gemini API access
- Internet connection

## Support
For issues or questions, please open a GitHub issue or contact the developer.
