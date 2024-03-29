#pragma semicolon 1

#include <bTimes-core>

public Plugin myinfo = 
{
    name = "[bTimes] Checkpoints",
    author = "blacky",
    description = "Checkpoints plugin for the timer",
    version = VERSION,
    url = "http://steamcommunity.com/id/blaackyy/"
}

#include <sdktools>
#include <sourcemod>
#include <bTimes-timer>
#include <bTimes-random>
#include <bTimes-zones>
#include <smlib/entities>

#pragma newdecls required

#define MAX_CP 20

enum
{
    GameType_CSS,
    GameType_CSGO
};

int g_GameType;

float g_cp[MAXPLAYERS+1][MAX_CP][3][3];
int g_cpcount[MAXPLAYERS+1];

bool g_UsePos[MAXPLAYERS+1] = {true, ...};
bool g_UseVel[MAXPLAYERS+1] = {true, ...};
bool g_UseAng[MAXPLAYERS+1] = {true, ...};

int g_LastUsed[MAXPLAYERS+1];
bool g_HasLastUsed[MAXPLAYERS+1];
    
int g_LastSaved[MAXPLAYERS+1];
bool g_HasLastSaved[MAXPLAYERS+1];
    
bool g_BlockTpTo[MAXPLAYERS+1][MAXPLAYERS+1];

char g_msg_start[128],
    g_msg_varcol[128],
    g_msg_textcol[128];
    
// Cvars
ConVar g_hAllowCp;

public void OnPluginStart()
{
    char sGame[64];
    GetGameFolderName(sGame, sizeof(sGame));
    
    if(StrEqual(sGame, "cstrike"))
        g_GameType = GameType_CSS;
    else if(StrEqual(sGame, "csgo"))
        g_GameType = GameType_CSGO;
    else
        SetFailState("This timer does not support this game (%s)", sGame);
    
    // Cvars
    g_hAllowCp = CreateConVar("timer_allowcp", "1", "Allows players to use the checkpoint plugin's features.", 0, true, 0.0, true, 1.0);
    
    AutoExecConfig(true, "cp", "timer");
    
    // Commands
    RegConsoleCmdEx("sm_cp", SM_CP, "Opens the checkpoint menu.");
    RegConsoleCmdEx("sm_checkpoint", SM_CP, "Opens the checkpoint menu.");
    RegConsoleCmdEx("sm_tele", SM_Tele, "Teleports you to the specified checkpoint.");
    RegConsoleCmdEx("sm_tp", SM_Tele, "Teleports you to the specified checkpoint.");
    RegConsoleCmdEx("sm_save", SM_Save, "Saves a int checkpoint.");
    RegConsoleCmdEx("sm_tpto", SM_TpTo, "Teleports you to a player.");
    
    // Makes FindTarget() work properly
    LoadTranslations("common.phrases");
}

public void OnClientPutInServer(int client)
{
    g_cpcount[client] = 0;
    
    for(int i=1; i<=MaxClients; i++)
    {
        g_BlockTpTo[i][client] = false;
    }
}

public void OnTimerChatChanged(int MessageType, char[] Message)
{
    if(MessageType == 0)
    {
        Format(g_msg_start, sizeof(g_msg_start), Message);
        ReplaceMessage(g_msg_start, sizeof(g_msg_start));
    }
    else if(MessageType == 1)
    {
        Format(g_msg_varcol, sizeof(g_msg_varcol), Message);
        ReplaceMessage(g_msg_varcol, sizeof(g_msg_varcol));
    }
    else if(MessageType == 2)
    {
        Format(g_msg_textcol, sizeof(g_msg_textcol), Message);
        ReplaceMessage(g_msg_textcol, sizeof(g_msg_textcol));
    }
}

void ReplaceMessage(char[] message, int maxlength)
{
    if(g_GameType == GameType_CSS)
    {
        ReplaceString(message, maxlength, "^", "\x07", false);
    }
    else if(g_GameType == GameType_CSGO)
    {
        ReplaceString(message, maxlength, "^A", "\x0A");
        ReplaceString(message, maxlength, "^1", "\x01");
        ReplaceString(message, maxlength, "^2", "\x02");
        ReplaceString(message, maxlength, "^3", "\x03");
        ReplaceString(message, maxlength, "^4", "\x04");
        ReplaceString(message, maxlength, "^5", "\x05");
        ReplaceString(message, maxlength, "^6", "\x06");
        ReplaceString(message, maxlength, "^7", "\x07");
    }
}

public Action SM_TpTo(int client, int args)
{
    if(g_hAllowCp.BoolValue)
    {
        if(IsPlayerAlive(client))
        {
            if(args == 0)
            {
                OpenTpToMenu(client);
            }
            else
            {
                char argString[250];
                GetCmdArgString(argString, sizeof(argString));
                int target = FindTarget(client, argString, false, false);
                
                if(client != target)
                {
                    if(target != -1)
                    {
                        if(IsPlayerAlive(target))
                        {
                            if(IsFakeClient(target))
                            {
                                float pos[3];
                                GetEntPropVector(target, Prop_Send, "m_vecOrigin", pos);
                                
                                StopTimer(client);
                                TeleportEntity(client, pos, NULL_VECTOR, NULL_VECTOR);
                            }
                            else
                            {
                                SendTpToRequest(client, target);
                            }
                        }
                        else
                        {
                            PrintColorText(client, "%s%sTarget not alive.",
                                g_msg_start,
                                g_msg_textcol);
                        }
                    }
                    else
                    {
                        OpenTpToMenu(client);
                    }
                }
                else
                {
                    PrintColorText(client, "%s%sYou can't target yourself.",
                        g_msg_start,
                        g_msg_textcol);
                }
            }
        }
        else
        {
            PrintColorText(client, "%s%sYou must be alive to use the sm_tpto command.",
                g_msg_start,
                g_msg_textcol);
        }
    }
    
    return Plugin_Handled;
}

void OpenTpToMenu(int client)
{
    Menu menu = new Menu(Menu_Tpto);
    menu.SetTitle("Select player to teleport to");

    char sTarget[MAX_NAME_LENGTH];
    char sInfo[8];
    for(int target = 1; target <= MaxClients; target++)
    {
        if(target != client && IsClientInGame(target))
        {
            GetClientName(target, sTarget, sizeof(sTarget));
            IntToString(GetClientUserId(target), sInfo, sizeof(sInfo));
            menu.AddItem(sInfo, sTarget);
        }
    }

    menu.ExitBackButton = true;
    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_Tpto(Menu menu, MenuAction action, int client, int param2)
{
    if(action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));
        
        int target = GetClientOfUserId(StringToInt(info));
        if(target != 0)
        {
            if(IsFakeClient(target))
            {
                float vPos[3];
                Entity_GetAbsOrigin(target, vPos);
                
                StopTimer(client);
                TeleportEntity(client, vPos, NULL_VECTOR, NULL_VECTOR);
            }
            else
            {
                SendTpToRequest(client, target);
            }
        }
        else
        {
            PrintColorText(client, "%s%sTarget not in game.",
                g_msg_start,
                g_msg_textcol);
        }
    }
    else if (action == MenuAction_End)
        delete menu;
}

void SendTpToRequest(int client, int target)
{
    if(g_BlockTpTo[target][client] == false)
    {
        Menu menu = new Menu(Menu_TpRequest);
        
        char sInfo[16];
        int UserId = GetClientUserId(client);
        
        menu.SetTitle("%N wants to teleport to you", client);
        
        Format(sInfo, sizeof(sInfo), "%d;a", UserId);
        menu.AddItem(sInfo, "Accept");
        
        Format(sInfo, sizeof(sInfo), "%d;d", UserId);
        menu.AddItem(sInfo, "Deny");
        
        Format(sInfo, sizeof(sInfo), "%d;b", UserId);
        menu.AddItem(sInfo, "Deny & Block");
        
        menu.Display(target, 20);
    }
    else
    {
        PrintColorText(client, "%s%s%N %sblocked all tpto requests from you.",
            g_msg_start,
            g_msg_varcol,
            target,
            g_msg_textcol);
    }
}

public int Menu_TpRequest(Menu menu, MenuAction action, int param1, int param2)
{
    if(action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));
        
        char sInfoExploded[2][16];
        ExplodeString(info, ";", sInfoExploded, 2, 16);
        
        int client = GetClientOfUserId(StringToInt(sInfoExploded[0]));
        
        if(client != 0)
        {
            if(sInfoExploded[1][0] == 'a') // accept
            {
                float vPos[3];
                Entity_GetAbsOrigin(param1, vPos);
                
                StopTimer(client);
                TeleportEntity(client, vPos, NULL_VECTOR, NULL_VECTOR);
                
                PrintColorText(client, "%s%s%N %saccepted your request.",
                    g_msg_start,
                    g_msg_varcol,
                    param1,
                    g_msg_textcol);
            }
            else if(sInfoExploded[1][0] == 'd') // deny
            {
                PrintColorText(client, "%s%s%N %sdenied your request.",
                    g_msg_start,
                    g_msg_varcol,
                    param1,
                    g_msg_textcol);
            }
            else if(sInfoExploded[1][0] == 'b') // deny and block
            {                
                g_BlockTpTo[param1][client] = true;
                PrintColorText(client, "%s%s%N %sdenied denied your request and blocked future requests from you.",
                    g_msg_start,
                    g_msg_varcol,
                    param1,
                    g_msg_textcol);
            }
        }
        else
        {
            PrintColorText(param1, "%s%sThe tp requester is no longer in game.",
                g_msg_start,
                g_msg_textcol);
        }
    }
    else if(action == MenuAction_End)
        delete menu;
}

public Action SM_CP(int client, int args)
{
    if(g_hAllowCp.BoolValue)
    {
        OpenCheckpointMenu(client);
    }
    
    return Plugin_Handled;
}

void OpenCheckpointMenu(int client)
{
    Menu menu = new Menu(Menu_Checkpoint);
    
    menu.SetTitle("Checkpoint menu");
    menu.AddItem("Save", "Save");
    menu.AddItem("Teleport", "Teleport");
    menu.AddItem("Delete", "Delete");
    menu.AddItem("usepos", g_UsePos[client]?"Use position: Yes":"Use position: No");
    menu.AddItem("usevel", g_UseVel[client]?"Use velocity: Yes":"Use velocity: No");
    menu.AddItem("useang", g_UseAng[client]?"Use angles: Yes":"Use angles: No");
    menu.AddItem("Noclip", "Noclip");
    
    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_Checkpoint(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));
        
        if(StrEqual(info, "Save"))
        {
            SaveCheckpoint(param1);
            OpenCheckpointMenu(param1);
        }
        else if(StrEqual(info, "Teleport"))
        {
            OpenTeleportMenu(param1);
        }
        else if(StrEqual(info, "Delete"))
        {
            OpenDeleteMenu(param1);
        }
        else if(StrEqual(info, "usepos"))
        {
            g_UsePos[param1] = !g_UsePos[param1];
            OpenCheckpointMenu(param1);
        }
        else if(StrEqual(info, "usevel"))
        {
            g_UseVel[param1] = !g_UseVel[param1];
            OpenCheckpointMenu(param1);
        }
        else if(StrEqual(info, "useang"))
        {
            g_UseAng[param1] = !g_UseAng[param1];
            OpenCheckpointMenu(param1);
        }
        else if(StrEqual(info, "Noclip"))
        {
            FakeClientCommand(param1, "sm_practice");
            OpenCheckpointMenu(param1);
        }
    }
    else if (action == MenuAction_End)
        delete menu;
}

void OpenTeleportMenu(int client)
{
    Menu menu = new Menu(Menu_Teleport);
    menu.SetTitle("Teleport");
    menu.AddItem("lastused", "Last used");
    menu.AddItem("lastsaved", "Last saved");
    
    char tpString[8];
    char infoString[8];
    for(int i=0; i < g_cpcount[client]; i++)
    {
        Format(tpString, sizeof(tpString), "CP %d", i+1);
        Format(infoString, sizeof(infoString), "%d", i);
        menu.AddItem(infoString, tpString);
    }
    
    menu.ExitBackButton = true;
    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_Teleport(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));
        
        if(StrEqual(info, "lastused"))
        {
            TeleportToLastUsed(param1);
            OpenTeleportMenu(param1);
        }
        else if(StrEqual(info, "lastsaved"))
        {
            TeleportToLastSaved(param1);
            OpenTeleportMenu(param1);
        }
        else
        {
            char infoGuess[8];
            for(int i=0; i < g_cpcount[param1]; i++)
            {
                Format(infoGuess, sizeof(infoGuess), "%d", i);
                if(StrEqual(info, infoGuess))
                {
                    TeleportToCheckpoint(param1, i);
                    OpenTeleportMenu(param1);
                    break;
                }
            }
        }
    }
    else if (action == MenuAction_Cancel)
    {
        if(param2 == MenuCancel_ExitBack)
        {
            OpenCheckpointMenu(param1);
        }
    }
    else if (action == MenuAction_End)
        delete menu;
}

void OpenDeleteMenu(int client)
{
    if(g_cpcount[client] != 0)
    {
        Menu menu = new Menu(Menu_Delete);
        menu.SetTitle("Delete");
        
        char display[16];
        char info[8];
        for(int i=0; i < g_cpcount[client]; i++)
        {
            Format(display, sizeof(display), "Delete %d", i+1);
            IntToString(i, info, sizeof(info));
            menu.AddItem(info, display);
        }
        
        menu.ExitBackButton = true;
        menu.ExitButton = true;
        menu.Display(client, MENU_TIME_FOREVER);
    }
    else
    {
        PrintColorText(client, "%s%sYou have no checkpoints saved.",
            g_msg_start,
            g_msg_textcol);
        OpenCheckpointMenu(client);
    }
    
    
}

public int Menu_Delete(Menu menu, MenuAction action, int param1, int param2)
{
    if(action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));
        
        DeleteCheckpoint(param1, StringToInt(info));
        OpenDeleteMenu(param1);
    }
    else if(action == MenuAction_Cancel)
    {
        if(param2 == MenuCancel_ExitBack)
        {
            OpenCheckpointMenu(param1);
        }
    }
    else if(action == MenuAction_End)
        delete menu;
    
}

public Action SM_Tele(int client, int args)
{
    if(args != 0)
    {
        char sArg[255];
        GetCmdArgString(sArg, sizeof(sArg));
        
        int checkpoint = StringToInt(sArg) - 1;
        TeleportToCheckpoint(client, checkpoint);
    }
    else
    {
        ReplyToCommand(client, "[SM] Usage: sm_tele <Checkpoint number>");
    }
    
    return Plugin_Handled;
}

public Action SM_Save(int client, int argS)
{
    SaveCheckpoint(client);
    
    return Plugin_Handled;
}

void SaveCheckpoint(int client)
{
    if(g_hAllowCp.BoolValue)
    {
        if(g_cpcount[client] < MAX_CP)
        {
            Entity_GetAbsOrigin(client, g_cp[client][g_cpcount[client]][0]);
            Entity_GetAbsVelocity(client, g_cp[client][g_cpcount[client]][1]);
            GetClientEyeAngles(client, g_cp[client][g_cpcount[client]][2]);
            
            g_HasLastSaved[client] = true;
            g_LastSaved[client]    = g_cpcount[client];
            
            g_cpcount[client]++;
            
            PrintColorText(client, "%s%sCheckpoint %s%d%s saved.", 
                g_msg_start,
                g_msg_textcol,
                g_msg_varcol,
                g_cpcount[client],
                g_msg_textcol);
        }
        else
        {
            PrintColorText(client, "%s%sYou have too many checkpoints.",
                g_msg_start,
                g_msg_textcol);
        }
    }
}

void DeleteCheckpoint(int client, int cpnum)
{
    if(0 <= cpnum <= g_cpcount[client])
    {
        for(int i=cpnum+1; i<MAX_CP; i++)
            for(int i2=0; i2<3; i2++)
                for(int i3=0; i3<3; i3++)
                    g_cp[client][i-1][i2][i3] = g_cp[client][i][i2][i3];
        g_cpcount[client]--;
        
        if(cpnum == g_LastUsed[client] || g_cpcount[client] < g_LastUsed[client])
            g_HasLastUsed[client] = false;
        else if(cpnum < g_LastUsed[client])
            g_LastUsed[client]--;
        
        if(cpnum == g_LastSaved[client] || g_cpcount[client] < g_LastSaved[client])
            g_HasLastSaved[client] = false;
        else if(cpnum < g_LastSaved[client])
            g_LastSaved[client]--;
            
    }
    else
    {
        PrintColorText(client, "%s%sCheckpoint %s%d%s doesn't exist", 
            g_msg_start,
            g_msg_textcol,
            g_msg_varcol,
            cpnum+1,
            g_msg_textcol);
    }
}

void TeleportToCheckpoint(int client, int cpnum)
{
    if(g_hAllowCp.BoolValue)
    {
        if(0 <= cpnum < g_cpcount[client])
        {
            float vPos[3];
            for(int i; i < 3; i++)
                vPos[i] = g_cp[client][cpnum][0][i];
            vPos[2] += 5.0;
            
            StopTimer(client);
            //SetEntityFlags(client, GetEntityFlags(client) & ~FL_ONGROUND);
            
            // Prevent using velocity with checkpoints inside start zones so players can't abuse it to beat times
            if(g_UsePos[client] == false)
            {
                float vClientPos[3];
                Entity_GetAbsOrigin(client, vClientPos);
                
                if(Timer_InsideZone(client, MAIN_START) != -1 || Timer_InsideZone(client, BONUS_START) != -1)
                {
                    TeleportEntity(client, 
                        g_UsePos[client]?g_cp[client][cpnum][0]:NULL_VECTOR, 
                        g_UseAng[client]?g_cp[client][cpnum][2]:NULL_VECTOR, 
                        view_as<float>({0.0, 0.0, 0.0}));
                }
                else
                {
                    TeleportEntity(client, 
                        g_UsePos[client]?g_cp[client][cpnum][0]:NULL_VECTOR, 
                        g_UseAng[client]?g_cp[client][cpnum][2]:NULL_VECTOR, 
                        g_UseVel[client]?g_cp[client][cpnum][1]:NULL_VECTOR);
                }
            }
            else
            {
                if(!Timer_IsPointInsideZone(vPos, MAIN_START, 0) && !Timer_IsPointInsideZone(vPos, BONUS_START, 0))
                {
                    TeleportEntity(client, 
                        g_UsePos[client]?g_cp[client][cpnum][0]:NULL_VECTOR, 
                        g_UseAng[client]?g_cp[client][cpnum][2]:NULL_VECTOR, 
                        g_UseVel[client]?g_cp[client][cpnum][1]:NULL_VECTOR);
                }
                else
                {
                    TeleportEntity(client, 
                        g_UsePos[client]?g_cp[client][cpnum][0]:NULL_VECTOR, 
                        g_UseAng[client]?g_cp[client][cpnum][2]:NULL_VECTOR, 
                        view_as<float>({0.0, 0.0, 0.0}));
                }
            }
            
            g_HasLastUsed[client] = true;
            g_LastUsed[client]    = cpnum;
        }
        else
        {
            PrintColorText(client, "%s%sCheckpoint %s%d%s doesn't exist", 
                g_msg_start,
                g_msg_textcol,
                g_msg_varcol,
                cpnum+1,
                g_msg_textcol);
        }
    }
}

void TeleportToLastUsed(int client)
{
    if(g_hAllowCp.BoolValue)
    {
        if(g_HasLastUsed[client] == true)
        {
            TeleportToCheckpoint(client, g_LastUsed[client]);
        }
        else
        {
            PrintColorText(client, "%s%sYou have no last used checkpoint.",
                g_msg_start,
                g_msg_textcol);
        }
    }
}

void TeleportToLastSaved(int client)
{
    if(g_hAllowCp.BoolValue)
    {
        if(g_HasLastSaved[client] == true)
        {
            TeleportToCheckpoint(client, g_LastSaved[client]);
        }
        else
        {
            PrintColorText(client, "%s%sYou have no last saved checkpoint.",
                g_msg_start,
                g_msg_textcol);
        }
    }
}
