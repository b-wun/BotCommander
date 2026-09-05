# BotCommander (v1.0.0)

**BotCommander** is a lightweight command panel for World of Warcraft (3.3.5a) designed to control `mod-playerbots` with a quick-click interface while keeping your chat logs and screen clean of command spam.

**Author:** b-wun  
**Interface:** 30300 (WotLK 3.3.5a)

---

## Features

* **Smart Command Dispatcher:** Automatically routes commands to Whispers, Raid, Party, or Say based on your active target and group context.
* **Quick-Command Grid:**
  * **Movement:** Follow, Stay, Flee
  * **Combat:** Attack, Pull, Pull Back (automatically clears 'Stay' state before executing)
  * **Pacing:** Pause (`co +passive`) and Unpause (`co -passive`)
  * **Recovery:** Spirit Release, Revive, and Summon
* **Minimap & Slash Commands:** Access the panel using the draggable minimap icon or `/bc` and `/bot` slash commands.
* **Target-Aware Display:** Dynamic header shows current command destination with class-colored player names.

---

## Chat Filtering Options

Click the Horn Icon in the top-right corner of the frame to access the configuration menu:

* **Bot Responses:** Suppresses incoming bot confirmation messages (e.g., "following", "staying") from chat frames.
* **Master Messages:** Suppresses outgoing master commands from echoing in your local chat logs.
* **Chat Bubbles:** Suppresses world-space speech bubbles for bot commands and replies without disrupting normal player chat bubbles.
* **Addon Messages:** Toggles local `[BC]` status prints in your chat log.

---

## Installation

1. Download or clone this repository.
2. Place the `BotCommander` folder into your World of Warcraft directory under `Interface\AddOns\`. 
3. Verify the path matches: `Interface\AddOns\BotCommander\`. You may need to delete `-main` from the folder name. 
4. Launch World of Warcraft and enable **BotCommander** in your AddOn list.
