# EmailsToCallSheet
A Drafts Action that takes a selected email thread/conversation, uses AI to extracts the important information for a project, and creates a new Draft in the format of a Call Sheet.

## Overview

This AppleScript extracts key information from an email thread in the macOS Mail app and sends it to OpenAI's API for detailed processing. The output is saved in the Drafts app, making it easy to organize and summarize email exchanges with clients. This script is especially helpful for photographers and other professionals who need to keep track of client communication.

## Features

- **Integrates with OpenAI API**: Extracts and formats key information from emails using OpenAI's API.
- **Removes Quoted Text**: Eliminates quoted text from email threads to prevent redundant information.
- **Email Analysis**: Extracts important details such as client information, project timeline, and deliverables.
- **Drafts App Integration**: Saves the processed response as a new draft in the Drafts app for easy reference.

## Dependencies

- **OpenAI API Key**: You need an OpenAI API key to access GPT-4. Store this key in your macOS Keychain under the label `OpenAI_API_Key`.
  ```sh
  security add-generic-password -a "<username>" -s "OpenAI_API_Key" -w "<YOUR_OPENAI_API_KEY>"
  ```
- **macOS Mail Application**: The script works with email threads selected in the macOS Mail app.
- **Python 3**: Required for making API calls. Python 3 is pre-installed on most modern macOS systems.
- **Drafts Application**: The script creates a new draft in the Drafts app, which must be installed and set up for automation.

## Installation

1. **Set Up OpenAI API Key**: Store your OpenAI API key in macOS Keychain using the command above.
2. **Install Python 3**: If it's not already installed, use Homebrew:
   ```sh
   brew install python
   ```
3. **Create a new action in Drafts**: In that action, add a Run AppleScript step. Paste the AppleScript into the script window. Uncheck all visibility in iOS because unfortunately, this only runs on macOS.
4. **Grant Action Permissions**: When running the first time, it will likely ask for permissions to access the Mail app and the filesystem because it has to write a temporary text file.

## Getting an OpenAI API Key

To use this script, you'll need an OpenAI API key. Here's how to get one:

1. **Sign Up or Log In**: Go to [OpenAI's website](https://platform.openai.com/signup) and sign up for an account, or log in if you already have one.
2. **Create an API Key**: Navigate to the API keys section in your OpenAI account settings. Click on **Create new secret key**.
3. **Copy the Key**: Once created, copy the API key. Be sure to store it securely, as you'll need it for configuring this script.
4. **Add to Keychain**: Store your API key in your macOS Keychain with the following terminal command:
   ```sh
   security add-generic-password -a "<username>" -s "OpenAI_API_Key" -w "<YOUR_OPENAI_API_KEY>"
   ```

## Usage

1. **Select Emails**: Open the macOS Mail app and select the email thread you want to analyze.
2. **Run the Drafts Action**: The script will:
   - Extract key information from the selected email thread.
   - Use OpenAI's API to summarize the details.
   - Save the formatted output in a new draft in the Drafts app.
3. **Customize the Output**: The output is organized into sections and can be easily edited by modifying the ChatGPT prompt.

## Adjusting the Prompt for Your Project

The default prompt used in this script is designed for general email analysis, but you can easily adjust it to fit the specific needs of your project. Here's how to do it:

1. **Locate the Prompt in the Script**: Find the section of the script where the prompt is defined. It will typically look something like this:
   ```applescript
   set promptText to "I am David Degner, the photographer, and this is an email thread with my client. Please extract the following information from the email thread for me..."
   ```
2. **Modify the Prompt**: Adjust the text to include specific details related to your project. For example, if you're a designer, you could modify it to say:
   ```applescript
   set promptText to "I am [Your Name], a graphic designer, and this is an email thread with my client. Please extract the following design-related information from the email thread..."
   ```
3. **Tailor Sections**: You can also change the sections you want the output to include. For example, if you're working on a marketing campaign, you might want to add sections like "Campaign Goals" or "Target Audience".
4. **Test the Changes**: Run the script with a sample email thread to ensure the adjusted prompt provides the output you need.

## Script Details

### Key Functions

- **`execute()`**: The main function that retrieves selected emails, processes them, and sends a request to OpenAI.
- **`removeQuotedText(emailBody)`**: Cleans the email body by removing quoted sections to avoid redundant content.

### Error Handling

- **Keychain Retrieval**: Displays an alert if the OpenAI API key is not found in Keychain.
- **API Call Errors**: Alerts the user if the API request fails.
- **Email Selection**: Alerts the user if no emails are selected.

## Security Considerations

- **Sensitive Information**: The OpenAI API key is stored in macOS Keychain for security. Only use the script on trusted devices.
- **Internet Access**: An internet connection is required to call the OpenAI API.

## License

This script is open source and available under the [MIT License](https://opensource.org/licenses/MIT).

## Contributing

Feel free to fork the repository and submit pull requests. Contributions are welcome to enhance functionality, improve error handling, or add support for other email clients or automation tools.

## Troubleshooting

- **No Response from API**: Ensure your internet connection is stable and that the API key is correctly added to Keychain.
- **Permission Issues**: Make sure you have granted automation permissions to Mail, Terminal, and Drafts in System Preferences > Security & Privacy.

For questions or assistance, please open an issue on the repository or contact me directly.
