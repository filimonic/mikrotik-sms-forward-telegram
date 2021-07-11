# Alexey D. Filimonov
# MIT License
# Source code at https://github.com/filimonic/mikrotik-sms-forward-telegram
# Version 21.06.11.12


:global TGBOTMQ
while ([:typeof $TGBOTMQ] = "nothing") do={
	:delay delay-time=2s
    :put "waiting TGBOTMQ ..."
}

while ([:typeof [/system ntp client get last-update-from ]] = "nil") do={
    :delay delay-time=2s
    :put "waiting NTP Sync ..."
}

:local bootdate [/system clock print as-value]
:local bootmessage {"Message"=("Boot at `". $bootdate->"date" . "@" . $bootdate->"time" . "`");"Sent"="no"}; 
:set ($TGBOTMQ->"startummsg") $bootmessage;
