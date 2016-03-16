import requests
import json
import time
import codecs
import re
import sopel.module
from sopel.tools import SopelMemory
from sopel.module import commands, example, interval, NOLIMIT, require_privmsg, require_admin
from sopel.config.types import (StaticSection, ListAttribute)

@sopel.module.commands('score')
@example('.score http://www.espncricinfo.com/icc-world-twenty20-2016/engine/match/951327.html')
def getscore(bot, trigger):
    # Score set to empty initially.
    score = ''
    # get arguments
    #arg = trigger.group(2)
    matches_response = requests.get("https://dev132-cricket-live-scores-v1.p.mashape.com/matches.php",
    headers={
       "X-Mashape-Key": "XXXXXXXXXXXXXXXXXXXXXXX",
       "Accept": "application/json"
        }
      )
    match_status = ['LIVE']
    match_name = ['Sheffield Shield 2015/2016'] 
    match_data = matches_response.json()
    match_list = match_data['matchList']['matches']
    match_short = ['SA']
    for match in match_list:
      if match['status'] in  match_status:
       if match['homeTeam']['shortName'] in match_short:
        summary =  match['matchSummaryText']
 
    bot.say(summary)

