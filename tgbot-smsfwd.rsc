# Alexey D. Filimonov
# MIT License
# Source code at https://github.com/filimonic/mikrotik-sms-forward-telegram
# Version 21.06.11.12


:global TGBOTMQ
while ([:typeof $TGBOTMQ] = "nothing") do={
	:delay delay-time=2s
    :put "waiting TGBOTMQ ..."
}
# function hexToNum
# @param <hex> hex string
:local hexToNum do={
    :local result 0
    :local lastIdx ([:len $hex] - 1)
    :for idx from=$lastIdx to=0 step=-1 do={
        :local dec [:find "0123456789ABCDEFabcdef" [:pick $hex $idx]]
        :if ([:typeof $dec] = "nil") do={
            :set result -1
        }
        :if ($dec > 15) do={
            :set dec (dec - 6)
        }
        for pow from=$lastIdx to=($idx + 1) step=-1 do={
            :set dec (dec * 16)
        }
        :if ($result >= 0) do={
            :set result ($result + $dec)
        }
    }
    #:log info message=("hexToNum: [" . $hex . "] = [" . $result . "]")
    :return $result
}

# sms7toJSONStr converts hex string taken from TP-UD PDU SMS to JSON \uXXXX notation
#     @param <hexstr> - hex string from TP-UD part of PDU message in upper case
#     @returns hex string of 8-bit ascii characters
#     @example [$sms7toJSONStr hexstr="C8329BFD06"] => "48656C6C6F" ("Hello")
:local sms7toJSONStr do={
    # Alexey D. Filimonov <alexey@filimonic.net>
    # @param <hexstr> - hex string from TP-UD
    # 2021-06-27
    # @ref "GSM 03.38"

    #:put "sms7toJSONStr called"

    :local asciiChars ( \
        "\\u0000",  "\\u0001",  "\\u0002",  "\\u0003",  "\\u0004",  "\\u0005",  "\\u0006",  "\\u0007", \
            "\\b",      "\\t",      "\\n",  "\\u000b",      "\\f",      "\\r",  "\\u000e",  "\\u000f", \
        "\\u0010",  "\\u0011",  "\\u0012",  "\\u0013",  "\\u0014",  "\\u0015",  "\\u0016",  "\\u0017", \
        "\\u0018",  "\\u0019",  "\\u001a",  "\\u001b",  "\\u001c",  "\\u001d",  "\\u001e",  "\\u001f", \
            "\20",      "\21",       "\"",      "\23",      "\24",      "\25",  "\\u0026",  "\\u0027", \
            "\28",      "\29",      "\2A",      "\2B",      "\2C",      "\2D",      "\2E",    "\\\2F", \
            "\30",      "\31",      "\32",      "\33",      "\34",      "\35",      "\36",      "\37", \
        "\\u0038",      "\39",      "\3A",      "\3B",      "\3C",      "\3D",  "\\u003e",      "\3F", \
            "\40",      "\41",      "\42",      "\43",      "\44",      "\45",      "\46",      "\47", \
            "\48",      "\49",      "\4A",      "\4B",      "\4C",      "\4D",      "\4E",      "\4F", \
            "\50",      "\51",      "\52",      "\53",      "\54",      "\55",      "\56",      "\57", \
            "\58",      "\59",      "\5A",      "\5B",       "\\",      "\5D",      "\5E",      "\5F", \
            "\60",      "\61",      "\62",      "\63",      "\64",      "\65",      "\66",      "\67", \
            "\68",      "\69",      "\6A",      "\6B",      "\6C",      "\6D",      "\6E",      "\6F", \
            "\70",      "\71",      "\72",      "\73",      "\74",      "\75",      "\76",      "\77", \
            "\78",      "\79",      "\7A",      "\7B",      "\7C",      "\7D",      "\7E",  "\\u007F"  )

    :if ([:typeof $hexstr] = "nil") do={
        :log error "sms7toJSONStr MUST have a `hexstr` parameter!"
        :return ""
    }
    :local hs $hexstr
    
    

    # make even number of characters
    :if (([:len $hs] & 1) > 0) do={
        :set hs ($hs . "0")
    }

    :local hexVocabulary "0123456789ABCDEF"
    :local result ""
    :local prevDec 0
    :local prevDecBits 0
    :local lastIdx ([:len $hs] - 1)
    :local idx 0

    :while ((idx <= $lastIdx) || ($prevDecBits = 7)) do={
        :local byteToAdd 0
        :if ($prevDecBits = 7) do={
            :set byteToAdd (($prevDec >> 1) & 127)
            :set prevDec 0
            :set prevDecBits 0
        } else={
            :local newDec (([:find $hexVocabulary [:pick $hs $idx]] * 16) + ([:find $hexVocabulary [:pick $hs ($idx+1)]]))
            :set byteToAdd ((($newDec << $prevDecBits) & 127) + ($prevDec >> (8 - $prevDecBits)))
            :set prevDecBits ($prevDecBits + 1)
            :set prevDec $newDec
            :set idx ($idx + 2)
        }
        :local textToAdd  [:pick $asciiChars $byteToAdd]

        #:local hexToAdd ([:pick $hexVocabulary ($byteToAdd >> 4)] . [:pick $hexVocabulary ($byteToAdd & 15)])
        :set result ($result . $textToAdd)
    }
    #:put ("sms7toJSONStr result [" . $result . "]")
    :return $result
} 
#end of sms7toJSONStr


# smsGetOA converts hex string from beginning to JSON string of sms sender (TP-OA)
#     @param <hexstr> - hex string starting from TP-OA (first byte is length byte)
#     @returns object (array) with fields:
#       numberText - JSON string 
#       passChars - how many nibbles(symbols) of message should be skipped
#     @example [$smsGetOA hexstr="0B919701119905F8"] => {numberHex=3739313031313939353038 ("79101199508"); passChars=12}
:local smsGetOA do={
    :if ([:typeof $hexstr] = "nil") do={
        :log error "smsGetOA MUST have a `hexstr` parameter!"
        :return ""
    }
    :local hs $hexstr
    #:put ("smsGetOA [" . $hexstr . "]")
    :local hexVocabulary "0123456789ABCDEF"

    :local txtpos 0
    :local numberText ""
    
    :local numLen    (([:find $hexVocabulary [:pick $hs 0]] * 16) + ([:find $hexVocabulary [:pick $hs 1]]))
    :local numFormat (([:find $hexVocabulary [:pick $hs 2]] * 16) + ([:find $hexVocabulary [:pick $hs 3]]))
    :set txtpos ($txtpos + 4)

    :local realNumLen $numLen
    # Increase real num len to even number of nibbles
    :if (($realNumLen & 1) > 0) do={
        :set realNumLen ($realNumLen + 1)
    }

    #numFormat 
    #
    #    [ 7 | 6   5   4 | 3   2   1   0]
    #    [ 1 |    TON    |      NPI     ]
    #    
    #    1   = Always 1
    #    TON = Type of number. 
    #    NPI = Numbering plan identification (We are not interested in NPI)
    #
    # We are interested in TON "101" bits indicating that number is alfanumeric and should be decoded using `sms7toJSONStr`
    #:put ("numFormat: " . $numFormat)
    # If TON = 101
    if ((($numFormat >> 4) & 7) = 5 ) do={
        #:put "DECODE USING sms7toJSONStr"
        :local numBytes [:pick $hs $txtpos ($txtpos + $realNumLen)]
        #:put ("numBytes [" . $numBytes . "]")
        #:put ("sms7toJSONStr type: " . [:typeof $sms7toJSONStr])
        :set numberText [$sms7toJSONStr hexstr=$numBytes]
        #:put ("numberText [" . $numberText . "]")
    } else={
        #:put "DECODE USING normal"
        :local numTxt ""
        :for bytePos from=$txtpos to=($txtpos + $realNumLen) step=2 do={
            :set numTxt ($numTxt . [:pick $hs ($bytePos+1)] . [:pick $hs ($bytePos+0)])
        }
        :set numTxt [:pick $numTxt 0 $numLen]
        #:put ("numTxt [$numTxt] [" . [:typeof $numTxt] . "]")
        #:for digitPos from=0 to=([:len $numTxt] - 1) step=1 do={
        #    # Numbers 0-9 are 0x30-0x39 in ASCII, so "0" is 0x30 and "9" is 0x39
        #    :set numberText ($numberText . ("\\u003" . [:pick $numTxt $digitPos]))
        #}
        :set numberText $numTxt
    }
    :return {"numberText"=$numberText; "passChars"=($realNumLen + 4)}
}
#end of smsGetOA

#Remove sent messages
:foreach k,v in=$TGBOTMQ do={
    :if (([:pick $k 0 6] = "smstg#") and ($v->"Sent" = "yes")) do={
        :put ("Remove SMS #" . $TGBOTMQ->$k->"SmsIndex")
        /interface lte at-chat lte1 wait=yes input=("AT+CMGD=" . $TGBOTMQ->$k->"SmsIndex")
        :set ($TGBOTMQ->$k) 
    }
}

#get new messages
:local rawmsg ([/interface lte at-chat lte1 wait=yes input="AT+CMGL=4" as-value]->"output")
:local smsList [:toarray ""]
:local smsData
:local pos 0

:while ($pos < ([:len $rawmsg])) do={
	local newlinepos [:find $rawmsg "\n" ($pos - 1)]
	:local line
	:if ([:typeof $newlinepos] = "nil") do={
		:set newlinepos ([:len $rawmsg] )
	}
	
	:local line [:pick $rawmsg $pos ($newlinepos + 1)]
    # Trim \r \n
	:while (([:pick $line ([:len $line] - 1)] = "\r") or ([:pick $line ([:len $line] - 1)] = "\n")) do={
		:set line [:pick $line 0 ([:len $line] - 2)]
	}
	:set pos ($newlinepos + 1)
	:if ( [pick $line 0 2] != "OK" ) do={
		:if ([:pick $line 0] = "+") do={
			:local smsHeaderTemp [:toarray [:pick $line ([:find $line ":"] + 1) [:len $line]]]
			:set smsData { 
				"SmsIdx"=[:pick $smsHeaderTemp 0];
				"Status"=[:pick $smsHeaderTemp 1];
                "FwdOk"=0
#				"Length"=[:pick $smsHeaderTemp 2];
			}
		} else={
            :if ( [typeof [:find "0123456789ABCDEFabcdef" [:pick $line 0]]] != "nil" ) do={
                :local txtpos 0
                #$line = TP-SCA | TP-MTI & Co | TP-OA | TP-PID | TP-DCS | TP-SCTS | TP-UDL | TP-UD
                #:put "X"
                :local "pdu-tp-uhdi-exists" false
                :local "pdu-tp-dcs-value" -1
                :local "pdu-tp-mti-normal" false

                # *TP-SCA (Service Center address)
                ### Get length of record in bytes 
                :local "pdu-tp-sca-length" [$hexToNum hex=[:pick $line $txtpos ($txtpos +2)]]
                :set txtpos ($txtpos + 2)
                ### Skip to end of TP-SCA
                :set txtpos ($txtpos + ($"pdu-tp-sca-length" * 2))

                # *TP-MTI
                ### Get TP-MTI byte
                :local "pdu-tp-mti-data" [$hexToNum hex=[:pick $line $txtpos ($txtpos +2)]]
                :set txtpos ($txtpos + 2)
                ### Set if user data header exists
                :if ((($"pdu-tp-mti-data" >> 6) & 1) > 0) do={
                    :set "pdu-tp-uhdi-exists" true
                }
                :put ("pdu-tp-uhdi-exists " . $"pdu-tp-uhdi-exists")
                ### Set if SMS is SMS-DELIVER
                if (($"pdu-tp-mti-data" & 3) = 0) do={
                    :set "pdu-tp-mti-normal" true
                }
                :put ("pdu-tp-mti-normal " . $"pdu-tp-mti-normal")

                # *TP-OA (Originating Address)
                # We use special function for parsing this
                :set $sender [$smsGetOA hexstr=[:pick $line $txtpos ([:len $line])] sms7toJSONStr=$sms7toJSONStr]
                :set txtpos ($txtpos + ($sender->"passChars"))
                :set $sender ($sender->"numberText")
                

                # *TP-PID
                ### Ignore this byte
                :set txtpos ($txtpos + 2)

                # *TP-DCS (Data Coding Scheme)
                ###  One byte for data coding scheme
                :local "pdu-tp-dcs-value" [$hexToNum hex=[:pick $line $txtpos ($txtpos +2)]]
                :set txtpos ($txtpos + 2)
                :put ("pdu-tp-dcs-value " . $"pdu-tp-dcs-value")

                # *TP-SCTS (Service Center Time Stamp)
                ### Time when SC received message.
                ### 7 Bytes, will ignore them
                :set txtpos ($txtpos + 14)

                # *TP-UDL (User data length)
                ### Depends on message encoding (See TP-DCS)
                ### Message contains length for TP-UDH + TP-UD
                ### If message is encoded using 7-bit encoding, this shows number of 7-BIT characters.
                ###   In this case, there should be 9 bytes for 10-character message,
                ###   because of 10 7-bit characters take 70 bits, and 70 bits take 9 (ceil(70 / 8) = ceil(8.75) = 9) bytes
                ### If message is encoded using UCS-2, this shows number of BYTES
                :local udLenBytes [$hexToNum hex=[:pick $line $txtpos ($txtpos + 2)]]
                :set txtpos ($txtpos + 2)
                ### If encoding is 7-bit. we need to recalculate $udLenBytes value
                :if (($"pdu-tp-dcs-value" & 8) = 0) do={
                    :local udLenBits ($udLenBytes * 7)
                    :set udLenBytes ($udLenBits / 8)
                    :if (($udLenBits % 8) > 0) do={
                        :set udLenBytes ($udLenBytes + 1)
                    }
                }

                # *TP-UDH (User data header)
                ### If TP-MTI:bit6 is 1, this field exists
                :if ($"pdu-tp-uhdi-exists") do={
                    #NOT IMPLEMENTED!
                    :local udhLen 0
                }
                
                # *TP-UD (User data)
                ### The rest of the message is text
                :local msg [:pick $line $txtpos ($txtpos + ($udLenBytes * 2))]
                ### If encoding is 0 (TP-DCS, bits 1 and 2) then we should convert from 7 bit to 8 bit
                :if (($"pdu-tp-dcs-value" & 8) = 0) do={
                    :put "Converting using sms7toJSONStr"
                    :set msg [$sms7toJSONStr hexstr=$msg]
                } else {
                    if (([:len $msg] % 4) = 0) do={
                        :put "Converting using UTF16BE to JSONStr"
                        :local msg2 $msg
                        :set msg ""
                        for i from=0 to=([:len $msg2] - 1) step=4 do={
                            set msg ($msg . "\\u" . [:pick $msg2 $i ($i+4)])
                        }
                    } else={
                        :put "WARNING! MSG not conforms anything"
                    }
                }

                :set smsData ($smsData, {"Sender"=$sender})
                :set smsData ($smsData, {"Message"=$msg})

                :local smsIdx ($smsData->"SmsIdx")
                :set ($smsList->$smsIdx) $smsData
                :set smsData 
            }
		}
	}
	
}



:foreach k,v in=$smsList do={
    :local smsKey ("smstg#" . $k)
    #:put "smsKey $smsKey"

    :if ([:typeof ($TGBOTMQ->$smsKey)] = "nothing") do={
        :put "Enqueue sms with key $smsKey"
        :local message {"Message"=("SMS from `" . $v->"Sender" . "` :\\n```\\n" . $v->"Message" . "\\n```\\n"); "Sent"="no"; "SmsIndex"=$v->"SmsIdx"}
	    :set ($TGBOTMQ->$smsKey) $message
    } 
}
