/*
	Plugin: 'Escape: Reborn'

	Plugin author ('how to' ignored, only suggestions & bugreport): http://t.me/blacksignature

	Plugin thread: ...

	Description:
		This plugin brings back (and allows you to customize its rules) an old unsupported
		counter-strike game mode known as 'Escape', where TTs must reach escape zone
		(like a VIP on 'as_' maps), and CTs	must prevent TTs to	do that by eleminating them.

	Credits:
		* CHEL74 -> https://dev-cs.ru/members/3489/
			* Suggestions, plugin testing

	Requirements:
		* Counter-Strike 1.6
		* Amx Mod X 1.9 - build 5241, or higher
		* ReAPI

	How to use:
		1) Install this plugin
		2) Run it
		3) Visit 'configs/plugins' to tweak config
		4) Upload some 'es_' maps onto your server
		5) Change map to any of 'es_' maps
		6) Enjoy!

	Change history:
		0.1 (06.03.2019):
			* Initial private release
		0.2 (08.03.2019):
			Added:
				* Cvar 'es_zones_on_radar'
				* Cvar 'es_show_info_menu'
		0.3 (12.03.2019):
			Added:
				* State 'Use map rules' (-1) for cvar 'es_buy_mode'
				* Cvar 'es_tt_loser_bonus_limit'
				* Cvar 'es_instant_tt_win_by_ratio'
				* Cvar 'es_instant_tt_loose_by_ratio'
			Fixed:
				* Round reward calculation now works as intended
			Removed:
				* Cvar 'es_tt_loser_bonus'
			Changed:
				* Cvar 'es_announce_to_ct' renamed to 'es_announce_escape_to_ct'
				* Cvar 'es_slay_tt_on_timeout' get three states instead of 2
				* Cvar 'es_rounds_to_switch_teams' renamed to 'es_rounds_to_swap_teams'
		0.4 (13.03.2019):
			* Public release
*/

/* Things that can be useful with this plugin (future plans?):
	* 'Armory manager' to manage (create, modify, delete) items that lays on map

	* 'Escape zone editor' to manage (create, modify, delete) escape zones, with
		ability to disable other map objectives (to turn any map into a escape map)

	* 'Escape shop' (as addition or replacement to buying system) with custom items
		like low gravity, silent footsteps, regeneration, partial visibility, etc.

	* 'Equip presets' (as addition or replacement to buying system) to allow random
		equipment with predefined item packs
*/

/* TODO:
	* At this moment plugin doesn't support maps with multiple objectives (as example,
		with bomb and escape scenario at the same time)

	* Test team swapping with 20+ players (ideally 32)

	* Total / Win(per team) round counting with command (by cvar) execution when limit is reached
*/

new const PLUGIN_VERSION[] = "0.4"

/* -------------------- */

#define AUTO_CFG // Create config with plugin cvars in 'configs/plugins', and execute it?

#define MAX_ESCAPE_ZONES 10

/* -------------------- */

#include <amxmodx>
#include <engine>
#include <reapi>

#define chx charsmax
#define rg_get_user_team(%0) get_member(%0, m_iTeam)
#define rg_set_user_money rg_add_account
#define WEAPON_NAME_LEN 32
#define MAP_NAME_LEN 32

#if !defined MAX_MENU_LENGTH
	#define MAX_MENU_LENGTH 512
#endif

const MENU_KEYS = MENU_KEY_4|MENU_KEY_5

new const SOUND__TUTOR_MSG[] = "sound/events/tutor_msg.wav"

new const MENU_IDENT_STRING[] = "ES Menu"

enum _:XYZ { Float:X, Float:Y, Float:Z }
enum { _KEY1_, _KEY2_, _KEY3_, _KEY4_, _KEY5_, _KEY6_, _KEY7_, _KEY8_, _KEY9_, _KEY0_ }

enum ( += MAX_PLAYERS + 1 ) {
	TASKID__DISABLE_BUY = 100,
	TASKID__UPDATE_RADAR
}

enum { // states for cvar 'es_announce_escape_to_ct'
	SHOW_TO_CT__OFF,
	SHOW_TO_CT__ONLY_DEAD,
	SHOW_TO_CT__ALL
}

enum { // states for cvar 'es_buy_mode'
	BUY_MODE__DEFAULT = -1,
	BUY_MODE__NONE,
	BUY_MODE__TT,
	BUY_MODE__CT,
	BUY_MODE__ALL
}

enum _:RADAR_ZONES_STATUS_ENUM { // states for cvar 'es_zones_on_radar'
	RADAR_ZONES__OFF,
	RADAR_ZONES__TT,
	RADAR_ZONES__CT,
	RADAR_ZONES__ALL
}

enum { // states for cvar 'es_slay_tt_on_timeout'
	SLAY_TT__NO,
	SLAY_TT__ONLY_ON_LOOSE,
	SLAY_TT__EVEN_IF_WIN
}

enum _:PCVAR_ENUM {
	PCVAR__BUY_MODE,
	PCVAR__BUYTIME,
	PCVAR__ZONES_ON_RADAR
}

enum _:CVAR_ENUM {
	CVAR__ROUNDS_TO_SWAP_TEAMS,
	Float:CVAR_F__ESCAPE_RATIO, // replacement for 'm_flRequiredEscapeRatio'
	CVAR__INSTANT_TT_WIN_BY_RATIO,
	CVAR__INSTANT_TT_LOOSE_BY_RATIO,
	CVAR__DISAPPEAR_AFTER_ESCAPE,
	CVAR__FRAGS_FOR_ESCAPE,
	CVAR__MONEY_FOR_ESCAPE,
	CVAR__ZONES_ON_RADAR,
	CVAR__ANNOUNCE_ESCAPE_TO_CT,
	CVAR__ESCAPE_SOUND,
	CVAR__SLAY_TT_ON_TIMEOUT,
	CVAR__STRIP_CT,
	CVAR__REMOVE_MAP_ITEMS,
	CVAR__BUY_MODE,
	Float:CVAR_F__BUYTIME,
	CVAR__TT_LOSER_BONUS_LIMIT,
	CVAR__SHOW_INFO_MENU,
	CVAR__TT_PRIMARY_BPAMMO,
	CVAR__TT_SECONDARY_BPAMMO,
	CVAR__TT_ARMOR,
	CVAR__TT_HEGREN,
	CVAR__TT_FLASHBANG,
	CVAR__TT_SMOKE,
	CVAR__CT_PRIMARY_BPAMMO,
	CVAR__CT_SECONDARY_BPAMMO,
	CVAR__CT_ARMOR,
	CVAR__CT_HEGREN,
	CVAR__CT_FLASHBANG,
	CVAR__CT_SMOKE,
	Float:CVAR_F__ROUND_RESTART_DELAY
}

new g_pCvar[PCVAR_ENUM]
new g_eCvar[CVAR_ENUM]
new g_iNumEscapeRounds
new HookChain:g_hStartSound
new g_pBuyZoneEnt
new bool:g_bRoundEnded
new bool:g_bIsConnected[MAX_PLAYERS + 1]
new g_iNumEscapers // 'm_iNumEscapers' won't be increased when CT changes team to TT and somehow get respawn, so we use cache
new bool:g_bSpawnedAsTer[MAX_PLAYERS + 1] // to prevent increasing 'g_iNumEscapers' per terrorist more than 1 time in one round
new bool:g_bEscaped[MAX_PLAYERS + 1] // gamedll set 'm_bEscaped' to false after player death, so we use cache
new g_iHaveEscaped // gamedll decrease 'm_iHaveEscaped' after escaper death/disconnect, so we use cache
new g_msgScoreInfo
new g_szPrimary[_:TeamName][WEAPON_NAME_LEN]
new g_szSecondary[_:TeamName][WEAPON_NAME_LEN]
new TeamName:g_iLastTeam[MAX_PLAYERS + 1]
new Float:g_fZoneOrigin[MAX_ESCAPE_ZONES][XYZ]
new g_iZoneCount
new bool:g_bConfigsExecuted
new g_msgHostagePos
new g_msgHostageK
new bool:g_bGotHostagePos[MAX_PLAYERS + 1]
new g_eGotInfo[MAX_PLAYERS + 1][TeamName]

/* -------------------- */

public plugin_init() {
	register_plugin("[ER] Escape: Reborn", PLUGIN_VERSION, "mx?!")
	register_dictionary("escape_reborn.txt")

	func_RegCvars()

	/* --- */

	func_FindEscapeZones()

	if(!g_iZoneCount) { // not a 'es_' map
		pause("ad")
		return
	}

	/* --- */

	register_logevent("logevent_TerroristEscaped", 3, "1=triggered", "2=Terrorist_Escaped")

	register_message(get_user_msgid("TextMsg"), "msg_TextMsg")
	register_message(get_user_msgid("ClCorpse"), "msg_ClCorpse")

	g_msgScoreInfo = get_user_msgid("ScoreInfo")
	g_msgHostagePos = get_user_msgid("HostagePos")
	g_msgHostageK = get_user_msgid("HostageK")

	RegisterHookChain(RG_CSGameRules_RestartRound, "OnRestartRound_Pre")
	RegisterHookChain(RG_CSGameRules_RestartRound, "OnRestartRound_Post", true)
	RegisterHookChain(RG_CBasePlayer_Spawn, "OnPlayerSpawn_Post", true)
	DisableHookChain(g_hStartSound = RegisterHookChain(RH_SV_StartSound, "OnStartSound_Pre"))
	RegisterHookChain(RG_RoundEnd, "OnRoundEnd_Pre")
	RegisterHookChain(RG_CBasePlayer_Killed, "OnPlayerKilled_Post", true)
	RegisterHookChain(RG_CBasePlayer_OnSpawnEquip, "OnSpawnEquip_Pre")
	RegisterHookChain(RG_CSGameRules_OnRoundFreezeEnd, "OnRoundFreezeEnd_Post", true)

	// https://github.com/s1lentq/ReGameDLL_CS/blob/master/regamedll/dlls/multiplay_gamerules.cpp#L1173
	set_member_game(m_flRequiredEscapeRatio, 100.0) // to break standart round end calculation when terrorist reaches escape zone

	register_menucmd(register_menuid(MENU_IDENT_STRING), MENU_KEYS, "func_Menu_Handler")
}

/* -------------------- */

public plugin_cfg() { // to prevent conflict with plugins that mess with 'func_buyzone' in plugin_precache() or plugin_init()
	new const szBuyZoneClassName[] = "func_buyzone"
	new pEnt = MaxClients

	while((pEnt = rg_find_ent_by_class(pEnt, szBuyZoneClassName, .useHashTable = true))) {
		set_entvar(pEnt, var_flags, FL_KILLME)
	}

	g_pBuyZoneEnt = rg_create_entity(szBuyZoneClassName, .useHashTable = true)
	DispatchKeyValue(g_pBuyZoneEnt, "team", "0")
	DispatchSpawn(g_pBuyZoneEnt)
	entity_set_size(g_pBuyZoneEnt, Float:{-8191.0, -8191.0, -8191.0}, Float:{8191.0, 8191.0, 8191.0})
	set_entvar(g_pBuyZoneEnt, var_solid, SOLID_NOT)
}

/* -------------------- */

public OnConfigsExecuted() {
	if(g_eCvar[CVAR__REMOVE_MAP_ITEMS]) {
		new pEnt = MaxClients

		while((pEnt = rg_find_ent_by_class(pEnt, "armoury_entity", .useHashTable = true))) {
			set_entvar(pEnt, var_flags, FL_KILLME)
		}
	}

	/* --- */

	g_bConfigsExecuted = true
	func_UpdateRadarStatus(g_eCvar[CVAR__ZONES_ON_RADAR])
}

/* -------------------- */

stock func_UpdateRadarStatus(iStatus) {
	remove_task(TASKID__UPDATE_RADAR)

	if(iStatus == RADAR_ZONES__OFF) {
		return
	}

	arrayset(g_bGotHostagePos, false, sizeof(g_bGotHostagePos))
	set_task(2.0, "task_UpdateRadar", TASKID__UPDATE_RADAR, .flags = "b")
}

/* -------------------- */

public task_UpdateRadar() {
	new pPlayers[MAX_PLAYERS], iPlCount, pPlayer, iZone

	if(g_eCvar[CVAR__ZONES_ON_RADAR] == RADAR_ZONES__ALL) {
		get_players(pPlayers, iPlCount, "a")
	}
	else {
		static const szFlags[RADAR_ZONES_STATUS_ENUM][] = { "", "TERRORIST", "CT", "" }
		get_players(pPlayers, iPlCount, "ae", szFlags[ g_eCvar[CVAR__ZONES_ON_RADAR] ])
	}

	for(new i; i < iPlCount; i++) {
		pPlayer = pPlayers[i]

		for(iZone = 0; iZone < g_iZoneCount; iZone++) {
			if(!g_bGotHostagePos[pPlayer]) {
				func_MsgHostagePos(pPlayer, iZone)
			}

			func_MsgHostageK(pPlayer, iZone)
		}

		g_bGotHostagePos[pPlayer] = true
	}
}

/* -------------------- */

stock func_MsgHostagePos(pPlayer, iZone) {
	message_begin(MSG_ONE, g_msgHostagePos, .player = pPlayer)
	write_byte(1)
	write_byte(iZone)
	write_coord_f(g_fZoneOrigin[iZone][X])
	write_coord_f(g_fZoneOrigin[iZone][Y])
	write_coord_f(g_fZoneOrigin[iZone][Z])
	message_end()
}

/* -------------------- */

stock func_MsgHostageK(pPlayer, iZone) {
	message_begin(MSG_ONE_UNRELIABLE, g_msgHostageK, .player = pPlayer)
	write_byte(iZone)
	message_end()
}

/* -------------------- */

public logevent_TerroristEscaped() {
	new szLogMsg[64], szName[1], iUserID

	read_logargv(0, szLogMsg, chx(szLogMsg))
	parse_loguser(szLogMsg, szName, chx(szName), iUserID)

	new pPlayer = find_player("k", iUserID)

	if(pPlayer) {
		func_AnnounceEscape(pPlayer)
		new Float:fFrags = Float:get_entvar(pPlayer, var_frags) + float(g_eCvar[CVAR__FRAGS_FOR_ESCAPE])
		set_entvar(pPlayer, var_frags, fFrags)
		func_ScoreInfo(pPlayer, floatround(fFrags))
		rg_set_user_money(pPlayer, g_eCvar[CVAR__MONEY_FOR_ESCAPE], AS_ADD, .bTrackChange = true)
	}

	g_iHaveEscaped++
	g_bEscaped[pPlayer] = true

	if(g_eCvar[CVAR__DISAPPEAR_AFTER_ESCAPE] && is_user_alive(pPlayer)) {
		rg_remove_all_items(pPlayer)
		set_member(pPlayer, m_iDeaths, get_member(pPlayer, m_iDeaths) - 1)
		set_entvar(pPlayer, var_frags, Float:get_entvar(pPlayer, var_frags) + 1.0)
		EnableHookChain(g_hStartSound)
		user_silentkill(pPlayer, .flag = 0)
		DisableHookChain(g_hStartSound)
		set_entvar(pPlayer, var_deadflag, DEAD_DISCARDBODY)
	}

	if(g_bRoundEnded) {
		return
	}

	if(g_eCvar[CVAR__INSTANT_TT_WIN_BY_RATIO]) {
		if(func_CheckRatio(g_iHaveEscaped)) {
			func_OverRound(WINSTATUS_TERRORISTS, ROUND_TERRORISTS_ESCAPED)
		}
	}
	else if(!func_CheckPotentialEscapers()) {
		func_OverRound()
	}
}

/* -------------------- */

stock func_AnnounceEscape(pPlayer) {
	if(g_bRoundEnded) {
		return
	}

	new pPlayers[MAX_PLAYERS], iPlCount, pTarget
	get_players(pPlayers, iPlCount, "ch") // NOTE: hltv excluded

	for(new i; i < iPlCount; i++) {
		pTarget = pPlayers[i]

		if(
			rg_get_user_team(pTarget) == TEAM_CT
				&&
			(
				g_eCvar[CVAR__ANNOUNCE_ESCAPE_TO_CT] == SHOW_TO_CT__OFF
					||
				(
					g_eCvar[CVAR__ANNOUNCE_ESCAPE_TO_CT] == SHOW_TO_CT__ONLY_DEAD
						&&
					is_user_alive(pTarget)
				)
			)
		) {
			continue
		}

		client_print(pTarget, print_center, "%L", pTarget, "ER__PLAYER_ESCAPED", pPlayer)

		if(g_eCvar[CVAR__ESCAPE_SOUND]) {
			rg_send_audio(pTarget, SOUND__TUTOR_MSG)
		}
	}
}

/* -------------------- */

public OnRoundEnd_Pre(WinStatus:iWinStatus, ScenarioEventEndRound:iScenarioEvent, Float:fNewRoundDelay) {
	if(iWinStatus == WINSTATUS_NONE || iWinStatus == WINSTATUS_DRAW || g_bRoundEnded) { // 1 - restart round, 2 - game commencing
		g_bRoundEnded = true
		return HC_CONTINUE
	}

	if(!get_member_game(m_bGameStarted)) {
		g_bRoundEnded = true
		SetHookChainArg(1, ATYPE_INTEGER, WINSTATUS_DRAW)
		SetHookChainArg(2, ATYPE_INTEGER, ROUND_END_DRAW)
		return HC_CONTINUE
	}

	if(g_eCvar[CVAR__SLAY_TT_ON_TIMEOUT] != SLAY_TT__NO && iScenarioEvent == ROUND_TERRORISTS_NOT_ESCAPED) {

		new bool:bTTsWin = func_CheckRatio(g_iHaveEscaped)

		if(!bTTsWin || g_eCvar[CVAR__SLAY_TT_ON_TIMEOUT] == SLAY_TT__EVEN_IF_WIN) {
			func_SlayNonEscapedTTs()
		}

		if(!bTTsWin) {
			g_bRoundEnded = true
			return HC_CONTINUE
		}
	}

	if(!func_CheckAliveCTs()) {
		g_bRoundEnded = true
		SetHookChainArg(1, ATYPE_INTEGER, WINSTATUS_TERRORISTS)
		SetHookChainArg(2, ATYPE_INTEGER, ROUND_TERRORISTS_WIN)
		return HC_CONTINUE
	}

	if(!func_CheckPotentialEscapers()) {
		g_bRoundEnded = true
		func_GetWinTeamByRatio(iWinStatus, iScenarioEvent)
		SetHookChainArg(1, ATYPE_INTEGER, iWinStatus)
		SetHookChainArg(2, ATYPE_INTEGER, iScenarioEvent)
		return HC_CONTINUE
	}

	SetHookChainReturn(ATYPE_INTEGER, false)
	return HC_SUPERCEDE
}

/* -------------------- */

public OnPlayerKilled_Post(pVictim, pKiller, iGib) {
	g_iLastTeam[pVictim] = TEAM_UNASSIGNED

	if(
		!g_bRoundEnded
			&&
		rg_get_user_team(pVictim) == TEAM_TERRORIST
			&&
		!g_bEscaped[pVictim]
			&&
		!func_CheckPotentialEscapers()
	) {
		func_OverRound()
	}
}

/* -------------------- */

stock func_GiveWeapon(pPlayer, szWeaponName[], iCvarPtr) {
	new WeaponIdType:iWeaponID = WeaponIdType:get_weaponid(szWeaponName)

	if(iWeaponID == WEAPON_NONE) { // wrong weapon
		return
	}

	rg_give_item(pPlayer, szWeaponName)

	new iBpAmmo

	if(g_eCvar[iCvarPtr] < 0) {
		iBpAmmo = rg_get_weapon_info(iWeaponID, WI_MAX_ROUNDS)

	}
	else {
		iBpAmmo = g_eCvar[iCvarPtr]
	}

	rg_set_user_bpammo(pPlayer, iWeaponID, iBpAmmo)
}

/* -------------------- */

public OnSpawnEquip_Pre(pPlayer, bool:bAddDefault, bool:bEquipGame) {
	new iTeam = rg_get_user_team(pPlayer)

	if(!g_eCvar[CVAR__STRIP_CT] && TeamName:iTeam == TEAM_CT && g_iLastTeam[pPlayer] == TeamName:iTeam) {
		return HC_SUPERCEDE
	}

	/* --- */

	g_iLastTeam[pPlayer] = TeamName:iTeam
	rg_remove_all_items(pPlayer)

	static const iPrimCvarPointers[_:TeamName] = { 0, CVAR__TT_PRIMARY_BPAMMO, CVAR__CT_PRIMARY_BPAMMO, 0 }
	static const iSecCvarPointers[_:TeamName] = { 0, CVAR__TT_SECONDARY_BPAMMO, CVAR__CT_SECONDARY_BPAMMO, 0 }

	if(g_szPrimary[iTeam][0]) {
		func_GiveWeapon(pPlayer, g_szPrimary[iTeam], iPrimCvarPointers[iTeam])
	}

	if(g_szSecondary[iTeam][0]) {
		func_GiveWeapon(pPlayer, g_szSecondary[iTeam], iSecCvarPointers[iTeam])
	}

	/* --- */

	static const iArmorPointers[_:TeamName] = { 0, CVAR__TT_ARMOR, CVAR__CT_ARMOR, 0 }

	new iPtr = iArmorPointers[iTeam]

	rg_set_user_armor(pPlayer, (iPtr && g_eCvar[iPtr]) ? g_eCvar[iPtr] : 0, ARMOR_VESTHELM)

	/* --- */

	static const iGrenadePointers[][_:TeamName] = {
		{ 0, CVAR__TT_HEGREN, CVAR__CT_HEGREN, 0 },
		{ 0, CVAR__TT_FLASHBANG, CVAR__CT_FLASHBANG, 0 },
		{ 0, CVAR__TT_SMOKE, CVAR__CT_SMOKE, 0 }
	}

	static const szGrenadeName[ sizeof(iGrenadePointers) ][] = { "weapon_hegrenade", "weapon_flashbang", "weapon_smokegrenade" }
	static const WeaponIdType:iGrenadeID[ sizeof(iGrenadePointers) ] = { WEAPON_HEGRENADE, WEAPON_FLASHBANG, WEAPON_SMOKEGRENADE }

	for(new i, iPtr; i < sizeof(iGrenadePointers); i++) {
		iPtr = iGrenadePointers[i][iTeam]

		if(!iPtr || !g_eCvar[iPtr]) {
			continue
		}

		rg_give_item(pPlayer, szGrenadeName[i])
		rg_set_user_bpammo(pPlayer, iGrenadeID[i], g_eCvar[iPtr])
	}

	rg_give_item(pPlayer, "weapon_knife")

	return HC_SUPERCEDE
}

/* -------------------- */

stock bool:func_CheckRatio(iHaveEscaped) {
	return (float(iHaveEscaped) / float(g_iNumEscapers) >= g_eCvar[CVAR_F__ESCAPE_RATIO])
}

/* -------------------- */

stock func_GetWinTeamByRatio(&WinStatus:iWinStatus, &ScenarioEventEndRound:iScenarioEvent) {
	if(func_CheckRatio(g_iHaveEscaped)) {
		iWinStatus = WINSTATUS_TERRORISTS
		iScenarioEvent = ROUND_TERRORISTS_ESCAPED
	}
	else {
		iWinStatus = WINSTATUS_CTS
		iScenarioEvent = ROUND_CTS_PREVENT_ESCAPE
	}
}

/* -------------------- */

stock bool:func_CheckPotentialEscapers() {
	new pPlayers[MAX_PLAYERS], iPlCount, pPlayer
	get_players(pPlayers, iPlCount, "ae", "TERRORIST")

	if(g_eCvar[CVAR__INSTANT_TT_LOOSE_BY_RATIO]) {
		new iCandidateCount

		for(new i; i < iPlCount; i++) {
			pPlayer = pPlayers[i]

			if(g_bEscaped[pPlayer] || !g_bIsConnected[pPlayer]) {
				continue
			}

			iCandidateCount++
		}

		return func_CheckRatio(g_iHaveEscaped + iCandidateCount)
	}

	//else ->

	for(new i; i < iPlCount; i++) {
		pPlayer = pPlayers[i]

		if(!g_bEscaped[pPlayer] && g_bIsConnected[pPlayer]) {
			return true
		}
	}

	return false
}

/* -------------------- */

stock func_CheckAliveCTs() {
	new pPlayers[MAX_PLAYERS], iPlCount
	get_players(pPlayers, iPlCount, "ae", "CT")
	return iPlCount

	/*new iRealCount = iPlCount

	for(new i; i < iPlCount; i++) {
		if( !g_bIsConnected[ pPlayers[i] ] ) {
			iRealCount--
		}
	}

	return iRealCount*/
}

/* -------------------- */

stock func_SlayNonEscapedTTs() {
	new pPlayers[MAX_PLAYERS], iPlCount, pPlayer, iKillCount
	get_players(pPlayers, iPlCount, "ae", "TERRORIST")

	for(new i; i < iPlCount; i++) {
		pPlayer = pPlayers[i]

		if(g_bEscaped[pPlayer]) {
			continue
		}

		iKillCount++
		user_kill(pPlayer, .flag = 0)
	}

	if(iKillCount) {
		client_print_color(0, print_team_red, "%L", LANG_PLAYER, "ER__SLAY_BY_TIMEOUT")
	}
}

/* -------------------- */

public OnRestartRound_Pre() {
	// make standart round reward calculation to work properly with escape scanario is
	// not as easy as i thought first, and to avoid manipulations with game members in
	// different places(pre/post) i decided to replace standart calculation with an
	// internal one (all code in one place)
	static iNumConsecutiveTerroristLoses
	static iNumConsecutiveCTLoses
	static iLoserBonus

	/* --- */

	g_bRoundEnded = false
	g_iNumEscapers = 0
	g_iHaveEscaped = 0
	arrayset(g_bEscaped, false, sizeof(g_bEscaped))
	arrayset(g_bSpawnedAsTer, false, sizeof(g_bSpawnedAsTer))

	/* --- */

	if(g_eCvar[CVAR_F__BUYTIME] && g_pBuyZoneEnt) {
		remove_task(TASKID__DISABLE_BUY)
		set_entvar(g_pBuyZoneEnt, var_solid, SOLID_TRIGGER)
	}

	/* --- */

	if(get_member_game(m_bCompleteReset)) {
		iNumConsecutiveTerroristLoses = 0
		iNumConsecutiveCTLoses = 0
		iLoserBonus = rg_get_account_rules(RR_LOSER_BONUS_DEFAULT)

		g_iNumEscapeRounds = 1
		arrayset(g_iLastTeam, _:TEAM_UNASSIGNED, sizeof(g_iLastTeam))

		return // !!! !!! !!!
	}

	/* --- */

	new WinStatus:iLastRoundWinStatus = get_member_game(m_iRoundWinStatus)
	// to break default round reward calculation (alt. way is to block RT_ROUND_BONUS in RG_CBasePlayer_AddAccount)
	set_member_game(m_iRoundWinStatus, WINSTATUS_DRAW)

	// https://github.com/s1lentq/ReGameDLL_CS/blob/master/regamedll/dlls/multiplay_gamerules.cpp#L1811
	switch(iLastRoundWinStatus) {
		case WINSTATUS_TERRORISTS: {
			if(iNumConsecutiveTerroristLoses > 1) {
				iLoserBonus = rg_get_account_rules(RR_LOSER_BONUS_MIN)
			}

			iNumConsecutiveTerroristLoses = 0
			iNumConsecutiveCTLoses++
		}
		case WINSTATUS_CTS: {
			if(iNumConsecutiveCTLoses > 1) {
				iLoserBonus = rg_get_account_rules(RR_LOSER_BONUS_MIN)
			}

			iNumConsecutiveCTLoses = 0
			iNumConsecutiveTerroristLoses++
		}
	}

	/* --- */

	if(
		(iNumConsecutiveTerroristLoses > 1 || iNumConsecutiveCTLoses > 1)
			&&
		iLoserBonus < rg_get_account_rules(RR_LOSER_BONUS_MAX)
	) {
		iLoserBonus += rg_get_account_rules(RR_LOSER_BONUS_ADD)
	}

	// at this moment calculation doesn't include bonus from 'hostage_entity'
	// it will be needed only if someone is make a 'supa-dupa' gameplay with escape and hostages at
	// the same time :)
	// https://github.com/s1lentq/ReGameDLL_CS/blob/master/regamedll/dlls/multiplay_gamerules.cpp#L1787

	new iAccountTerrorist, iAccountCT

	switch(iLastRoundWinStatus) {
		case WINSTATUS_TERRORISTS: {
			iAccountTerrorist = get_member_game(m_iAccountTerrorist)
			iAccountCT = iLoserBonus
		}
		case WINSTATUS_CTS: {
			iAccountCT = get_member_game(m_iAccountCT)

			// by default, TTs doesn't get loser bonus on 'es_' maps, but plugin provides this feature
			// https://github.com/s1lentq/ReGameDLL_CS/blob/master/regamedll/dlls/multiplay_gamerules.cpp#L1860
			if(g_eCvar[CVAR__TT_LOSER_BONUS_LIMIT] >= 0) {
				iAccountTerrorist = g_eCvar[CVAR__TT_LOSER_BONUS_LIMIT] ? min(iLoserBonus, g_eCvar[CVAR__TT_LOSER_BONUS_LIMIT]) : iLoserBonus;
			}
		}
	}

	// https://github.com/s1lentq/ReGameDLL_CS/blob/master/regamedll/dlls/multiplay_gamerules.cpp#L1866
	/*iAccountCT += get_member_game(m_iHostagesRescued) * rg_get_account_rules(RR_RESCUED_HOSTAGE)
	set_member_game(m_iHostagesRescued, 0)*/

	/* --- */

	if(g_eCvar[CVAR__ROUNDS_TO_SWAP_TEAMS] && g_iNumEscapeRounds >= g_eCvar[CVAR__ROUNDS_TO_SWAP_TEAMS]) {
		// swap team rewards
		set_member_game(m_iAccountTerrorist, iAccountCT)
		set_member_game(m_iAccountCT, iAccountTerrorist)

		// swap consecutive loses
		new iTempTtLoses = iNumConsecutiveTerroristLoses
		new iTempCtLoses = iNumConsecutiveCTLoses
		iNumConsecutiveTerroristLoses = iTempCtLoses
		iNumConsecutiveCTLoses = iTempTtLoses

		// forces gamedll to swap teams
		// https://github.com/s1lentq/ReGameDLL_CS/blob/master/regamedll/dlls/multiplay_gamerules.cpp#L1771
		set_member_game(m_iNumEscapeRounds, 3)
		g_iNumEscapeRounds = 0

		arrayset(g_iLastTeam, _:TEAM_UNASSIGNED, sizeof(g_iLastTeam))
	}
	else {
		// prevent hardcoded swap after 3 rounds and use g_iNumEscapeRounds as counter instead
		set_member_game(m_iNumEscapeRounds, 0)

		set_member_game(m_iAccountTerrorist, iAccountTerrorist)
		set_member_game(m_iAccountCT, iAccountCT)
	}

	g_iNumEscapeRounds++

	/*log_message( "m_iAccountTerrorist: %d | m_iAccountCT: %d | m_iLoserBonus: %d",
		get_member_game(m_iAccountTerrorist), get_member_game(m_iAccountCT), get_member_game(m_iLoserBonus) );*/
}

/* -------------------- */

public OnRestartRound_Post() {
	func_UpdateBuyMode(g_eCvar[CVAR__BUY_MODE])
}

/* -------------------- */

public OnPlayerSpawn_Post(pPlayer) {
	if(!is_user_alive(pPlayer)) {
		return
	}

	new TeamName:iTeam = rg_get_user_team(pPlayer)

	if(iTeam == TEAM_TERRORIST && !g_bSpawnedAsTer[pPlayer]) {
		g_bSpawnedAsTer[pPlayer] = true
		g_iNumEscapers++
	}

	if(g_bEscaped[pPlayer]) {
		// to prevent TT escape twice per round if he died and somehow get respawned (compatibility)
		set_member(pPlayer, m_bEscaped, true)
	}

	if(g_eCvar[CVAR__SHOW_INFO_MENU] && !g_eGotInfo[pPlayer][iTeam]) {
		new szMenu[MAX_MENU_LENGTH], bool:bZonesOnRadar

		if(g_eCvar[CVAR__ZONES_ON_RADAR] == RADAR_ZONES__ALL || _:iTeam == g_eCvar[CVAR__ZONES_ON_RADAR]) {
			bZonesOnRadar = true
		}

		formatex( szMenu, chx(szMenu), "%L%L",
			pPlayer, (iTeam == TEAM_CT) ? "ES__OBJ_INFO_CT" : "ES__OBJ_INFO_TT",
			pPlayer, bZonesOnRadar ? "ES__OBJ_INFO_RADAR_ZONES_ON" : "ES__OBJ_INFO_RADAR_ZONES_OFF",
			pPlayer, "ES__OBJ_BUTTONS"
		);

		show_menu(pPlayer, MENU_KEYS, szMenu, -1, MENU_IDENT_STRING)
	}
}

/* -------------------- */

public OnRoundFreezeEnd_Post() {
	if(g_eCvar[CVAR_F__BUYTIME] > 0.0 && g_pBuyZoneEnt) {
		set_task(g_eCvar[CVAR_F__BUYTIME], "task_DisableBuy", TASKID__DISABLE_BUY)
	}
}

/* -------------------- */

public func_Menu_Handler(pPlayer, iKey) {
	if(!g_bIsConnected[pPlayer]) {
		return
	}

	if(iKey == _KEY4_) {
		g_eGotInfo[pPlayer][ rg_get_user_team(pPlayer) ] = true
		return
	}

	//else -> _KEY5_

	g_eGotInfo[pPlayer][TEAM_TERRORIST] =
		g_eGotInfo[pPlayer][TEAM_CT] = true;
}

/* -------------------- */

public client_putinserver(pPlayer) {
	g_bIsConnected[pPlayer] = true

	g_eGotInfo[pPlayer][TEAM_TERRORIST] =
		g_eGotInfo[pPlayer][TEAM_CT] =
			bool:is_user_bot(pPlayer);
}

/* -------------------- */

public client_disconnected(pPlayer) {
	g_bIsConnected[pPlayer] = false
	g_iLastTeam[pPlayer] = TEAM_UNASSIGNED
	g_bGotHostagePos[pPlayer] = false

	if(
		is_user_alive(pPlayer)
			&&
		rg_get_user_team(pPlayer) == TEAM_TERRORIST
			&&
		!g_bEscaped[pPlayer]
			&&
		!g_bRoundEnded
			&&
		!func_CheckPotentialEscapers()
	) {
		func_OverRound()
	}
}

/* -------------------- */

stock func_OverRound(WinStatus:iWinStatus = WINSTATUS_NONE, ScenarioEventEndRound:iScenarioEvent = ROUND_NONE) {
	if(!get_member_game(m_bGameStarted)) {
		rg_round_end(g_eCvar[CVAR_F__ROUND_RESTART_DELAY], WINSTATUS_DRAW, ROUND_END_DRAW, .trigger = true)
		return
	}

	new iTsWins, iCtsWins, CSGameRules_Members:mTeamAccount, iReward

	if(iWinStatus == WINSTATUS_NONE) {
		func_GetWinTeamByRatio(iWinStatus, iScenarioEvent)
	}

	if(iWinStatus == WINSTATUS_TERRORISTS) {
		iTsWins = 1
		mTeamAccount = m_iAccountTerrorist
		iReward = rg_get_account_rules(RR_TERRORISTS_ESCAPED)
	}
	else {
		iCtsWins = 1
		mTeamAccount = m_iAccountCT
		iReward = rg_get_account_rules(RR_CTS_PREVENT_ESCAPE)
	}

	g_bRoundEnded = true
	set_member_game(mTeamAccount, iReward)
	rg_update_teamscores(iCtsWins, iTsWins, .bAdd = true)
	rg_round_end(g_eCvar[CVAR_F__ROUND_RESTART_DELAY], iWinStatus, iScenarioEvent, .trigger = true)
}

/* -------------------- */

public msg_TextMsg(/*iMsgID, iMsgDest, iMsgEnt*/) {
	new const szPattern[] = "#Terrorist_Escaped"
	new szMsg[ sizeof(szPattern) ]
	get_msg_arg_string(2, szMsg, chx(szMsg))
	return equal(szMsg, szPattern) ? PLUGIN_HANDLED : PLUGIN_CONTINUE
}

/* -------------------- */

public msg_ClCorpse(/*iMsgID, iMsgDest, iMsgEnt*/) {
	return g_bEscaped[ get_msg_arg_int(12) ] ? PLUGIN_HANDLED : PLUGIN_CONTINUE
}

/* -------------------- */

public OnStartSound_Pre(iRecipients, iEntity, iChanngel, szSample[], iVolume, Float:fAttenuation, iFlags, const pitch) {
	// player/die#.wav, player/death#.wav
	//return (contain(szSample, "player/d") == -1) ? HC_CONTINUE : HC_SUPERCEDE
	return HC_SUPERCEDE
}

/* -------------------- */

public hook_CvarChange(pCvar, szOldVal[], szNewVal[]) {
	new iNewVal = str_to_num(szNewVal)

	if(pCvar == g_pCvar[PCVAR__BUY_MODE]) {
		func_UpdateBuyMode(iNewVal)
	}
	else if(pCvar == g_pCvar[PCVAR__BUYTIME]) {
		if(!iNewVal && g_pBuyZoneEnt) {
			set_entvar(g_pBuyZoneEnt, var_solid, SOLID_NOT)
			remove_task(TASKID__DISABLE_BUY)
		}
	}
	else if(g_bConfigsExecuted) { // PCVAR__ZONES_ON_RADAR
		func_UpdateRadarStatus(iNewVal)
	}
}

/* -------------------- */

stock func_UpdateBuyMode(iValue) {
	new bool:bTCantBuy, bool:bCTCantBuy

	switch(iValue) {
		case BUY_MODE__DEFAULT: {
			new iEnt = rg_find_ent_by_class(MaxClients, "info_map_parameters", .useHashTable = true)

			if(iEnt) {
				switch(InfoMapBuyParam:get_member(iEnt, m_MapInfo_iBuyingStatus)) {
					//case BUYING_EVERYONE: {}
					case BUYING_ONLY_CTS: {
						bTCantBuy = true
					}
					case BUYING_ONLY_TERRORISTS: {
						bCTCantBuy = true
					}
					case BUYING_NO_ONE: {
						bTCantBuy = true
						bCTCantBuy = true
					}
				}
			}
		}
		case BUY_MODE__NONE: {
			bTCantBuy = true
			bCTCantBuy = true
		}
		case BUY_MODE__TT: {
			bCTCantBuy = true
		}
		case BUY_MODE__CT: {
			bTCantBuy = true
		}
		//case BUY_MODE__ALL: {}
	}

	set_member_game(m_bTCantBuy, bTCantBuy)
	set_member_game(m_bCTCantBuy, bCTCantBuy)
}

/* -------------------- */

public task_DisableBuy() {
	set_entvar(g_pBuyZoneEnt, var_solid, SOLID_NOT)
}

/* -------------------- */

stock func_ScoreInfo(pPlayer, iFrags) {
	message_begin(MSG_BROADCAST, g_msgScoreInfo)
	write_byte(pPlayer)
	write_short(iFrags)
	write_short(get_member(pPlayer, m_iDeaths))
	write_short(0)
	write_short(rg_get_user_team(pPlayer))
	message_end()
}

/* -------------------- */

stock func_FindEscapeZones() {
	new Float:fOrigin[XYZ], Float:fMins[XYZ], Float:fMaxs[XYZ], pEnt = MaxClients

	while((pEnt = rg_find_ent_by_class(pEnt, "func_escapezone", .useHashTable = true)) && g_iZoneCount < MAX_ESCAPE_ZONES) {
		get_entvar(pEnt, var_origin, fOrigin)

		// compatibility with 'escape zone editor' (for future)
		// brush (map default) entity will have zero origin
		if(!fOrigin[X] && !fOrigin[Y] && !fOrigin[Z]) {
			get_entvar(pEnt, var_mins, fMins)
			get_entvar(pEnt, var_maxs, fMaxs)

			g_fZoneOrigin[g_iZoneCount][X] = (fMins[X] + fMaxs[X]) * 0.5
			g_fZoneOrigin[g_iZoneCount][Y] = (fMins[Y] + fMaxs[Y]) * 0.5
			g_fZoneOrigin[g_iZoneCount][Z] = (fMins[Z] + fMaxs[Z]) * 0.5
		}
		else {
			g_fZoneOrigin[g_iZoneCount][X] = fOrigin[X]
			g_fZoneOrigin[g_iZoneCount][Y] = fOrigin[Y]
			g_fZoneOrigin[g_iZoneCount][Z] = fOrigin[Z]
		}

		g_iZoneCount++
	}
}

/* -------------------- */

stock func_RegCvars() {
	bind_pcvar_num( create_cvar("es_rounds_to_swap_teams", "1", FCVAR_SERVER,
		.has_min = true, .min_val = 0.0,
		.description = "The number of rounds after which teams will be swapped^n\
		By default swaping occur each three rounds^n0 - Disable swapping"),
		g_eCvar[CVAR__ROUNDS_TO_SWAP_TEAMS] );

	bind_pcvar_float( create_cvar("es_escape_ratio", "0.4", FCVAR_SERVER,
		.has_min = true, .min_val = 0.1, .has_max = true, .max_val = 1.0,
		.description = "Ratio that determines how many terrorists must escape to win a round^n\
		Default ratio is 0.5"),
		g_eCvar[CVAR_F__ESCAPE_RATIO] );

	bind_pcvar_num( create_cvar("es_instant_tt_win_by_ratio", "1", FCVAR_SERVER,
		.has_min = true, .min_val = 0.0, .has_max = true, .max_val = 1.0,
		.description = "Defines behavior when a escape ratio is reached^n\
		0 - Round continues as long as there are any living escape candidates^n\
		1 - TTs win the round immediately (default behavior)"),
		g_eCvar[CVAR__INSTANT_TT_WIN_BY_RATIO] );

	bind_pcvar_num( create_cvar("es_instant_tt_loose_by_ratio", "1", FCVAR_SERVER,
		.has_min = true, .min_val = 0.0, .has_max = true, .max_val = 1.0,
		.description = "Defines behavior when a escape ratio can't be reached anymore^n\
		0 - Round continues as long as there are any living escape candidates^n\
		1 - CTs win the round immediately (default behavior)"),
		g_eCvar[CVAR__INSTANT_TT_LOOSE_BY_RATIO] );

	bind_pcvar_num( create_cvar("es_disappear_after_escape", "1", FCVAR_SERVER,
		.has_min = true, .min_val = 0.0, .has_max = true, .max_val = 1.0,
		.description = "Terrorist must disappear after escape?^n\
		0 - Terrorist stays in game and can help to his team by eleminating remaining CTs^n\
		1 - Terrorist immediately moved to spectators (default behavior)"),
		g_eCvar[CVAR__DISAPPEAR_AFTER_ESCAPE] );

	bind_pcvar_num( create_cvar("es_frags_for_escape", "3", FCVAR_SERVER,
		.has_min = true, .min_val = 0.0,
		.description = "How many frags a player gets for escaping (0 - default behavior)"),
		g_eCvar[CVAR__FRAGS_FOR_ESCAPE] );

	bind_pcvar_num( create_cvar("es_money_for_escape", "500", FCVAR_SERVER,
		.has_min = true, .min_val = 0.0,
		.description = "How many $ a player gets for escaping (0 - default behavior)"),
		g_eCvar[CVAR__MONEY_FOR_ESCAPE] );

	/* --- */

	g_pCvar[PCVAR__ZONES_ON_RADAR] = create_cvar( "es_zones_on_radar", "3", FCVAR_SERVER,
		.has_min = true, .min_val = 0.0, .has_max = true, .max_val = 3.0,
		.description = "Show escape zones on radar?^n\
		0 - Do not show (default behavior)^n1 - Show only for TTs^n\
		2 - Show only for CTs^n3 - Show for all" );

	bind_pcvar_num(g_pCvar[PCVAR__ZONES_ON_RADAR], g_eCvar[CVAR__ZONES_ON_RADAR])
	hook_cvar_change(g_pCvar[PCVAR__ZONES_ON_RADAR], "hook_CvarChange")

	/* --- */

	bind_pcvar_num( create_cvar("es_announce_escape_to_ct", "1", FCVAR_SERVER,
		.has_min = true, .min_val = 0.0, .has_max = true, .max_val = 2.0,
		.description = "Show escape information to CT's?^n\
		0 - Do not show (default behavior)^n1 - Show only for dead^n2 - Show for all"),
		g_eCvar[CVAR__ANNOUNCE_ESCAPE_TO_CT] );

	bind_pcvar_num( create_cvar("es_escape_sound", "1", FCVAR_SERVER,
		.has_min = true, .min_val = 0.0, .has_max = true, .max_val = 1.0,
		.description = "Accompany escape information with a sound effect?"),
		g_eCvar[CVAR__ESCAPE_SOUND] );

	bind_pcvar_num( create_cvar("es_slay_tt_on_timeout", "1", FCVAR_SERVER,
		.has_min = true, .min_val = 0.0, .has_max = true, .max_val = 2.0,
		.description = "Slay all non-escaped TT's when time runs out?^n\
		0 - Do not slay (default behavior)^n1 - Slay only when loose^n2 - Slay even if win"),
		g_eCvar[CVAR__SLAY_TT_ON_TIMEOUT] );

	bind_pcvar_num( create_cvar("es_strip_ct", "0", FCVAR_SERVER,
		.has_min = true, .min_val = 0.0, .has_max = true, .max_val = 1.0,
		.description = "Strip all stuff from CTs (same as from TTs) on every round?^n\
		0 - Do not strip (default behavior)^n1 - Strip"),
		g_eCvar[CVAR__STRIP_CT] );

	bind_pcvar_num( create_cvar("es_remove_map_items", "0", FCVAR_SERVER,
	.has_min = true, .min_val = 0.0, .has_max = true, .max_val = 1.0,
		.description = "Remove all map items (weapons, grenades, armor)?^n\
		0 - Do not remove (default behavior)^n1 - Remove"),
		g_eCvar[CVAR__REMOVE_MAP_ITEMS] );

	/* --- */

	g_pCvar[PCVAR__BUY_MODE] = create_cvar( "es_buy_mode", "-1", FCVAR_SERVER,
		.has_min = true, .min_val = -1.0, .has_max = true, .max_val = 3.0,
		.description = "Determines global buying mode:^n\
		-1 - Use map rules (default behavior)^n0 - Buying disabled^n\
		1 - Only TT can buy^n2 - Only CT can buy^n3 - Both teams can buy" );

	bind_pcvar_num(g_pCvar[PCVAR__BUY_MODE], g_eCvar[CVAR__BUY_MODE])
	func_UpdateBuyMode(get_pcvar_num(g_pCvar[PCVAR__BUY_MODE]))
	hook_cvar_change(g_pCvar[PCVAR__BUY_MODE], "hook_CvarChange")

	/* --- */

	g_pCvar[PCVAR__BUYTIME] = create_cvar( "es_buytime", "15", FCVAR_SERVER,
		.has_min = true, .min_val = -1.0,
		.description = "Time (in seconds, +freezetime) to buy equipment^n\
		-1 - No limit^n0 - Disable buying^n> 0 - Limit by value" );

	bind_pcvar_float(g_pCvar[PCVAR__BUYTIME], g_eCvar[CVAR_F__BUYTIME])
	hook_cvar_change(g_pCvar[PCVAR__BUYTIME], "hook_CvarChange")

	/* --- */

	bind_pcvar_num( create_cvar("es_tt_loser_bonus_limit", "0", FCVAR_SERVER,
		.has_min = true, .min_val = -1.0,
		.description = "Determines whether TTs can receive a round loser bonus^n\
		-1 - Disable bonus (default behavior)^n0 - No limit^n> 0 - Limit by value"),
		g_eCvar[CVAR__TT_LOSER_BONUS_LIMIT] );

	bind_pcvar_num( create_cvar("es_show_info_menu", "1", FCVAR_SERVER,
		.has_min = true, .min_val = 0.0, .has_max = true, .max_val = 1.0,
		.description = "Show menu with objectives info to new players?"),
		g_eCvar[CVAR__SHOW_INFO_MENU] );

	/* --- */

	bind_pcvar_string( create_cvar("es_tt_primary", "", FCVAR_SERVER,
		.description = "Default primary weapon for terrorists^n\
		Use this if you confused: https://wiki.alliedmods.net/Cs_weapons_information"),
		g_szPrimary[_:TEAM_TERRORIST], chx(g_szPrimary[]) );

	bind_pcvar_num( create_cvar("es_tt_primary_bpammo", "0", FCVAR_SERVER,
		.has_min = true, .min_val = -1.0,
		.description = "Default primary weapon backpack ammo amount for terrorists^n-1 - Auto (max)"),
		g_eCvar[CVAR__TT_PRIMARY_BPAMMO] );

	bind_pcvar_string( create_cvar("es_tt_secondary", "weapon_glock18", FCVAR_SERVER,
		.description = "Default secondary weapon for terrorists"),
		g_szSecondary[_:TEAM_TERRORIST], chx(g_szSecondary[]) );

	bind_pcvar_num( create_cvar("es_tt_secondary_bpammo", "40", FCVAR_SERVER,
		.has_min = true, .min_val = -1.0,
		.description = "Default secondary weapon backpack ammo amount for terrorists^n-1 - Auto (max)"),
		g_eCvar[CVAR__TT_SECONDARY_BPAMMO] );

	bind_pcvar_num( create_cvar("es_tt_armor", "0", FCVAR_SERVER,
		.has_min = true, .min_val = 0.0,
		.description = "Default armor value for terrorists"),
		g_eCvar[CVAR__TT_ARMOR] );

	bind_pcvar_num( create_cvar("es_tt_hegrenade", "0", FCVAR_SERVER,
		.has_min = true, .min_val = 0.0,
		.description = "Default explosive grenades count for terrorists"),
		g_eCvar[CVAR__TT_HEGREN] );

	bind_pcvar_num( create_cvar("es_tt_flashbang", "0", FCVAR_SERVER,
		.has_min = true, .min_val = 0.0,
		.description = "Default flashbang grenades count for terrorists"),
		g_eCvar[CVAR__TT_FLASHBANG] );

	bind_pcvar_num( create_cvar("es_tt_smokenade", "0", FCVAR_SERVER,
		.has_min = true, .min_val = 0.0,
		.description = "Default smoke grenades count for terrorists"),
		g_eCvar[CVAR__TT_SMOKE] );

	/* --- */

	bind_pcvar_string( create_cvar("es_ct_primary", "", FCVAR_SERVER,
		.description = "Default primary weapon for counter-terrorists^n\
		Use this if you confused: https://wiki.alliedmods.net/Cs_weapons_information"),
		g_szPrimary[_:TEAM_CT], chx(g_szPrimary[]) );

	bind_pcvar_num( create_cvar("es_ct_primary_bpammo", "0", FCVAR_SERVER,
		.has_min = true, .min_val = -1.0,
		.description = "Default primary weapon backpack ammo amount for counter-terrorists^n-1 - Auto (max)"),
		g_eCvar[CVAR__CT_PRIMARY_BPAMMO] );

	bind_pcvar_string( create_cvar("es_ct_secondary", "weapon_usp", FCVAR_SERVER,
		.description = "Default secondary weapon for counter-terrorists"),
		g_szSecondary[_:TEAM_CT], chx(g_szSecondary[]) );

	bind_pcvar_num( create_cvar("es_ct_secondary_bpammo", "24", FCVAR_SERVER,
		.has_min = true, .min_val = -1.0,
		.description = "Default secondary weapon backpack ammo amount for counter-terrorists^n-1 - Auto (max)"),
		g_eCvar[CVAR__CT_SECONDARY_BPAMMO] );

	bind_pcvar_num( create_cvar("es_ct_armor", "0", FCVAR_SERVER,
		.has_min = true, .min_val = 0.0,
		.description = "Default armor value for counter-terrorists"),
		g_eCvar[CVAR__CT_ARMOR] );

	bind_pcvar_num( create_cvar("es_ct_hegrenade", "0", FCVAR_SERVER,
		.has_min = true, .min_val = 0.0,
		.description = "Default explosive grenades count for counter-terrorists"),
		g_eCvar[CVAR__CT_HEGREN] );

	bind_pcvar_num( create_cvar("es_ct_flashbang", "0", FCVAR_SERVER,
		.has_min = true, .min_val = 0.0,
		.description = "Default flashbang grenades count for counter-terrorists"),
		g_eCvar[CVAR__CT_FLASHBANG] );

	bind_pcvar_num( create_cvar("es_ct_smokenade", "0", FCVAR_SERVER,
		.has_min = true, .min_val = 0.0,
		.description = "Default smoke grenades count for counter-terrorists"),
		g_eCvar[CVAR__CT_SMOKE] );

	/* --- */

	bind_pcvar_float(get_cvar_pointer("mp_round_restart_delay"), g_eCvar[CVAR_F__ROUND_RESTART_DELAY])

	/* --- */

#if defined AUTO_CFG
	AutoExecConfig()
#endif
}