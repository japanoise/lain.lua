#!/usr/bin/env lua

--
-- Lainbot ported to lua for use on darenet.
-- Based on SubBot.
-- Licensed GPLv2.
--

require("lib/base")

-- global vars
local buffers = {}
local comfort = {}
local waifus = {}
local DEBUG_CHANNEL = "#t"
local FILE_CHANNEL_LIST = "data/lainbot_channels"
local FILE_WAIFUS = "data/lainbot_waifus"
local FILE_COMFORT = "data/comfort.txt"
local MAX_CHANNEL_BUFFER_SIZE = 50
local ACCEPTED_SEPERATORS = ",./;[]\`~!@#$%^&*()_+-=|{}:<>?"

-- handle all messages not registered as public commands
function FakeClient:onPublicMessage(user, channel, words)
  -- return immediatly if we have no buffer for this channel to work with
  if not buffers[channel] then
    return
  end

  -- dont let the buffers table grow too big
  while #buffers[channel] > MAX_CHANNEL_BUFFER_SIZE do
    table.remove(buffers[channel], 1)
  end

  if string.sub(words[1], 1, 1) == "s" then
    local seperator = string.sub(words[1], 2, 2)
    local parts     = table.concat(words, " "):split(seperator)
    local index     = 0

    -- make sure this seperator is accepted
    if string.find(ACCEPTED_SEPERATORS, seperator) == nil then
      appendToBuffer(channel, user["nick"], table.concat(words, " "))
      return
    end

    -- make sure we have enough parts
    if #parts < 3 or #parts > 4 then
      appendToBuffer(channel, user["nick"], table.concat(words, " "))
      return
    end

    -- check for any line containing a match in the buffer
    for i = #buffers[channel], 1, -1 do
      if string.find(buffers[channel][i]["message"], parts[2]) ~= nil then
        index = i
        break
      end
    end

    -- if there's no matches, return early
    if index == 0 then
      return
    end

    -- replace as necessary
    local replaced  = string.gsub(buffers[channel][index]["message"], parts[2], parts[3])

    -- send the new line
    self:msg(channel, "<%s> %s", buffers[channel][index]["nick"], replaced)

    -- append the updated message
    appendToBuffer(channel, buffers[channel][index]["nick"], replaced)

    return
  end

  -- add the line to the buffer
  appendToBuffer(channel, user["nick"], table.concat(words, " "))
end

function appendToBuffer(channel, nick, message)
  table.insert(buffers[channel], {
    nick = nick,
    message = message
  })
end

-- bot startup
function onload()
  -- initialize bot
  client = FakeClient:new{
    nick         = "lainbot",
    host         = "lainbot.service.darenet",
    debugChannel = "#t"
  }
  -- lain: slurp the comfort file
  for line in io.lines(FILE_COMFORT) do
    table.insert(comfort, line)
  end

  -- set CTCP replies
  client.ctcpReplies.version = "lain.lua v0.0.1"

  -- join initial channels
  client:debug("Attempting to read from " .. FILE_CHANNEL_LIST)

  file = io.open(FILE_CHANNEL_LIST, "r")
  if file ~= nil then
    for line in io.lines(FILE_CHANNEL_LIST) do
      client:debug("Loading channel " .. line)
      -- initialize a buffer table for the channel
      buffers[line] = {}

      -- join the channel
      client:join{line}
    end

    io.close(file)
  end

  -- lain: read serialized waifus
  client:debug("Attempting to read from " .. FILE_WAIFUS)

  file = io.open(FILE_WAIFUS, "r")
  if file ~= nil then
    for line in io.lines(FILE_WAIFUS) do
      client:debug("Loading waifu - line: " .. line)
      split = mysplit (line, "$")
      client:debug("I think "..split[1].."'s waifu is "..split[0])
      waifus[split[1]] = split[0]
    end

    io.close(file)
  end

  -- register private commands
  client:registerPrivateCommand("dump", function(self, user, channel, message)
    if not irc.isOper(user["nick"]) then
      self:reply("You must have transcended to the gods to make me dump")
      return
    end

    if #message < 2 then
      self:reply("You must provide a channel")
      return
    end

    self:reply("Dumping buffers[%s] in %s:", message[2], DEBUG_CHANNEL)

    for i, message in pairs(buffers[message[2]]) do
      self:msg(DEBUG_CHANNEL, "buffers[%s][%02d] %s", message[2], i, message)
    end
  end)

  client:registerPrivateCommand("join", function(self, user, channel, message)
    if #message < 2 then
      self:reply("You must provide a channel")
      return
    end

    if not irc.isOp(user["nick"], message[2]) and not irc.isOper(user["nick"]) then
      self:reply("You must have +o in %s to invite me", message[2])
      return
    end

    client:debug("Joining " .. message[2] .. " on " .. user["nick"] .. "'s request")

    -- prepare your buffers
    buffers[message[2]] = {}

    -- join the requested channel
    client:join{message[2]}
  end)

  client:registerPrivateCommand("part", function(self, user, channel, message)
    if #message < 2 then
      self:reply("You must provide a channel")
      return
    end

    if not irc.isOp(user["nick"], message[2]) and not irc.isOper(user["nick"]) then
      self:reply("You must have +o in %s to part me", message[2])
      return
    end

    client:debug("Leaving " .. message[2] .. " on " .. user["nick"]. .. "'s request'")

    -- clear channel buffer
    buffers[message[2]] = nil

    -- leave channel
    client:part{message[2]}
  end)

  -- register public commands
  client:registerPublicCommand(".bots", function(self, user, channel, message)
    self:reply("%s reporting in! [%s] %s", "lain.lua", "lua", "https://github.com/japanoise/lain.lua")
  end)

  -- Begin lainbot commands
  client:registerPublicCommand("#waifureg", function(self, user, channel, message)
    if #message < 2 then
      self:reply("Your waifu needs a name, %s", user)
      return
    end
    waifus[user] = string.gsub(message[2],"$","")
  end)

  client:registerPublicCommand("#comfort", function(self, user, channel, message)
    if waifus[user] == nil then
      self:reply("You should register your waifu first, %s", user)
      return
    end
    self:reply("%s", string.gsub(string.gsub(comfort[math.random(#comfort)],"$waifu",waifus[user]),"$nick",user))
  end)
end

-- bot shutdown
function onunload()
  file = io.open(FILE_CHANNEL_LIST, "w")

  if file ~= nil then
    io.output(file)

    for channel, x in pairs(client["channels"]) do
      client:debug("Saving channel " .. channel)
      io.write(channel .. "\n")
    end

    io.close(file)
  end
  -- Lain waifus; entirely ripped off from the other ;)
  file = io.open(FILE_WAIFUS, "w")

  if file ~= nil then
    io.output(file)

    for user, waifu in pairs(waifus) do
      client:debug("Saving " .. user .. "'s waifu " .. waifu)
      io.write(waifu .. "$" .. user .. "\n")
    end

    io.close(file)
  end
end

-- stolen from stackoverflow because I'm lazy
function mysplit(inputstr, sep)
        if sep == nil then
                sep = "%s"
        end
        local t={} ; i=0
        for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
                t[i] = str
                i = i + 1
        end
        return t
end
