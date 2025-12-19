# Drafts App Actions for Photographers

A collection of [Drafts](https://getdrafts.com/) actions that automate photography production workflows using Google Gemini AI.

**[Install from Drafts Directory](https://directory.getdrafts.com/g/23B)**

## Actions Included

### 1. NewCallSheet.scpt
Creates a new call sheet from email threads in Mail.app.

**How it works:**
1. Select one or more emails in Mail.app
2. Run the action from Drafts
3. The script automatically finds all related thread messages (by subject)
4. Gemini AI reconstructs the conversation chronologically
5. Gemini AI extracts project details into a structured call sheet
6. A new draft is created with the call sheet and conversation history

**Features:**
- Automatically discovers thread messages by normalized subject
- Strips email prefixes (`Re:`, `Fwd:`) and bracket tags (`[EXTERNAL]`, `[EXT]`, etc.)
- Deduplicates messages by Message-ID
- Sorts messages chronologically
- Caps at 50 messages to manage token limits

### 2. UpdateCallSheet.scpt
Updates an existing call sheet with new email information.

**How it works:**
1. Open an existing call sheet draft in Drafts
2. Select one or more new emails in Mail.app
3. Run the action
4. Gemini AI merges new information into the existing call sheet
5. The draft is updated in-place

**Use case:** When you receive follow-up emails after creating the initial call sheet.

### 3. CreateCaption.js
Generates photo metadata from shoot notes for Photo Mechanic ingestion.

**How it works:**
1. Create a draft with your shoot notes
2. Run the action
3. Gemini AI generates structured metadata
4. A new draft is created with the formatted output

**Output format:**
```
Slug: SubjectName
Title: Short Shoot Title  
Caption: {city:UC}, {state:UC} - {iptcmonthname:UC} {day0}: [description]...
Keywords: keyword1, keyword2, keyword3, ...
```

The caption uses Photo Mechanic template tags for automatic date/location insertion.

---

## Prerequisites

- **macOS** with Mail.app
- **[Drafts](https://getdrafts.com/)** app (macOS version)
- **Google Gemini API key** stored in Keychain
- Active internet connection

## Setup

### 1. Store your Gemini API key in Keychain

Open Terminal and run:
```bash
security add-generic-password -s "Gemini_API_Key" -a "$USER" -w "YOUR_API_KEY_HERE"
```

Replace `YOUR_API_KEY_HERE` with your actual [Gemini API key](https://aistudio.google.com/app/apikey).

### 2. Install the actions in Drafts

For AppleScript actions (`.scpt` files):
1. In Drafts, go to **Drafts → Settings → Actions**
2. Create a new Action
3. Add a step: **Script → AppleScript**
4. Copy the contents of the `.scpt` file into the script field

For JavaScript actions (`.js` files):
1. In Drafts, go to **Drafts → Settings → Actions**
2. Create a new Action
3. Add a step: **Script → Script**
4. Copy the contents of the `.js` file into the script field

### 3. Configure the Drafts Credential (for CreateCaption.js)

The JavaScript action uses Drafts' built-in GoogleAI integration:
1. The first time you run it, Drafts will prompt for your API key
2. Or configure it in **Drafts → Settings → Credentials**

## Configuration

Edit these properties at the top of each script:

| Property | Default | Description |
|----------|---------|-------------|
| `geminiAPIKeyName` | `"Gemini_API_Key"` | Keychain service name |
| `geminiModel` | `"gemini-3-flash-preview"` | Gemini model to use |
| `draftsTags` | `{"callsheet"}` | Tags applied to new drafts |
| `maxMessagesPerThread` | `50` | Maximum messages to process |
| `showAlerts` | `true` | Show error dialogs |

## Call Sheet Sections

The generated call sheet includes these sections:

| Section | Description |
|---------|-------------|
| **Location** | Photography location, address, start time |
| **Project Description** | Key objectives, scope, style, goals |
| **Team and Roles** | Team members, subjects, and their roles |
| **Client Information** | Client name, contacts, agency details |
| **Project Timeline** | Deadlines, shoot dates, delivery timelines |
| **Deliverables** | Required outputs with quantity and format |
| **Budget** | All financial details, quotes, rates |

## Error Handling

The scripts handle common errors:
- No email selected in Mail.app
- API key not found in Keychain
- Gemini API errors (rate limits, invalid responses)
- Empty or malformed responses

## License

MIT License - See [LICENSE](LICENSE) for details.

## Support

For issues or questions, please [open a GitHub issue](../../issues).
