namespace eval ::rss-synd { 
   variable rss 

   set rss(cricinfo)   { 
             "url"      "http://www.cricinfo.com/rss/livescores.xml" 
             "channels"   "#redditCricket" 
             "database"   "/home/cycloblastic/zCricketBot/cricinfo.db" 
             "output"   "[Cricket ScoreBoard] @@item!title@@" 
             "trigger"   "!score" 
             "update-interval"  5
             "announce-output" 1
            } 

   set default      { 
             "max-output"   10 
             "remove-empty"   0 
             "max-depth"   5 
             "eval-tcl"   0 
             "update"   1 
             "timeout"   60000 
             "channels"   "#redditCricket" 
             "trigger"   "!score @@feedid@@" 
             "output"   "\[@@channel!title@@] @@item!title@@"
#"output"   "\4[3@@channel!title@@4]5 @@item!title@@" 
             "useragent"   "Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.7.10) Gecko/20050716 Firefox/1.0.6" 
            } 
} 

proc ::rss-synd::init {args} { 
   variable rss 
   variable default 

   package require http 

   foreach feed [array names rss] { 
      array set tmp $default 
      array set tmp $rss($feed) 

      set required [list "max-depth" "update" "timeout" "channels" "output" "useragent" "url" "database"] 
      foreach {key value} [array get tmp] { 
         if {[set ptr [lsearch -exact $required $key]] >= 0} { 
            set required [lreplace $required $ptr $ptr] 
         } 
      } 

      regsub -nocase -all -- {@@feedid@@} $tmp(trigger) $feed tmp(trigger) 

      if {[llength $required] == 0} { 
         if {([file exists $tmp(database)]) && ([set mtime [file mtime $tmp(database)]] < [unixtime])} { 
            set tmp(updated) [file mtime $tmp(database)] 
         } else { 
            set tmp(updated) 0 
         } 

         set rss($feed) [array get tmp] 
      } else { 
         putlog "\002RSS Error\002: Unable to load feed \"$feed\", missing one or more required settings. \"[join $required ", "]\"" 
         unset rss($feed) 
      } 

      unset tmp 
   } 

   bind evnt -|- prerehash [namespace current]::deInit 
   bind time -|- {* * * * *} [namespace current]::getFeeds 
   bind pubm -|- {* *} [namespace current]::pubFeeds 

   putlog "\002RSS Syndication Script\002: Loaded." 
} 

proc ::rss-synd::deInit {args} { 
   catch {unbind evnt -|- prerehash [namespace current]::deInit} 
   catch {unbind time -|- {* * * * *} [namespace current]::getFeeds} 
   catch {unbind pubm -|- {* *} [namespace current]::pubFeeds} 

   namespace delete [namespace current] 
} 

proc ::rss-synd::getFeeds {args} { 
   variable rss 

   set i 0 
   foreach name [array names rss] { 
      if {$i == 3} { break } 

      array set feed $rss($name) 

      if {$feed(updated) <= [expr { [unixtime] - ($feed(update) * 60) }]} { 
         ::http::config -useragent $feed(useragent) 

         catch {::http::geturl "$feed(url)" -command "[namespace current]::processFeed {[array get feed] depth 0}" -timeout $feed(timeout)} 

         set feed(updated) [unixtime] 
         set rss($name) [array get feed] 
         incr i 
      } 

      unset feed 
   } 
} 

proc ::rss-synd::pubFeeds {nick user handle chan text} { 
   variable rss 

   foreach name [array names rss] { 
      array set feed $rss($name) 

      if {[string match -nocase $text $feed(trigger)]} { 
         if {[[namespace current]::channelCheck $feed(channels) $chan]} { 
            set feed(channels) $chan 

            set data "" 
            if {[catch {open $feed(database) "r"} fp] == 0} { 
               while {![eof $fp]} { 
                  gets $fp line 
                  append data $line 
               } 

               close $fp 

               [namespace current]::outputFeed [array get feed] $data 
            } else { putserv "PRIVMSG $chan :\002RSS Warning\002: [string totitle $fp]." } 
         } 
      } 
   } 
} 

proc ::rss-synd::processFeed {feedlist args} { 
   set token [lindex $args end] 
   array set feed $feedlist 

   upvar 0 $token state 

   if {![string match -nocase $state(status) "ok"]} { 
      putlog "\002RSS Error\002: $state(url) (State: $state(status))" 
      return 1 
   } 

   if {([::http::ncode $token] == 302) || ([::http::ncode $token] == 301)} { 
      set feed(depth) [expr {$feed(depth) + 1 }] 

      array set meta $state(meta) 

      if {$feed(depth) < $feed(max-depth)} { 
         catch {::http::geturl "$meta(Location)" -command "[namespace current]::processFeed {[array get feed]}" -timeout $feed(timeout)} 
      } else { 
         putlog "\002RSS Error\002: $state(url) (State: timeout, max refer limit reached)" 
      } 

      return 1 
   } elseif {[::http::ncode $token] != 200} { 
      putlog "\002RSS Error\002: $state(url) ($state(http))" 
      return 1 
   } 

   if {[set newsdata [[namespace current]::createList [::http::data $token]]] == ""} { 
      putlog "\002RSS Error\002: Unable to parse URL properly. \"$state(url)\"" 
      return 1 
   } 

   ::http::cleanup $token 

   set oldfeed "" 
   if {[catch {open $feed(database) "r"} fp] == 0} { 
      while {![eof $fp]} { 
         gets $fp line 
         append oldfeed $line 
      } 

      close $fp 
   } else { putlog "\002RSS Warning\002: [string totitle $fp]." } 

   # reconstruct the data list into a format thats standard and usable with cookies 
   # 
   # note: 
   #   this code is pretty nasty, the hack to make attributes work with bottom level 
   #   tags could probably be improved on. should probably clean this up for v0.3. 
   foreach {tag value} $newsdata { 
      # rss v0.9x & v2.0 'item' tags are within the 'channel' tag. we need to seperate them. 
      if {[string match -nocase $tag "rss"]} { 
         foreach {subtag subvalue} $value { 
            if {[string match -nocase $subtag "=channel"]} { 
               set tmp $subvalue 
            } elseif {[string match -nocase $subtag "channel"]} { 
               foreach {ssubtag ssubvalue} $subvalue { 
                  if {[string match -nocase $ssubtag "=item"]} { 
                     set ttmp [list $ssubtag $ssubvalue] 
                     continue 
                  } elseif {[string match -nocase $ssubtag "item"]} { 
                     if {![info exists ttmp]} { 
                        lappend news(item) [list "item" $ssubvalue] 
                     } else { 
                        lappend news(item) [list "item" $ssubvalue [lindex $ttmp 0] [lindex $ttmp 1]] 
                        unset ttmp 
                     } 
                  } else { 
                     lappend news(channel) $ssubtag $ssubvalue 
                  } 
               } 

               if {[info exists news(channel)]} { 
                  if {![info exists tmp]} { 
                     set news(channel) [list [list "channel" $news(channel)]] 
                  } else { 
                     set news(channel) [list [list "channel" $news(channel) "=channel" $tmp]] 
                     unset tmp 
                  } 
               } 
            } 
         } 

         break 

      # rss v1.0 'item' tags are outside of the 'channel' tag, just remove excess garbage. 
      } elseif {[string match -nocase $tag "rdf:RDF"]} { 
         foreach {subtag subvalue} $value { 
            if {[string match {=*} $subtag]} { 
               set tmp [list $subtag $subvalue] 
               continue 
            } 

            if {![info exists tmp]} { 
               lappend news($subtag) [list $subtag $subvalue] 
            } else { 
               lappend news($subtag) [list $subtag $subvalue [lindex $tmp 0] [lindex $tmp 1]] 
               unset tmp 
            } 
         } 

         break 
      } 
   } 

   if {[catch {open $feed(database) "w+"} fp] == 0} { 
      puts $fp [array get news] 
      close $fp 
   } else { 
      putlog "\002RSS Error\002: [string totitle $fp]." 
      return 1 
   } 

   [namespace current]::outputFeed [array get feed] [array get news] $oldfeed 

   return 0 
} 

proc ::rss-synd::createList {data} { 
   set i 0 
   set news [list] 
   set length [string length $data] 

   for {set ptr 1} {$ptr <= $length} {incr ptr} { 
      set section [string range $data $i $ptr] 

      # split up the tag data 
      if {[llength [set match [regexp -inline -- {<(.[^ \n\r>]+)(?: |\n|\r\n|\r|)(.[^>]+|)>} $section]]] > 0} { 
         set i [expr { $ptr + 1 } ] 

         set tag [lindex $match 1] 

         # check to see if the tag is being closed 
         if {([info exists current(tag)]) && ([string match -nocase $current(tag) [string map { "/" "" } $tag]])} { 
            set subdata [string range $data $current(pos) [expr { $ptr - ([string length $tag] + 2) } ]] 

            # remove all CDATA garbage 
            if {[set cdata [lindex [regexp -inline -nocase -- {^(?:\s*)<!\[CDATA\[(.[^\]>]*)\]\]>} $subdata] 1]] != ""} { 
               set subdata $cdata 
            } 

            # recurse the data within the currently open tag 
            set result [[namespace current]::createList $subdata] 

            # set the attribute data, this is set before the actual data to make reconstructing it later much easier. 
            if {[info exists current(tmp)]} { lappend news "=$current(tag)" $current(tmp) } 

            # set the list data returned from the recursion we just performed 
            if {[llength $result] > 0} { 
               lappend news $current(tag) $result 
            # set the current data we have because were already at the end of a branch 
            #   (ie: the recursion didnt return any data) 
            } else { 
               regsub -nocase -all -- "\\s{2,}" $subdata " " subdata 
               lappend news $current(tag) [string trim $subdata] 
            } 

            unset current 
         # check to see if the tag is being opened 
         } elseif {(![string match {[!\?]*} $tag]) && (![info exists current(tag)])} { 
            set tmp [list] 

            # get all of the tags attributes 
            if {[lindex $match 2] != ""} { 
               set values [regexp -inline -all -- {(?:\s*)(.[^=]+)="(.[^"]+)"} [lindex $match 2]] 

               foreach {regmatch regtag regval} $values { 
                  lappend tmp $regtag $regval 
               } 
            } 

            # append attributes for self closing tags 
            if {([regexp {/(\s*)$} [lindex $match 2]]) && ([llength $tmp] > 0)} { 
               lappend news "=$tag" $tmp 
            # set the current open tag and its attributes 
            } else { 
               set current(tag) [string map { "\r" "" "\n" "" "\t" "" } $tag] 
               if {[llength $tmp] > 0} { set current(tmp) $tmp } 
               set current(pos) $i 
            } 

            unset tmp 
         } 
      } 
   } 

   return $news 
} 

proc ::rss-synd::outputFeed {feedlist newslist {oldfeed ""}} { 
   array set feed $feedlist 
   array set news $newslist 

   if {$oldfeed != ""} { 
      array set ttmp $oldfeed 
      array set old [lindex $ttmp(item) 0] 
      unset ttmp 

      array set last $old(item) 
   } 

   set i 0 
   foreach itemlist $news(item) { 
      array set ttmp $itemlist 
      array set tmp $ttmp(item) 
      unset ttmp 

      if {([info exists feed(max-output)]) && ($i == $feed(max-output))} { break } 
      if {([info exists last(title)]) && ([string compare $last(title) $tmp(title)] == 0)} { break } 
      if {([info exists last(link)]) && ([string compare $last(link) $tmp(link)] == 0)} { break } 

      set msg [[namespace current]::formatOutput $feedlist "[lindex [set news(channel)] 0] [set itemlist]"] 

      foreach chan $feed(channels) { 
         if {[botonchan $chan]} { 
            putserv "PRIVMSG $chan :$msg" 
         } 
      } 

      incr i 
   } 
} 

proc ::rss-synd::formatOutput {feedlist item} { 
   array set feed $feedlist 
   set output $feed(output) 

   set eval 0 
   if {([info exists feed(eval-tcl)]) && ($feed(eval-tcl) == 1)} { set eval 1 } 

   set data [regexp -inline -nocase -all -- {@@(.*?)@@} $output] 

   foreach {match cookie} $data { 
      if {[set tmp [[namespace current]::replaceCookies [split $cookie "!"] $item]] != ""} { 
         regsub -nocase -- "@@$cookie@@" $output "[string map { "&" "\\\x26" } [[namespace current]::decodeHtml $eval $tmp]]" output 
      } 
   } 

   if {(![info exists feed(remove-empty)]) || ($feed(remove-empty) == 1)} { 
      regsub -nocase -all -- "@@.*?@@" $output "" output 
   } 

   if {$eval == 1} { 
      if {[catch {set output [subst $output]} error] != 0} { 
         putlog "\002RSS Error\002: $error" 
      } 
   } 

   return $output 
} 

proc ::rss-synd::replaceCookies {cookie data} { 
   foreach {key value} $data { 
      if {([llength $cookie] > 1) && ([string compare -nocase [lindex $cookie 0] $key] == 0)} { 
         return [[namespace current]::replaceCookies [lreplace $cookie 0 0] $value] 
      } elseif {([llength $cookie] == 1) && ([string compare -nocase $cookie $key] == 0)} { 
         return $value 
      } 
   } 
} 

proc ::rss-synd::decodeHtml {eval data} { 

   array set chars { 
          nbsp   \x20 amp   \x26 quot   \x22 lt      \x3C 
          gt   \x3E iexcl   \xA1 cent   \xA2 pound   \xA3 
          curren   \xA4 yen   \xA5 brvbar   \xA6 brkbar   \xA6 
          sect   \xA7 uml   \xA8 die   \xA8 copy   \xA9 
          ordf   \xAA laquo   \xAB not   \xAC shy   \xAD 
          reg   \xAE hibar   \xAF macr   \xAF deg   \xB0 
          plusmn   \xB1 sup2   \xB2 sup3   \xB3 acute   \xB4 
          micro   \xB5 para   \xB6 middot   \xB7 cedil   \xB8 
          sup1   \xB9 ordm   \xBA raquo   \xBB frac14   \xBC 
          frac12   \xBD frac34   \xBE iquest   \xBF Agrave   \xC0 
          Aacute   \xC1 Acirc   \xC2 Atilde   \xC3 Auml   \xC4 
          Aring   \xC5 AElig   \xC6 Ccedil   \xC7 Egrave   \xC8 
          Eacute   \xC9 Ecirc   \xCA Euml   \xCB Igrave   \xCC 
          Iacute   \xCD Icirc   \xCE Iuml   \xCF ETH   \xD0 
          Dstrok   \xD0 Ntilde   \xD1 Ograve   \xD2 Oacute   \xD3 
          Ocirc   \xD4 Otilde   \xD5 Ouml   \xD6 times   \xD7 
          Oslash   \xD8 Ugrave   \xD9 Uacute   \xDA Ucirc   \xDB 
          Uuml   \xDC Yacute   \xDD THORN   \xDE szlig   \xDF 
          agrave   \xE0 aacute   \xE1 acirc   \xE2 atilde   \xE3 
          auml   \xE4 aring   \xE5 aelig   \xE6 ccedil   \xE7 
          egrave   \xE8 eacute   \xE9 ecirc   \xEA euml   \xEB 
          igrave   \xEC iacute   \xED icirc   \xEE iuml   \xEF 
          eth   \xF0 ntilde   \xF1 ograve   \xF2 oacute   \xF3 
          ocirc   \xF4 otilde   \xF5 ouml   \xF6 divide   \xF7 
          oslash   \xF8 ugrave   \xF9 uacute   \xFA ucirc   \xFB 
          uuml   \xFC yacute   \xFD thorn   \xFE yuml   \xFF 
          ensp   \x20 emsp   \x20 thinsp   \x20 zwnj   \x20 
          zwj   \x20 lrm   \x20 rlm   \x20 euro   \x80 
          sbquo   \x82 bdquo   \x84 hellip   \x85 dagger   \x86 
          Dagger   \x87 circ   \x88 permil   \x89 Scaron   \x8A 
          lsaquo   \x8B OElig   \x8C oelig   \x8D lsquo   \x91 
          rsquo   \x92 ldquo   \x93 rdquo   \x94 ndash   \x96 
          mdash   \x97 tilde   \x98 scaron   \x9A rsaquo   \x9B 
          Yuml   \x9F apos   \x27 
         } 


   regsub -all -- {<(.[^>]*)>} $data "" data 

   if {$eval != 1} { 
      regsub -all -- {([\"\$\[\]\{\}\(\)\\])} $data {\\\1} data 
   } else { 
      regsub -all -- {([\"\$\[\]\{\}\(\)\\])} $data {\\\\\\\1} data 
   } 

   regsub -all -- {&#([0-9][0-9]?[0-9]?);?} $data {[format %c [scan \1 %d]]} data 
   regsub -all -- {&([0-9a-zA-Z#]*);} $data {[if {[catch {set tmp $chars(\1)} char] == 0} { set tmp }]} data 
   regsub -all -nocase -- {&([0-9a-zA-Z#]*);} $data {[if {[catch {set tmp [string tolower $chars(\1)]} char] == 0} { set tmp }]} data 

   return [subst $data] 
} 

proc ::rss-synd::channelCheck {chanlist chan} { 
   foreach match [split $chanlist] { 
      if {[string match -nocase $match $chan]} { return 1 } 
   } 

   return 0 
} 

::rss-synd::init

