#!/usr/bin/lua

--[[
 * Copyright (C) 2019 Red Hat, Inc.
 * Author: Bastien Nocera <hadess@hadess.net>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA.
 *
--]]

local inspect = require "lib.inspect"
require "lib.dirtree"

local os = require "os"
local posix = require "posix"

function bold(enable)
	if enable then
		for _,i in ipairs{ 0x1b,0x5b, 0x31, 0x6d } do io.write(string.char(i)) end
	else
		for _,i in ipairs{ 0x1b,0x5b, 0x30, 0x6d } do io.write(string.char(i)) end
	end
end

function usage()
	print('find-known-roms [ROM Path] [Database Path]')
	print('')
	print('[Rom Path] is the current directory if not passed')
	print('[Database Path] is $HOME/.local/share/find-known-roms/ if not passed')
end

function dir_exists(path)
        local stat = posix.stat(path)
        if not stat then
                return false
        end
        return stat.type == 'directory'
end

local function ends_with(str, ending)
	return ending == "" or str:sub(-#ending) == ending
end

function read_all(file)
        local f = io.open(file, "r")
        if not f then return nil end
        local t = f:read("*all")
        f:close()
        return t
end

function split_clr_tokens(s)
        local res = {}
        for w in s:gmatch("%w (.*)") do
                res[#res+1] = w
        end
        return res
end

local function parse_dat_game(game_str)
	local game = {}
	game.name = game_str:match('name.-"(.-)"')
	local sha1 = game_str:match('sha1 (%w+)') or error('Could not parse sha1 in ' .. game_str)
	game.sha1 = sha1:lower()

	return game
end

local function parse_dat(path)
	local dat = {}
	local contents = read_all(path)
	local dat_name = contents:match('clrmamepro.-%(.-name.-"(.-)".-%)') or error('Could not parse dat from "' .. path .. '"')
	for game_str in contents:gmatch('game %(.-sha1.-%).-%)') do
		local game = parse_dat_game(game_str)
		dat[game.sha1] = game
	end
	return dat, dat_name
end

function shell_quote(...)
        local command = type(...) == 'table' and ... or { ... }
        for i, s in ipairs(command) do
                s = (tostring(s) or ''):gsub("'", "'\\''")
                s = "'" .. s .. "'"
                command[i] = s
        end
        return table.concat(command, ' ')
end

-- This is 100 times faster than using a native SHA-1
local function sha1_file_ext(path)
	local command = { 'sha1sum', path }
        local f = io.popen(shell_quote(command), 'r') or error('Could not launch sha1sum')
        local s = f:read('*a')
        f:close()
        return s:match('(%w+) .+')
end

-- 1. Parse command-line
local db_path = nil
local rom_path = nil
local options = {}
for k, v in ipairs(arg) do
	if v == '-h' or v == '--help' then
		usage()
		return 1
	end
	if not rom_path then
		rom_path = v
	elseif not db_path then
		db_path = v
	else
		usage()
		return 1
	end
end
if not db_path then
	db_path = os.getenv("HOME") .. '/.local/share/find-known-roms/'
	if not dir_exists(db_path) then
		print ('db_path doesnt exist')
		usage()
		return 1
	end
end
if not rom_path then
	rom_path = '.'
end

-- 2. Load databases

print ('Loading databases from ' .. db_path)
local db = {}
for filename, attr in dirtree(db_path) do
	if attr.mode == 'file' and ends_with(filename, '.dat') then
		print ('Loading database "' .. filename .. '"')
		local dat, dat_name = parse_dat(filename)
		db[dat_name] = dat
	end
end

-- 3. For each file in the directory, and try to look it up
print ('Checking files in "' .. rom_path .. '" against databases')
for filename, attr in dirtree(rom_path) do
	if attr.mode == 'file' then
		-- SHA1 for the filename
		local sha1 = sha1_file_ext(filename):lower()
		-- print ('Looking for ' .. sha1 .. ' from "' .. filename .. '"')
		for _,dat in pairs(db) do
			if dat[sha1] ~= nil then
				local game = dat[sha1]
				local relative = filename:sub(#rom_path)
				if relative:sub(1, 1) == '/' then relative = relative:sub(2) end
				print ('Found "' .. game.name .. '" in "' .. relative .. '"')
				break
			end
		end
	else
		-- print ('Skipping ' .. attr.mode .. ' ' .. filename)
	end
end
