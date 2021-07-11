## mikrotik-sms-forward-telegram

Set of scripts to forward SMS messages to Telegram

### Features

* Works directly with modem
* Supports UCS2 (non-ASCII) messages

### Setup

* Create a telegram bot using @botfather
* Get chat id or group id using https://api.telegram.org/botXXX:YYYY/getUpdates 
* Fill in bot token and chat id in `tgbot-notify.rsc`
* Save all 3 scripts on your mikrotik device

### Create schedules

* `tgbot_notify_robot`   : `/system script run tgbot_notify.rsc`  at startup, interval `1m`
* `tgbot_smsfwd_robot`   : `/system script run tgbot-smsfwd.rsc`  at startup, interval `3m`
* `tgbot_notify_startup` : `/system script run tgbot-startup.rsc` at startup once

### Dusable SMS processing

* Disable SMS processing `/tool sms set receive-enabled=no auto-erase=no`

### Workflow

* Messages queued to send are stored in `TGBOTMQ` array of messages. Each message is array with mandatory `Message(str)` field and `Sent(str)` fields and any optional fields.
* `tgbot_notify_robot` task runs every minute. It looks for global `TGBOTMQ` array of messages for messages with `Sent = "no"`. It rties to send message, and if message is sent OK, message's `Sent` is set to `yes`
* `tgbot_smsfwd_robot` task runs every 3 minutes. It looks for SMS stored in SIM card, decodes them into text format and puts into `TGBOTMQ` array. Messages with `Sent` = `yes` are removed from both `TGBOTMQ` and SIM card.
* `tgbot_notify_startup` task runs at startup, waits for NTP time to be synced and sends message with boot event to `TGBOTMQ`
