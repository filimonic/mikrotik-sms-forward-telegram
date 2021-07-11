# Alexey D. Filimonov
# MIT License
# Source code at https://github.com/filimonic/mikrotik-sms-forward-telegram
# Version 21.06.11.12

:global TGBOTMQ

# Fill with bot key
:local TGBOTTOKEN "0000000000:AAAAAAA_AAAAAAAAAA_AAAAAAAAAAAAAAAA"
# Fill with chat_id
:local TGBOTCHATID "-123456789"

:if ([:typeof $TGBOTMQ] = "nothing") do={
	:set TGBOTMQ [:toarray ""]
}

:local TGBOTURL ( "https://api.telegram.org/bot$TGBOTTOKEN/sendMessage")

:foreach idx,msg in=$TGBOTMQ do={
    :if ($msg->"Sent" = "no") do={
        :local result ""
        :local msgBody ("{\"chat_id\":\"" . $TGBOTCHATID . "\", \"text\":\"". $msg->"Message" ."\", \"disable_web_page_preview\":true, \"parse_mode\": \"MarkdownV2\"}")
        :do {:set result [/tool fetch output=user url="$TGBOTURL" http-method=post http-data=$msgBody http-header-field="content-type: application/json" as-value]} on-error={:put ("Error sending Telegram: " . [:tostr $result])}
        :if ( ($result->"status" = "finished") and ("." . [:find ($result->"data") "\"ok\":true"] . "." != "..") ) do={
            :put "MARK message $idx as Sent"
            :set ($TGBOTMQ->$idx->"Sent") "yes"
        }
    } else={
        :if ($msg->"Sent" != "yes") do={
            :put "Message TGBOTMQ[$idx] has wrong \"Sent\" value"
        }
    }
}
