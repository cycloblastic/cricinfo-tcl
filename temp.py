import requests
import json
import time
import urllib.request
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
    arg = trigger.group(2)
    cricinfo_id = ['951327']
    if arg is not None:
     cricinfo_id = arg[-11:].split(".")[0]
     req = urllib.request.Request('http://cricscore-api.appspot.com/csa?id='+ str(cricinfo_id))   
     response = urllib.request.urlopen(req)
    # Get the score details `de` from the response json.
     reader = codecs.getreader("utf-8")
     data = json.load(reader(response))
     new_score = data[0]['de']
     if cricinfo_id != ['951327']:
      bot.say(new_score)
