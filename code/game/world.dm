/var/server_name = "Foundation 19"
/var/game_id = null

GLOBAL_VAR(href_logfile)

// Find mobs matching a given string
//
// search_string: the string to search for, in params format; for example, "some_key;mob_name"
// restrict_type: A mob type to restrict the search to, or null to not restrict
//
// Partial matches will be found, but exact matches will be preferred by the search
//
// Returns: A possibly-empty list of the strongest matches
/proc/text_find_mobs(search_string, restrict_type = null)
	var/list/search = params2list(search_string)
	var/list/ckeysearch = list()
	for(var/text in search)
		ckeysearch += ckey(text)

	var/list/match = list()

	for(var/mob/M in SSmobs.mob_list)
		if(restrict_type && !istype(M, restrict_type))
			continue
		var/strings = list(M.name, M.ckey)
		if(M.mind)
			strings += M.mind.assigned_role
			strings += M.mind.special_role
		if(ishuman(M))
			var/mob/living/carbon/human/H = M
			if(H.species)
				strings += H.species.name
		for(var/text in strings)
			if(ckey(text) in ckeysearch)
				match[M] += 10 // an exact match is far better than a partial one
			else
				for(var/searchstr in search)
					if(findtext(text, searchstr))
						match[M] += 1

	var/maxstrength = 0
	for(var/mob/M in match)
		maxstrength = max(match[M], maxstrength)
	for(var/mob/M in match)
		if(match[M] < maxstrength)
			match -= M

	return match

#define RECOMMENDED_VERSION 512
/world/New()
	//set window title
	name = "[server_name] - [GLOB.using_map.full_name]"

	if(isnull(game_id))
		game_id = ""

		var/list/c = list("a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0")
		var/l = c.len

		var/t = world.timeofday
		for(var/_ = 1 to 4)
			game_id = "[c[(t % l) + 1]][game_id]"
			t = round(t / l)
		game_id = "-[game_id]"
		t = round(world.realtime / (10 * 60 * 60 * 24))
		for(var/_ = 1 to 3)
			game_id = "[c[(t % l) + 1]][game_id]"
			t = round(t / l)

	make_datum_references_lists() //initialises global lists for referencing frequently used datums (so that we only ever do it once)

	//logs
	SetupLogs()
	var/date_string = time2text(world.realtime, "YYYY/MM/DD")
	diary = file("data/logs/[date_string].log")
	to_file(diary, "[log_end]\n[log_end]\nStarting up. (ID: [game_id]) [time2text(world.timeofday, "hh:mm.ss")][log_end]\n---------------------[log_end]")

	if(config && config.log_runtime)
		var/runtime_log = file("data/logs/runtime/[date_string]_[time2text(world.timeofday, "hh:mm")]_[game_id].log")
		to_file(runtime_log, "Game [game_id] starting up at [time2text(world.timeofday, "hh:mm.ss")]")
		log = runtime_log // Note that, as you can see, this is misnamed: this simply moves world.log into the runtime log file.

	if(config && config.log_hrefs)
		GLOB.href_logfile = file("data/logs/[date_string] hrefs.htm")

	if(config?.log_assets)
		GLOB.world_asset_log = file("[GLOB.log_directory]/asset.log")

	if(byond_version < RECOMMENDED_VERSION)
		to_world_log("Your server's byond version does not meet the recommended requirements for this server. Please update BYOND")

	LoadVerbs(/datum/verbs/menu)

	GLOB.timezoneOffset = text2num(time2text(0,"hh")) * 36000

	var/latest_changelog = file("html/changelogs/archive/" + time2text(world.timeofday, "YYYY-MM") + ".yml")
	GLOB.changelog_hash = fexists(latest_changelog) ? md5(latest_changelog) : 0 //for telling if the changelog has changed recently

	// Database masterinit
	SSdbcore.CheckSchemaVersion()
	SSdbcore.SetRoundID()

	callHook("startup")

	//TGS
	TgsNew(new /datum/tgs_event_handler/impl, TGS_SECURITY_TRUSTED)
	TgsInitializationComplete();

	//Emergency Fix
	load_mods()
	//end-emergency fix

	// Load the list of trusted players
	load_trusted_players()

	. = ..()

#ifdef UNIT_TEST
	log_unit_test("Unit Tests Enabled. This will destroy the world when testing is complete.")
	load_unit_test_changes()
#endif
	Master.Initialize(10, FALSE)


#undef RECOMMENDED_VERSION

GLOBAL_LIST_EMPTY(world_topic_throttle)
GLOBAL_VAR_INIT(world_topic_last, world.timeofday)
#define SET_THROTTLE(TIME, REASON) throttle[1] = base_throttle + (TIME); throttle[2] = (REASON);
#define THROTTLE_MAX_BURST 15 SECONDS

/world/Topic(T, addr, master, key)
	TGS_TOPIC

	to_file(diary, "TOPIC: \"[T]\", from:[addr], master:[master], key:[key][log_end]")

	if (GLOB.world_topic_last > world.timeofday)
		GLOB.world_topic_throttle = list() //probably passed midnight
	GLOB.world_topic_last = world.timeofday

	var/list/throttle = GLOB.world_topic_throttle[addr]
	if (!throttle)
		GLOB.world_topic_throttle[addr] = throttle = list(0, null)
	else if (throttle[1] && throttle[1] > world.timeofday + THROTTLE_MAX_BURST)
		return throttle[2] ? "Throttled ([throttle[2]])" : "Throttled"

	var/base_throttle = max(throttle[1], world.timeofday)
	SET_THROTTLE(3 SECONDS, null)

	/* * * * * * * *
	* Public Topic Calls
	* The following topic calls are available without a comms secret.
	* * * * * * * */

	if (T == "ping")
		var/x = 1
		for (var/client/C)
			x++
		return x

	else if(T == "players")
		var/n = 0
		for(var/mob/M in GLOB.player_list)
			if(M.client)
				n++
		return n

	else if (copytext(T,1,7) == "status")
		var/input[] = params2list(T)
		var/list/s = list()
		s["version"] = config.game_version
		s["mode"] = PUBLIC_GAME_MODE
		s["respawn"] = config.abandon_allowed
		s["enter"] = config.enter_allowed
		s["vote"] = config.allow_vote_mode
		s["ai"] = !!length(empty_playable_ai_cores)
		s["host"] = host ? host : null

		// This is dumb, but spacestation13.com's banners break if player count isn't the 8th field of the reply, so... this has to go here.
		s["players"] = 0
		s["stationtime"] = station_time_timestamp("hh:mm")
		s["roundduration"] = DisplayTimeText(world.time - SSticker.round_start_time)
		s["map"] = replacetext(GLOB.using_map.full_name, "\improper", "") //Done to remove the non-UTF-8 text macros

		var/active = 0
		var/list/players = list()
		var/list/admins = list()
		var/legacy = input["status"] != "2"
		for(var/client/C in GLOB.clients)
			if(C.holder)
				if(C.is_stealthed())
					continue	//so stealthmins aren't revealed by the hub
				admins[C.key] = C.holder.rank
			if(legacy)
				s["player[players.len]"] = C.key
			players += C.key
			if(istype(C.mob, /mob/living))
				active++

		s["players"] = players.len
		s["admins"] = admins.len
		if(!legacy)
			s["playerlist"] = list2params(players)
			s["adminlist"] = list2params(admins)
			s["active_players"] = active

		return list2params(s)

	else if(T == "manifest")
		var/list/positions = list()
		var/list/nano_crew_manifest = nano_crew_manifest()
		// We rebuild the list in the format external tools expect
		for(var/dept in nano_crew_manifest)
			var/list/dept_list = nano_crew_manifest[dept]
			if(dept_list.len > 0)
				positions[dept] = list()
				for(var/list/person in dept_list)
					positions[dept][person["name"]] = person["rank"]

		for(var/k in positions)
			positions[k] = list2params(positions[k]) // converts positions["heads"] = list("Bob"="Captain", "Bill"="CMO") into positions["heads"] = "Bob=Captain&Bill=CMO"

		return list2params(positions)

	else if(T == "revision")
		var/list/L = list()
		L["gameid"] = game_id
		L["dm_version"] = DM_VERSION // DreamMaker version compiled in
		L["dm_build"] = DM_BUILD // DreamMaker build compiled in
		L["dd_version"] = world.byond_version // DreamDaemon version running on
		L["dd_build"] = world.byond_build // DreamDaemon build running on

		if(revdata.revision)
			L["revision"] = revdata.revision
			L["branch"] = revdata.branch
			L["date"] = revdata.date
		else
			L["revision"] = "unknown"

		return list2params(L)

	/* * * * * * * *
	* Admin Topic Calls
	* The following topic calls are only available if a ban comms secret has been defined, supplied, and is correct.
	* * * * * * * */

	if(copytext(T,1,14) == "placepermaban")
		var/input[] = params2list(T)
		if(!config.ban_comms_password)
			SET_THROTTLE(10 SECONDS, "Bans Not Enabled")
			return "Not Enabled"
		if(input["bankey"] != config.ban_comms_password)
			SET_THROTTLE(30 SECONDS, "Bad Bans Key")
			return "Bad Key"

		var/target = ckey(input["target"])

		var/client/C
		for(var/client/K in GLOB.clients)
			if(K.ckey == target)
				C = K
				break
		if(!C)
			return "No client with that name found on server"
		if(!C.mob)
			return "Client missing mob"

		if(!_DB_ban_record(input["id"], "0", "127.0.0.1", 1, C.mob, -1, input["reason"]))
			return "Save failed"
		ban_unban_log_save("[input["id"]] has permabanned [C.ckey]. - Reason: [input["reason"]] - This is a ban until appeal.")
		notes_add(target,"[input["id"]] has permabanned [C.ckey]. - Reason: [input["reason"]] - This is a ban until appeal.",input["id"])
		qdel(C)

	/* * * * * * * *
	* Secure Topic Calls
	* The following topic calls are only available if a comms secret has been defined, supplied, and is correct.
	* * * * * * * */

	if (!config.comms_password)
		SET_THROTTLE(10 SECONDS, "Comms Not Enabled")
		return "Not enabled"

	else if(copytext(T,1,5) == "laws")
		var/input[] = params2list(T)
		if(input["key"] != config.comms_password)
			SET_THROTTLE(30 SECONDS, "Bad Comms Key")
			return "Bad Key"

		var/list/match = text_find_mobs(input["laws"], /mob/living/silicon)

		if(!match.len)
			return "No matches"
		else if(match.len == 1)
			var/mob/living/silicon/S = match[1]
			var/info = list()
			info["name"] = S.name
			info["key"] = S.key

			if(istype(S, /mob/living/silicon/robot))
				var/mob/living/silicon/robot/R = S
				info["master"] = R.connected_ai?.name
				info["sync"] = R.lawupdate

			if(!S.laws)
				info["laws"] = null
				return list2params(info)

			var/list/lawset_parts = list(
				"ion" = S.laws.ion_laws,
				"inherent" = S.laws.inherent_laws,
				"supplied" = S.laws.supplied_laws
			)

			for(var/law_type in lawset_parts)
				var/laws = list()
				for(var/datum/ai_law/L in lawset_parts[law_type])
					laws += L.law
				info[law_type] = list2params(laws)

			info["zero"] = S.laws.zeroth_law ? S.laws.zeroth_law.law : null

			return list2params(info)

		else
			var/list/ret = list()
			for(var/mob/M in match)
				ret[M.key] = M.name
			return list2params(ret)

	else if(copytext(T,1,5) == "info")
		var/input[] = params2list(T)
		if(input["key"] != config.comms_password)
			SET_THROTTLE(30 SECONDS, "Bad Comms Key")
			return "Bad Key"

		var/list/match = text_find_mobs(input["info"])

		if(!match.len)
			return "No matches"
		else if(match.len == 1)
			var/mob/M = match[1]
			var/info = list()
			info["key"] = M.key
			info["name"] = M.name == M.real_name ? M.name : "[M.name] ([M.real_name])"
			info["role"] = M.mind ? (M.mind.assigned_role ? M.mind.assigned_role : "No role") : "No mind"
			var/turf/MT = get_turf(M)
			info["loc"] = M.loc ? "[M.loc]" : "null"
			info["turf"] = MT ? "[MT] @ [MT.x], [MT.y], [MT.z]" : "null"
			info["area"] = MT ? "[MT.loc]" : "null"
			info["antag"] = M.mind ? (M.mind.special_role ? M.mind.special_role : "Not antag") : "No mind"
			info["hasbeenrev"] = M.mind ? M.mind.has_been_rev : "No mind"
			info["stat"] = M.stat
			info["type"] = M.type
			if(isliving(M))
				var/mob/living/L = M
				info["damage"] = list2params(list(
							oxy = L.getOxyLoss(),
							tox = L.getToxLoss(),
							fire = L.getFireLoss(),
							brute = L.getBruteLoss(),
							clone = L.getCloneLoss(),
							brain = L.getBrainLoss()
						))
				if(ishuman(M))
					var/mob/living/carbon/human/H = M
					info["species"] = H.species.name
				else
					info["species"] = "non-human"
			else
				info["damage"] = "non-living"
				info["species"] = "non-human"
			info["gender"] = M.gender
			return list2params(info)
		else
			var/list/ret = list()
			for(var/mob/M in match)
				ret[M.key] = M.name
			return list2params(ret)

	else if(copytext(T,1,9) == "adminmsg")
		/*
			We got an adminmsg from IRC bot lets split the input then validate the input.
			expected output:
				1. adminmsg = ckey of person the message is to
				2. msg = contents of message, parems2list requires
				3. validatationkey = the key the bot has, it should match the gameservers commspassword in it's configuration.
				4. sender = the ircnick that send the message.
		*/


		var/input[] = params2list(T)
		if(input["key"] != config.comms_password)
			SET_THROTTLE(30 SECONDS, "Bad Comms Key")
			return "Bad Key"

		var/client/C
		var/req_ckey = ckey(input["adminmsg"])

		for(var/client/K in GLOB.clients)
			if(K.ckey == req_ckey)
				C = K
				break
		if(!C)
			return "No client with that name on server"

		var/rank = input["rank"]
		if(!rank)
			rank = "Admin"
		if(rank == "Unknown")
			rank = "Staff"

		var/message =	"<font color='red'>[rank] PM from <b><a href='?irc_msg=[input["sender"]]'>[input["sender"]]</a></b>: [input["msg"]]</font>"
		var/amessage =  "<font color='blue'>[rank] PM from <a href='?irc_msg=[input["sender"]]'>[input["sender"]]</a> to <b>[key_name(C)]</b> : [input["msg"]]</font>"

		C.received_irc_pm = world.time
		C.irc_admin = input["sender"]

		sound_to(C, 'sound/effects/adminhelp.ogg')
		to_chat(C, message)

		for(var/client/A in GLOB.admins)
			if(A != C)
				to_chat(A, amessage)
		return "Message Successful"

	else if(copytext(T,1,6) == "notes")
		/*
			We got a request for notes from the IRC Bot
			expected output:
				1. notes = ckey of person the notes lookup is for
				2. validationkey = the key the bot has, it should match the gameservers commspassword in it's configuration.
		*/
		var/input[] = params2list(T)
		if(input["key"] != config.comms_password)
			SET_THROTTLE(30 SECONDS, "Bad Comms Key")
			return "Bad Key"
		return show_player_info_irc(ckey(input["notes"]))

	else if(copytext(T,1,4) == "age")
		var/input[] = params2list(T)
		if(input["key"] != config.comms_password)
			SET_THROTTLE(30 SECONDS, "Bad Comms Key")
			return "Bad Key"
		var/age = get_player_age(input["age"])
		if(isnum(age))
			if(age >= 0)
				return "[age]"
			else
				return "Ckey not found"
		else
			return "Database connection failed or not set up"

	else if(copytext(T,1,19) == "prometheus_metrics")
		var/input[] = params2list(T)
		if(input["key"] != config.comms_password)
			SET_THROTTLE(30 SECONDS, "Bad Comms Key")
			return "Bad Key"
		if(!GLOB || !GLOB.prometheus_metrics)
			return "Metrics not ready"
		return GLOB.prometheus_metrics.collect()

#undef SET_THROTTLE

/world/Reboot(reason)
	/*spawn(0)
		sound_to(world, sound(pick('sound/AI/newroundsexy.ogg','sound/misc/apcdestroyed.ogg','sound/misc/bangindonk.ogg')))// random end sounds!! - LastyBatsy

		*/
	TgsReboot()

	Master.Shutdown()

	if(config.server)	//if you set a server location in config.txt, it sends you there instead of trying to reconnect to the same world address. -- NeoFite
		for(var/client/C in GLOB.clients)
			C?.tgui_panel?.send_roundrestart()
			send_link(C, "byond://[config.server]")

	if(config.wait_for_sigusr1_reboot && reason != 3)
		text2file("foo", "reboot_called")
		to_world("<span class=danger>World reboot waiting for external scripts. Please be patient.</span>")
		return

	..(reason)

/world/Del()
	var/debug_server = world.GetConfig("env", "AUXTOOLS_DEBUG_DLL")
	if (debug_server)
		call(debug_server, "auxtools_shutdown")()
	callHook("shutdown")
	return ..()

/hook/startup/proc/loadMode()
	world.load_mode()
	return 1

/world/proc/load_mode()
	if(!fexists("data/mode.txt"))
		return

	var/list/Lines = file2list("data/mode.txt")
	if(Lines.len)
		if(Lines[1])
			SSticker.master_mode = Lines[1]
			log_misc("Saved mode is '[SSticker.master_mode]'")

/world/proc/save_mode(var/the_mode)
	var/F = file("data/mode.txt")
	fdel(F)
	to_file(F, the_mode)

/hook/startup/proc/loadMods()
	world.load_mods()
	return 1

/world/proc/load_mods()
	if(config.admin_legacy_system)
		var/text = file2text("config/moderators.txt")
		if (!text)
			error("Failed to load config/mods.txt")
		else
			var/list/lines = splittext(text, "\n")
			for(var/line in lines)
				if (!line)
					continue

				if (copytext(line, 1, 2) == ";")
					continue

				var/title = "Moderator"
				var/rights = admin_ranks[title]

				var/ckey = copytext(line, 1, length(line)+1)
				var/datum/admins/D = new /datum/admins(title, rights, ckey)
				D.associate(GLOB.ckey_directory[ckey])

/world/proc/update_status()
	var/s = ""

	if (config && config.server_name)
		s += "<b>[config.server_name]</b>"

	if (config && config.server_suffix)
		s += " &#8212; <b>[config.server_suffix]</b>"

	if(config && config.server_desc)
		s += "<br>"
		s += config.server_desc

	s += "<br>"
	if(SSticker.master_mode)
		s += "Gamemode: [SSticker.master_mode]"
	else
		s += "<b>ROUND STARTING</b>"

	if (!config.enter_allowed)
		s += "<br>"
		s += "Server closed"

	s += "<br>"
	s += config.abandon_allowed ? "Respawn allowed" : "No respawn"

	if (config && config.hostedby)
		s += "<br>"
		s += "Hosted by <b>[config.hostedby]</b>"

	// Forum link
	if(config && config.forumurl)
		s += "<br>"
		s += "<a href=\"[config.forumurl]\">"
		s += "Forums"
		s += "</a>"

	// Discord link
	if(config && config.discordurl)
		s += "<br>"
		s += "<a href=\"[config.discordurl]\">"
		s += "Discord"
		s += "</a>"

	// Discord link
	if(config && config.rulesurl)
		s += "<br>"
		s += "<a href=\"[config.rulesurl]\">"
		s += "Rules"
		s += "</a>"

	// Discord link
	if(config && config.loreurl)
		s += "<br>"
		s += "<a href=\"[config.loreurl]\">"
		s += "Lore"
		s += "</a>"
	/* does this help? I do not know */
	if (src.status != s)
		src.status = s

/world/proc/SetupLogs()
	GLOB.log_directory = "data/logs/[time2text(world.realtime, "YYYY/MM/DD")]/round-"
	if(game_id)
		GLOB.log_directory += "[game_id]"
	else
		GLOB.log_directory += "[replacetext(time_stamp(), ":", ".")]"

	GLOB.world_qdel_log = file("[GLOB.log_directory]/qdel.log")
	GLOB.query_debug_log = file("[GLOB.log_directory]/sql.log")
	GLOB.tgui_log = file("[GLOB.log_directory]/tgui.log")
	to_file(GLOB.world_qdel_log, "\n\nStarting up round ID [game_id]. [time_stamp()]\n---------------------")

#define FAILED_DB_CONNECTION_CUTOFF 5
var/failed_db_connections = 0
var/failed_old_db_connections = 0

/proc/setup_database_connection()

	if(failed_db_connections > FAILED_DB_CONNECTION_CUTOFF)	//If it failed to establish a connection more than 5 times in a row, don't bother attempting to conenct anymore.
		return 0

	if(!dbcon)
		dbcon = new()

	var/user = sqlfdbklogin
	var/pass = sqlfdbkpass
	var/db = sqlfdbkdb
	var/address = sqladdress
	var/port = sqlport

	dbcon.Connect("dbi:mysql:[db]:[address]:[port]","[user]","[pass]")
	. = dbcon.IsConnected()
	if ( . )
		failed_db_connections = 0	//If this connection succeeded, reset the failed connections counter.
	else
		failed_db_connections++		//If it failed, increase the failed connections counter.
		to_world_log(dbcon.ErrorMsg())
	return .

//This proc ensures that the connection to the feedback database (global variable dbcon) is established
/proc/establish_db_connection()
	if(failed_db_connections > FAILED_DB_CONNECTION_CUTOFF)
		return 0

	if(!dbcon || !dbcon.IsConnected())
		return setup_database_connection()
	else
		return 1

//These two procs are for the old database, while it's being phased out. See the tgstation.sql file in the SQL folder for more information.
/proc/setup_old_database_connection()

	if(failed_old_db_connections > FAILED_DB_CONNECTION_CUTOFF)	//If it failed to establish a connection more than 5 times in a row, don't bother attempting to conenct anymore.
		return 0

	if(!dbcon_old)
		dbcon_old = new()

	var/user = sqllogin
	var/pass = sqlpass
	var/db = sqldb
	var/address = sqladdress
	var/port = sqlport

	dbcon_old.Connect("dbi:mysql:[db]:[address]:[port]","[user]","[pass]")
	. = dbcon_old.IsConnected()
	if ( . )
		failed_old_db_connections = 0	//If this connection succeeded, reset the failed connections counter.
	else
		failed_old_db_connections++		//If it failed, increase the failed connections counter.
		to_world_log(dbcon.ErrorMsg())

	return .

//This proc ensures that the connection to the feedback database (global variable dbcon) is established
/proc/establish_old_db_connection()
	if(failed_old_db_connections > FAILED_DB_CONNECTION_CUTOFF)
		return 0

	if(!dbcon_old || !dbcon_old.IsConnected())
		return setup_old_database_connection()
	else
		return 1

#undef FAILED_DB_CONNECTION_CUTOFF
