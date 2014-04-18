//
// SourceMod Script
//
// Developed by <eVa>Dog
// June 2008
// http://www.theville.org
//

//
// DESCRIPTION:
// Allows players to vote mute a player

// Voting adapted from AlliedModders' basevotes system
// basevotes.sp, basekick.sp
//


// Includes
#include <sourcemod>
#include <sdktools>
#undef REQUIRE_PLUGIN
#include <adminmenu>
#include <donator>


// Defines
// Plugin Info
#define PLUGIN_INFO_VERSION			"1.0.105P.D2"
#define PLUGIN_INFO_NAME			"Donator Vote Mute"
#define PLUGIN_INFO_AUTHOR			"<eVa>Dog/AlliedModders LLC/Malachi"
#define PLUGIN_INFO_DESCRIPTION		"Donator-initiated vote to mute"
#define PLUGIN_INFO_URL				"http://www.theville.org"
#define PLUGIN_PRINT_NAME			"[Donator:VoteMute]"			// Used for self-identification in chat/logging

#define VOTE_CLIENTID	0
#define VOTE_USERID		1
#define VOTE_NAME		0
#define VOTE_NO 		"###no###"
#define VOTE_YES 		"###yes###"

// These define the text players see in the donator menu
#define MENUTEXT_CHOOSEPLAYER				"Vote Mute"
#define MENUTITLE_CHOOSEPLAYER				"Choose player:"



// Globals
new Handle:g_Cvar_Limits
new Handle:g_hVoteMenu = INVALID_HANDLE
new g_voteClient[2]
new String:g_voteInfo[3][65]
new g_votetype = 0
new bool:g_Gagged[65]


// Info
public Plugin:myinfo = 
{
	name = PLUGIN_INFO_NAME,
	author = PLUGIN_INFO_AUTHOR,
	description = PLUGIN_INFO_DESCRIPTION,
	version = PLUGIN_INFO_VERSION,
	url = PLUGIN_INFO_URL
}


public OnPluginStart()
{
	CreateConVar("sm_votemute_version", PLUGIN_INFO_VERSION, "Version of votemute/votesilence", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY)
	g_Cvar_Limits = CreateConVar("sm_votemute_limit", "0.30", "Vote percentage required for successful mute.")
		
	//Allowed for ALL players
	RegConsoleCmd("sm_votemute", Command_Votemute,  "sm_votemute <player> ")  
}


public OnAllPluginsLoaded()
{
	if(!LibraryExists("donator.core")) 
		SetFailState("Unable to find plugin: Basic Donator Interface");

	Donator_RegisterMenuItem(MENUTEXT_CHOOSEPLAYER, VoteMuteCallback);
}


public DonatorMenu:VoteMuteCallback(iClient)
{
	DisplayVoteTargetMenu(iClient);
}


public Action:Command_Votemute(client, args)
{
	new String:name[MAX_NAME_LENGTH];
	GetClientName(client, name, sizeof(name));
	
	// Is this client a donator?
	if (IsPlayerDonator(client))
	{
		PrintToServer("%s Donator %s started a mute vote.", PLUGIN_PRINT_NAME, name);
	}
	else
	{
		ReplyToCommand(client, "%s You must be a donator to use this command.", PLUGIN_PRINT_NAME);
		return Plugin_Handled
	}
	

	if (IsVoteInProgress())
	{
		ReplyToCommand(client, "%s Vote in Progress", PLUGIN_PRINT_NAME);
		return Plugin_Handled
	}	
	
	if (!TestVoteDelay(client))
	{
		return Plugin_Handled
	}
	
	if (args < 1)
	{
		g_votetype = 0
		DisplayVoteTargetMenu(client)
	}
	else
	{
		new String:arg[64]
		GetCmdArg(1, arg, 64)
		
		new target = FindTarget(client, arg)

		if (target == -1)
		{
			return Plugin_Handled;
		}
		
		g_votetype = 0
		DisplayVoteMuteMenu(client, target)
	}
	
	return Plugin_Handled
}


DisplayVoteMuteMenu(client, target)
{
	g_voteClient[VOTE_CLIENTID] = target;
	g_voteClient[VOTE_USERID] = GetClientUserId(target);

	GetClientName(target, g_voteInfo[VOTE_NAME], sizeof(g_voteInfo[]));

	if (g_votetype == 0)
	{
		LogAction(client, target, "\"%L\" initiated a mute vote against \"%L\"", client, target);
		ShowActivity(client, "%s", "Initiated Vote Mute", g_voteInfo[VOTE_NAME]);
		
		g_hVoteMenu = CreateMenu(Handler_VoteCallback, MenuAction:MENU_ACTIONS_ALL);
		SetMenuTitle(g_hVoteMenu, "Mute Player:");
	}
	else if (g_votetype == 1)
	{
		LogAction(client, target, "\"%L\" initiated a silence vote against \"%L\"", client, target);
		ShowActivity(client, "%s", "Initiated Vote Silence", g_voteInfo[VOTE_NAME]);
		
		g_hVoteMenu = CreateMenu(Handler_VoteCallback, MenuAction:MENU_ACTIONS_ALL);
		SetMenuTitle(g_hVoteMenu, "Silence Player:");
	}
	else 
	{
		LogAction(client, target, "\"%L\" initiated a gag vote against \"%L\"", client, target);
		ShowActivity(client, "%s", "Initiated Vote Gag", g_voteInfo[VOTE_NAME]);
		
		g_hVoteMenu = CreateMenu(Handler_VoteCallback, MenuAction:MENU_ACTIONS_ALL);
		SetMenuTitle(g_hVoteMenu, "Gag Player:");
	}
	AddMenuItem(g_hVoteMenu, VOTE_YES, "Yes");
	AddMenuItem(g_hVoteMenu, VOTE_NO, "No");
	SetMenuExitButton(g_hVoteMenu, false);
	VoteMenuToAll(g_hVoteMenu, 20);
}


DisplayVoteTargetMenu(client)
{
	new Handle:menu = CreateMenu(MenuHandler_Vote);
	new count = 0;
	
	decl String:title[100];
	new String:playername[128]
	new String:identifier[64]
	Format(title, sizeof(title), "%s", MENUTITLE_CHOOSEPLAYER);
	SetMenuTitle(menu, title);
//	SetMenuExitBackButton(menu, true);
	
	for (new i = 1; i < GetMaxClients(); i++)
	{
		if (IsClientInGame(i) && !(GetUserFlagBits(i) & ADMFLAG_CHAT) && !IsFakeClient(i))
		{
			GetClientName(i, playername, sizeof(playername))
			Format(identifier, sizeof(identifier), "%i", i)
			AddMenuItem(menu, identifier, playername)
			count++;
		}
	}
	
	if (count > 0)
	{
		DisplayMenu(menu, client, MENU_TIME_FOREVER);
	}
	else
	{
		PrintToChat(client, "%s No muteable players.",  PLUGIN_PRINT_NAME);
	}
}


public MenuHandler_Vote(Handle:menu, MenuAction:action, param1, param2)
{
	if (action == MenuAction_End)
	{
		CloseHandle(menu);
	}
	else if (action == MenuAction_Select)
	{
		decl String:info[32], String:name[32];
		new target;
		
		GetMenuItem(menu, param2, info, sizeof(info), _, name, sizeof(name));
		target = StringToInt(info);

		if (target == 0)
		{
			PrintToChat(param1, "%s %s",  PLUGIN_PRINT_NAME, "Player no longer available.");
		}
		else
		{
			if (IsVoteInProgress())
			{
				PrintToChat(param1, "%s Vote in Progress", PLUGIN_PRINT_NAME);
			}
			else
			{
				DisplayVoteMuteMenu(param1, target);
			}
		}
	}
}

public Handler_VoteCallback(Handle:menu, MenuAction:action, param1, param2)
{
	if (action == MenuAction_End)
	{
		VoteMenuClose();
	}
	else if (action == MenuAction_Display)
	{
		decl String:title[64];
		GetMenuTitle(menu, title, sizeof(title));
		
		decl String:buffer[255];
		Format(buffer, sizeof(buffer), "%s %s", title, g_voteInfo[VOTE_NAME]);

		new Handle:panel = Handle:param2;
		SetPanelTitle(panel, buffer);
	}
	else if (action == MenuAction_DisplayItem)
	{
		decl String:display[64];
		GetMenuItem(menu, param2, "", 0, _, display, sizeof(display));
	 
	 	if (strcmp(display, "No") == 0 || strcmp(display, "Yes") == 0)
	 	{
			decl String:buffer[255];
			Format(buffer, sizeof(buffer), "%s", display);

			return RedrawMenuItem(buffer);
		}
	}
	/* else if (action == MenuAction_Select)
	{
		VoteSelect(menu, param1, param2);
	}*/
	else if (action == MenuAction_VoteCancel && param1 == VoteCancel_NoVotes)
	{
		PrintToChatAll("%s %s", PLUGIN_PRINT_NAME, "No Votes Cast");
	}	
	else if (action == MenuAction_VoteEnd)
	{
		decl String:item[64], String:display[64];
		new Float:percent, Float:limit, votes, totalVotes;

		GetMenuVoteInfo(param2, votes, totalVotes);
		GetMenuItem(menu, param1, item, sizeof(item), _, display, sizeof(display));
		
		if (strcmp(item, VOTE_NO) == 0 && param1 == 1)
		{
			votes = totalVotes - votes; // Reverse the votes to be in relation to the Yes option.
		}
		
		percent = GetVotePercent(votes, totalVotes);
		
		limit = GetConVarFloat(g_Cvar_Limits);
		
		if ((strcmp(item, VOTE_YES) == 0 && FloatCompare(percent,limit) < 0 && param1 == 0) || (strcmp(item, VOTE_NO) == 0 && param1 == 1))
		{
			LogAction(-1, -1, "Vote failed.");
			PrintToChatAll("%s %s", PLUGIN_PRINT_NAME, "Vote Failed", RoundToNearest(100.0*limit), RoundToNearest(100.0*percent), totalVotes);
		}
		else
		{
			PrintToChatAll("%s %s", PLUGIN_PRINT_NAME, "Vote Successful", RoundToNearest(100.0*percent), totalVotes);			
			if (g_votetype == 0)
			{
				PrintToChatAll("%s %s", PLUGIN_PRINT_NAME, "Muted target", "_s", g_voteInfo[VOTE_NAME]);
				LogAction(-1, g_voteClient[VOTE_CLIENTID], "Vote mute successful, muted \"%L\" ", g_voteClient[VOTE_CLIENTID]);
				SetClientListeningFlags( g_voteClient[VOTE_CLIENTID], VOICE_MUTED);					
			}
			else if (g_votetype == 1)
			{
				PrintToChatAll("%s %s", PLUGIN_PRINT_NAME, "Silenced target", "_s", g_voteInfo[VOTE_NAME]);	
				LogAction(-1, g_voteClient[VOTE_CLIENTID], "Vote silence successful, silenced \"%L\" ", g_voteClient[VOTE_CLIENTID]);
				SetClientListeningFlags( g_voteClient[VOTE_CLIENTID], VOICE_MUTED);
				g_Gagged[g_voteClient[VOTE_CLIENTID]] = true
			}		
			else 
			{
				PrintToChatAll("%s %s", PLUGIN_PRINT_NAME, "Gagged target", "_s", g_voteInfo[VOTE_NAME]);	
				LogAction(-1, g_voteClient[VOTE_CLIENTID], "Vote gag successful, gagged \"%L\" ", g_voteClient[VOTE_CLIENTID]);
				g_Gagged[g_voteClient[VOTE_CLIENTID]] = true
			}	
		}
	}
	return 0;
}

VoteMenuClose()
{
	CloseHandle(g_hVoteMenu)
	g_hVoteMenu = INVALID_HANDLE
}

Float:GetVotePercent(votes, totalVotes)
{
	return FloatDiv(float(votes),float(totalVotes))
}

bool:TestVoteDelay(client)
{
 	new delay = CheckVoteDelay()
 	
 	if (delay > 0)
 	{
 		if (delay > 60)
 		{
 			ReplyToCommand(client, "%s Vote delay: %i mins", PLUGIN_PRINT_NAME, delay % 60)
 		}
 		else
 		{
 			ReplyToCommand(client, "%s Vote delay: %i secs", PLUGIN_PRINT_NAME, delay)
 		}
 		
 		return false
 	}
 	
	return true
}