#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <vector>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "2.3.0"
#define PERMANENT_KEY 999

public Plugin myinfo = 
{
    name = "Railcannon",
    author = "hjz9188nb666",
    description = "hjz9188nb666,30rfantasynb666",
    version = PLUGIN_VERSION,
    url = "https://space.bilibili.com/535157375"
};

int g_iRailcannon[MAXPLAYERS + 1] = {-1, ...};
int g_iBeamSprite;
int g_iPlayerColor[MAXPLAYERS + 1][3];
char g_szPrefix[256] = "DocのRailcannon";
bool g_bRailcannonRemoved[MAXPLAYERS + 1];
float g_fRailcannonYaw[MAXPLAYERS + 1];
float g_fPauseEndTime[MAXPLAYERS + 1];
float g_fShootAngle[MAXPLAYERS + 1][3];

// Cookie相关Handle已移除，改用SteamID存储

bool g_bActivated[MAXPLAYERS + 1];
int g_iActivationTime[MAXPLAYERS + 1];
char g_szKeyFile[PLATFORM_MAX_PATH];
ConVar g_hKeyFile;

bool g_bShowOthersRailcannon[MAXPLAYERS + 1] = {true, ...};

// SteamID存储相关
char g_szDataFile[PLATFORM_MAX_PATH];
ConVar g_hDataFile;

public void OnPluginStart()
{
    g_hKeyFile = CreateConVar("sm_railcannon_keyfile", "railcannon_keys.cfg", "卡密文件路径（在sourcemod/configs/目录下）", FCVAR_NONE);
    g_hDataFile = CreateConVar("sm_railcannon_datafile", "railcannon_steamid_data.cfg", "SteamID数据文件路径（在sourcemod/configs/目录下）", FCVAR_NONE);
    
    char sFile[64];
    g_hKeyFile.GetString(sFile, sizeof(sFile));
    BuildPath(Path_SM, g_szKeyFile, sizeof(g_szKeyFile), "configs/%s", sFile);
    
    char sDataFile[64];
    g_hDataFile.GetString(sDataFile, sizeof(sDataFile));
    BuildPath(Path_SM, g_szDataFile, sizeof(g_szDataFile), "configs/%s", sDataFile);
    
    char dirPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, dirPath, sizeof(dirPath), "configs");
    if (!DirExists(dirPath))
    {
        CreateDirectory(dirPath, 509);
    }
    
    if (!FileExists(g_szKeyFile))
    {
        KeyValues kv = new KeyValues("Keys");
        if (kv.ExportToFile(g_szKeyFile))
        {
            LogMessage("已创建卡密文件: %s", g_szKeyFile);
        }
        else
        {
            LogError("无法创建卡密文件: %s", g_szKeyFile);
        }
        delete kv;
    }
    
    if (!FileExists(g_szDataFile))
    {
        KeyValues kv = new KeyValues("SteamIDData");
        if (kv.ExportToFile(g_szDataFile))
        {
            LogMessage("已创建SteamID数据文件: %s", g_szDataFile);
        }
        else
        {
            LogError("无法创建SteamID数据文件: %s", g_szDataFile);
        }
        delete kv;
    }
    
    RegConsoleCmd("sm_rc", Command_Railcannon, "打开浮游炮菜单");
    RegConsoleCmd("sm_rcl", Command_RailcannonColor, "设置浮游炮颜色");
    
    RegAdminCmd("sm_rcckey", Command_GenerateKey, ADMFLAG_ROOT, "生成浮游炮激活卡密");
    RegConsoleCmd("sm_rckey", Command_Activate, "激活浮游炮功能");
    
    RegAdminCmd("sm_banfyp", Command_BanFYP, ADMFLAG_ROOT, "封禁玩家浮游炮");
    
    HookEvent("bullet_impact", Event_BulletImpact);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("player_spawn", Event_PlayerSpawn);
    
    // Cookie注册已移除，改用SteamID存储
    
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            LoadClientData(i);
        }
    }
}

public void OnMapStart()
{
    g_iBeamSprite = PrecacheModel("materials/sprites/laserbeam.vmt");
}

public void OnClientPutInServer(int client)
{
    ResetClientData(client);
    LoadClientData(client);
}

public void OnClientDisconnect(int client)
{
    DestroyRailcannon(client);
}

// OnClientCookiesCached已移除，因为不再使用Cookie

void ResetClientData(int client)
{
    g_iRailcannon[client] = -1;
    g_fRailcannonYaw[client] = 0.0;
    g_fPauseEndTime[client] = 0.0;
    g_fShootAngle[client][0] = 0.0;
    g_fShootAngle[client][1] = 0.0;
    g_fShootAngle[client][2] = 0.0;
    g_bRailcannonRemoved[client] = false;
    
    g_bActivated[client] = false;
    g_iActivationTime[client] = 0;
    
    g_bShowOthersRailcannon[client] = true;
}

void LoadClientData(int client)
{
    LoadClientColor(client);
    LoadRemovedState(client);
    LoadActivationState(client);
    LoadShowOthersState(client);
}

void LoadShowOthersState(int client)
{
    char sValue[8];
    LoadClientDataBySteamID(client, "show_others", sValue, sizeof(sValue));
    
    if (strlen(sValue) > 0)
    {
        g_bShowOthersRailcannon[client] = view_as<bool>(StringToInt(sValue));
    }
    else
    {
        g_bShowOthersRailcannon[client] = true;
    }
}

void SaveShowOthersState(int client)
{
    char sValue[8];
    IntToString(view_as<int>(g_bShowOthersRailcannon[client]), sValue, sizeof(sValue));
    SaveClientDataBySteamID(client, "show_others", sValue);
}

public Action Command_GenerateKey(int client, int args)
{
    if (args != 2)
    {
        ReplyToCommand(client, "[\x0E%s\x01] 用法: !rcckey \x04天数(999=永久) 数量", g_szPrefix);
        ReplyToCommand(client, "[\x0E%s\x01] 示例: !rcckey \x0430 5  -> 生成5个30天有效的卡密", g_szPrefix);
        ReplyToCommand(client, "[\x0E%s\x01] 示例: !rcckey \x04999 1 -> 生成1个永久卡密", g_szPrefix);
        return Plugin_Handled;
    }
    
    char sDays[12], sCount[12];
    GetCmdArg(1, sDays, sizeof(sDays));
    GetCmdArg(2, sCount, sizeof(sCount));
    
    int days = StringToInt(sDays);
    int count = StringToInt(sCount);
    
    if (days <= 0 || count <= 0)
    {
        ReplyToCommand(client, "[\x0E%s\x01] 天数(%d)和数量(%d)必须是大于0的整数", g_szPrefix, days, count);
        return Plugin_Handled;
    }
    
    char keys[256][32];
    int generated = GenerateKeys(days, count, keys, sizeof(keys));
    
    if (generated == 0)
    {
        ReplyToCommand(client, "[\x0E%s\x01] 卡密生成失败，请检查文件权限", g_szPrefix);
        return Plugin_Handled;
    }
    
    ReplyToCommand(client, "[\x0E%s\x01] 已生成 %d 个卡密:", g_szPrefix, generated);
    for (int i = 0; i < generated; i++)
    {
        ReplyToCommand(client, "卡密 %d: %s", i+1, keys[i]);
    }
    
    if (days == PERMANENT_KEY)
    {
        ReplyToCommand(client, "[\x0E%s\x01] 类型: \x04永久激活", g_szPrefix);
    }
    else
    {
        char sExpire[32];
        FormatTime(sExpire, sizeof(sExpire), "%Y-%m-%d %H:%M", GetTime() + (days * 86400));
        ReplyToCommand(client, "[\x0E%s\x01] 有效期至: \x04%s", g_szPrefix, sExpire);
    }
    
    return Plugin_Handled;
}

public Action Command_Activate(int client, int args)
{
    if (args < 1)
    {
        PrintToChat(client, "[\x0E%s\x01] 用法: !rckey \x04<卡密>", g_szPrefix);
        return Plugin_Handled;
    }
    
    char key[32];
    GetCmdArg(1, key, sizeof(key));
    
    KeyValues kv = new KeyValues("Keys");
    if (!kv.ImportFromFile(g_szKeyFile))
    {
        PrintToChat(client, "[\x0E%s\x01] 激活系统错误，请联系管理员", g_szPrefix);
        delete kv;
        return Plugin_Handled;
    }
    
    if (kv.JumpToKey(key))
    {
        int days = kv.GetNum("days", 0);
        if (days <= 0)
        {
            PrintToChat(client, "[\x0E%s\x01] 该卡密已失效", g_szPrefix);
            delete kv;
            return Plugin_Handled;
        }
        
        if (days == PERMANENT_KEY)
        {
            g_iActivationTime[client] = -1;
            PrintToChat(client, "[\x0E%s\x01] 恭喜！您已获得\x04永久浮游炮\x01权限", g_szPrefix);
        }
        else
        {
            g_iActivationTime[client] = GetTime() + (days * 86400);
            
            char sExpire[32];
            FormatTime(sExpire, sizeof(sExpire), "%Y-%m-%d %H:%M", g_iActivationTime[client]);
            PrintToChat(client, "[\x0E%s\x01] 激活成功！有效期至: \x04%s", g_szPrefix, sExpire);
        }
        
        g_bActivated[client] = true;
        
        char sValue[32];
        IntToString(g_iActivationTime[client], sValue, sizeof(sValue));
        SaveClientDataBySteamID(client, "activation_time", sValue);
        
        kv.DeleteThis();
        kv.Rewind();
        kv.ExportToFile(g_szKeyFile);
        
        if (IsClientInGame(client) && IsPlayerAlive(client) && !g_bRailcannonRemoved[client])
        {
            CreateRailcannon(client);
        }
    }
    else
    {
        PrintToChat(client, "[\x0E%s\x01] 无效的卡密", g_szPrefix);
    }
    
    delete kv;
    return Plugin_Handled;
}

public Action Command_BanFYP(int client, int args)
{
    if (client == 0)
    {
        PrintToServer("此命令只能在游戏中使用");
        return Plugin_Handled;
    }
    
    Menu menu = new Menu(MenuHandler_BanFYP);
    menu.SetTitle("选择要封禁浮游炮的玩家");
    
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            char userid[12], name[64];
            IntToString(GetClientUserId(i), userid, sizeof(userid));
            GetClientName(i, name, sizeof(name));
            
            char status[64];
            GetActivationStatus(i, status, sizeof(status));
            Format(name, sizeof(name), "%s (%s)", name, status);
            
            menu.AddItem(userid, name);
        }
    }
    
    if (menu.ItemCount == 0)
    {
        menu.AddItem("", "没有可封禁的玩家", ITEMDRAW_DISABLED);
    }
    
    menu.ExitButton = true;
    menu.Display(client, 20);
    
    return Plugin_Handled;
}

public int MenuHandler_BanFYP(Menu menu, MenuAction action, int client, int param)
{
    if (action == MenuAction_Select)
    {
        char info[12];
        menu.GetItem(param, info, sizeof(info));
        int target = GetClientOfUserId(StringToInt(info));
        
        if (IsClientValid(target))
        {
            DestroyRailcannon(target);
            g_bRailcannonRemoved[target] = true;
            SaveRemovedState(target);
            
            g_bActivated[target] = false;
            g_iActivationTime[target] = 0;
            SaveClientDataBySteamID(target, "activation_time", "0");
            
            char adminName[64], targetName[64];
            GetClientName(client, adminName, sizeof(adminName));
            GetClientName(target, targetName, sizeof(targetName));
            
            PrintToChatAll("[\x0E%s\x01] 管理员 \x04%s \x01已封禁 \x06%s \x01的浮游炮权限", 
                          g_szPrefix, adminName, targetName);
        }
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }
    
    return 0;
}

int GenerateKeys(int days, int count, char[][] keys, int maxKeys)
{
    KeyValues kv = new KeyValues("Keys");
    if (!kv.ImportFromFile(g_szKeyFile))
    {
        kv = new KeyValues("Keys");
        kv.ExportToFile(g_szKeyFile);
    }
    
    int generated = 0;
    
    for (int i = 0; i < count && generated < maxKeys; i++)
    {
        char key[32];
        GenerateRandomKey(key, sizeof(key));
        
        if (!kv.JumpToKey(key, false))
        {
            kv.JumpToKey(key, true);
            kv.SetNum("days", days);
            kv.Rewind();
            
            strcopy(keys[generated], 32, key);
            generated++;
        }
    }
    
    kv.ExportToFile(g_szKeyFile);
    delete kv;
    return generated;
}

void GenerateRandomKey(char[] buffer, int length)
{
    char chars[] = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    for (int i = 0; i < length - 1; i++)
    {
        buffer[i] = chars[GetRandomInt(0, sizeof(chars) - 2)];
    }
    buffer[length - 1] = '\0';
}

void LoadActivationState(int client)
{
    char sValue[32];
    LoadClientDataBySteamID(client, "activation_time", sValue, sizeof(sValue));
    
    if (strlen(sValue) > 0)
    {
        g_iActivationTime[client] = StringToInt(sValue);
        
        if (g_iActivationTime[client] == -1)
        {
            g_bActivated[client] = true;
        }
        else if (g_iActivationTime[client] > 0)
        {
            g_bActivated[client] = (GetTime() < g_iActivationTime[client]);
        }
        else
        {
            g_bActivated[client] = false;
        }
    }
    else
    {
        g_bActivated[client] = false;
        g_iActivationTime[client] = 0;
    }
}

bool CheckActivation(int client)
{
    if (g_iActivationTime[client] == -1) 
        return true;
    
    if (g_iActivationTime[client] > 0 && GetTime() < g_iActivationTime[client])
        return true;
    
    if (g_bActivated[client] && g_iActivationTime[client] > 0 && GetTime() >= g_iActivationTime[client])
    {
        g_bActivated[client] = false;
        char sValue[32];
        Format(sValue, sizeof(sValue), "%d", g_iActivationTime[client]);
        SaveClientDataBySteamID(client, "activation_time", sValue);
    }
    
    return false;
}

void GetActivationStatus(int client, char[] buffer, int length)
{
    if (g_iActivationTime[client] == -1)
    {
        Format(buffer, length, "永久激活");
    }
    else if (g_iActivationTime[client] > 0)
    {
        char sExpire[32];
        FormatTime(sExpire, sizeof(sExpire), "%Y-%m-%d %H:%M", g_iActivationTime[client]);
        Format(buffer, length, "到期: %s", sExpire);
    }
    else
    {
        Format(buffer, length, "未激活");
    }
}

public Action Command_Railcannon(int client, int args)
{
    if (client == 0 || !IsClientInGame(client))
    {
        return Plugin_Handled;
    }
    
    if (!CheckActivation(client))
    {
        PrintToChat(client, "[\x0E%s\x01] 请先激活浮游炮功能！使用\x04 !rckey [卡密]\x01激活", g_szPrefix);
        return Plugin_Handled;
    }
    
    char status[64];
    GetActivationStatus(client, status, sizeof(status));
    
    Menu menu = new Menu(MenuHandler_Railcannon);
    menu.SetTitle("浮游炮控制面板 [%s]", status);
    menu.AddItem("create", "创建/重新加载浮游炮");
    menu.AddItem("color", "设置浮游炮颜色");
    menu.AddItem("remove", "移除浮游炮");
    menu.AddItem("showothers", g_bShowOthersRailcannon[client] ? "隐藏他人浮游炮" : "显示他人浮游炮");
    menu.ExitButton = true;
    menu.Display(client, 20);
    
    return Plugin_Handled;
}

public int MenuHandler_Railcannon(Menu menu, MenuAction action, int client, int param)
{
    if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param, info, sizeof(info));
        
        if (StrEqual(info, "create"))
        {
            g_bRailcannonRemoved[client] = false;
            SaveRemovedState(client);
            CreateRailcannon(client);
            PrintToChat(client, "[\x0E%s\x01] 已创建浮游炮", g_szPrefix);
        }
        else if (StrEqual(info, "color"))
        {
            PrintToChat(client, "[\x0E%s\x01] 请输入 \x04!rcl R G B\x01 设置颜色 (0-255)", g_szPrefix);
        }
        else if (StrEqual(info, "remove"))
        {
            DestroyRailcannon(client);
            g_bRailcannonRemoved[client] = true;
            SaveRemovedState(client);
            PrintToChat(client, "[\x0E%s\x01] 已移除浮游炮", g_szPrefix);
        }
        else if (StrEqual(info, "showothers"))
        {
            g_bShowOthersRailcannon[client] = !g_bShowOthersRailcannon[client];
            SaveShowOthersState(client);
            
            if (g_bShowOthersRailcannon[client])
            {
                PrintToChat(client, "[\x0E%s\x01] 已设置为\x04显示\x01其他人的浮游炮", g_szPrefix);
            }
            else
            {
                PrintToChat(client, "[\x0E%s\x01] 已设置为\x02隐藏\x01其他人的浮游炮", g_szPrefix);
            }
            
            // 重新打开菜单
            Command_Railcannon(client, 0);
        }
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }
    
    return 0;
}

public Action Command_RailcannonColor(int client, int args)
{
    if (client == 0 || !IsClientInGame(client))
    {
        return Plugin_Handled;
    }
    
    if (args != 3)
    {
        PrintToChat(client, "[\x0E%s\x01] 用法: !rcl \x04R G B", g_szPrefix);
        PrintToChat(client, "[\x0E%s\x01] 示例: !rcl \x04255 50 150", g_szPrefix);
        return Plugin_Handled;
    }
    
    char sRed[32], sGreen[32], sBlue[32];
    GetCmdArg(1, sRed, sizeof(sRed));
    GetCmdArg(2, sGreen, sizeof(sGreen));
    GetCmdArg(3, sBlue, sizeof(sBlue));
    
    int red = ClampColor(StringToInt(sRed));
    int green = ClampColor(StringToInt(sGreen));
    int blue = ClampColor(StringToInt(sBlue));
    
    g_iPlayerColor[client][0] = red;
    g_iPlayerColor[client][1] = green;
    g_iPlayerColor[client][2] = blue;
    
    SaveClientColor(client);
    PrintToChat(client, "[\x0E%s\x01] 颜色已设置为: \x07%i \x06%i \x05%i", g_szPrefix, red, green, blue);
    
    if (g_iRailcannon[client] != -1 && IsValidEntity(g_iRailcannon[client]))
    {
        SetRailcannonColor(client);
    }
    
    return Plugin_Handled;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    
    if (!IsClientValid(client) || !IsPlayerAlive(client))
    {
        return Plugin_Continue;
    }
    
    if (!CheckActivation(client))
    {
        return Plugin_Continue;
    }
    
    LoadClientData(client);
    
    if (!g_bRailcannonRemoved[client])
    {
        CreateTimer(0.1, Timer_CreateRailcannon, GetClientUserId(client));
    }
    
    return Plugin_Continue;
}

public Action Timer_CreateRailcannon(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    
    if (IsClientValid(client) && IsPlayerAlive(client))
    {
        CreateRailcannon(client);
    }
    
    return Plugin_Stop;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    DestroyRailcannon(client);
    return Plugin_Continue;
}

public Action Event_BulletImpact(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    
    if (!IsClientValid(client) || !IsPlayerAlive(client))
    {
        return Plugin_Continue;
    }
    
    if (g_iRailcannon[client] == -1 || !IsValidEntity(g_iRailcannon[client]))
    {
        return Plugin_Continue;
    }
    
    float vBullet[3];
    vBullet[0] = event.GetFloat("x");
    vBullet[1] = event.GetFloat("y");
    vBullet[2] = event.GetFloat("z");
    
    float vRCOrigin[3];
    GetEntPropVector(g_iRailcannon[client], Prop_Send, "m_vecOrigin", vRCOrigin);
    
    float vDirection[3];
    SubtractVectors(vBullet, vRCOrigin, vDirection);
    NormalizeVector(vDirection, vDirection);
    
    GetVectorAngles(vDirection, g_fShootAngle[client]);
    
    g_fPauseEndTime[client] = GetGameTime() + 0.6;
    
    int color[4];
    color[0] = g_iPlayerColor[client][0];
    color[1] = g_iPlayerColor[client][1];
    color[2] = g_iPlayerColor[client][2];
    color[3] = 220;
    
    TE_SetupBeamPoints(
        vRCOrigin, 
        vBullet, 
        g_iBeamSprite, 
        0,
        0,
        0,
        0.5,
        35.0,
        1.2,
        5,
        0.0,
        color, 
        3
    );
    
    TE_SendToAll();
    
    return Plugin_Continue;
}

public void OnGameFrame()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientValid(client) || !IsPlayerAlive(client) || 
            g_iRailcannon[client] == -1 || !IsValidEntity(g_iRailcannon[client]))
        {
            continue;
        }
        
        // 更新浮游炮位置和角度
        float vecOrigin[3];
        GetClientEyePosition(client, vecOrigin);
        vecOrigin[2] += (GetClientButtons(client) & IN_DUCK) ? 30.0 : 47.0;
        
        float vecAngle[3];
        
        if (GetGameTime() < g_fPauseEndTime[client])
        {
            vecAngle[0] = g_fShootAngle[client][0];
            vecAngle[1] = g_fShootAngle[client][1];
            vecAngle[2] = 0.0;
        }
        else
        {
            g_fRailcannonYaw[client] += 5.0;
            g_fRailcannonYaw[client] = NormalizeAngle(g_fRailcannonYaw[client]);
            
            vecAngle[0] = 0.0;
            vecAngle[1] = g_fRailcannonYaw[client];
            vecAngle[2] = 0.0;
        }
        
        TeleportEntity(g_iRailcannon[client], vecOrigin, vecAngle, NULL_VECTOR);
        
        // 设置浮游炮的可见性
        // 自己的浮游炮总是可见
        SetEntityRenderMode(g_iRailcannon[client], RENDER_TRANSTEXTURE);
        SetEntityRenderColor(g_iRailcannon[client], 
            g_iPlayerColor[client][0], 
            g_iPlayerColor[client][1], 
            g_iPlayerColor[client][2], 
            50);
    }
}

void CreateRailcannon(int client)
{
    if (!CheckActivation(client))
    {
        PrintToChat(client, "[\x0E%s\x01] 浮游炮功能未激活！使用\x04 !rckey [卡密]\x01激活", g_szPrefix);
        return;
    }
    
    DestroyRailcannon(client);
    
    int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (!IsValidEntity(weapon))
    {
        return;
    }
    
    char szModel[256];
    GetEntPropString(weapon, Prop_Data, "m_ModelName", szModel, sizeof(szModel));
    ReplaceString(szModel, sizeof(szModel), "_dropped", "", false);
    
    float vecOrigin[3];
    GetClientEyePosition(client, vecOrigin);
    vecOrigin[2] += (GetClientButtons(client) & IN_DUCK) ? 30.0 : 47.0;
    
    g_iRailcannon[client] = CreateEntityByName("prop_dynamic_glow");
    if (g_iRailcannon[client] == -1)
    {
        return;
    }
    
    DispatchKeyValue(g_iRailcannon[client], "model", szModel);
    DispatchKeyValue(g_iRailcannon[client], "disablereceiveshadows", "1");
    DispatchKeyValue(g_iRailcannon[client], "disableshadows", "1");
    DispatchKeyValue(g_iRailcannon[client], "solid", "0");
    DispatchKeyValue(g_iRailcannon[client], "spawnflags", "256");
    DispatchSpawn(g_iRailcannon[client]);
    
    SetEntProp(g_iRailcannon[client], Prop_Send, "m_CollisionGroup", 11);
    SetEntProp(g_iRailcannon[client], Prop_Send, "m_bShouldGlow", true);
    SetEntPropFloat(g_iRailcannon[client], Prop_Send, "m_flModelScale", 2.0);
    SetEntPropFloat(g_iRailcannon[client], Prop_Send, "m_flGlowMaxDist", 100000.0);
    
    SetRailcannonColor(client);
    
    TeleportEntity(g_iRailcannon[client], vecOrigin, NULL_VECTOR, NULL_VECTOR);
    SetEntPropEnt(g_iRailcannon[client], Prop_Send, "m_hOwnerEntity", client);
    
    SDKHook(client, SDKHook_WeaponSwitch, OnWeaponSwitch);
    
    g_fRailcannonYaw[client] = 0.0;
    g_fPauseEndTime[client] = 0.0;
    
    // 设置浮游炮的传输钩子，用于控制对其他玩家的可见性
    SDKHook(g_iRailcannon[client], SDKHook_SetTransmit, OnRailcannonSetTransmit);
}

public Action OnRailcannonSetTransmit(int entity, int client)
{
    // 获取浮游炮的所有者
    int owner = -1;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (g_iRailcannon[i] == entity)
        {
            owner = i;
            break;
        }
    }
    
    // 如果找不到所有者，允许传输
    if (owner == -1)
        return Plugin_Continue;
    
    // 如果是所有者自己，总是允许传输
    if (owner == client)
        return Plugin_Continue;
    
    // 如果观察者设置了显示其他人的浮游炮，允许传输
    if (g_bShowOthersRailcannon[client])
        return Plugin_Continue;
    
    // 否则阻止传输
    return Plugin_Handled;
}

void DestroyRailcannon(int client)
{
    if (g_iRailcannon[client] != -1 && IsValidEntity(g_iRailcannon[client]))
    {
        SDKUnhook(g_iRailcannon[client], SDKHook_SetTransmit, OnRailcannonSetTransmit);
        AcceptEntityInput(g_iRailcannon[client], "Kill");
    }
    
    g_iRailcannon[client] = -1;
    SDKUnhook(client, SDKHook_WeaponSwitch, OnWeaponSwitch);
}

public Action OnWeaponSwitch(int client, int weapon)
{
    if (!IsClientValid(client) || g_iRailcannon[client] == -1)
    {
        return Plugin_Continue;
    }
    
    if (IsValidEntity(weapon))
    {
        char szModel[256];
        GetEntPropString(weapon, Prop_Data, "m_ModelName", szModel, sizeof(szModel));
        ReplaceString(szModel, sizeof(szModel), "_dropped", "", false);
        
        if (IsValidEntity(g_iRailcannon[client]))
        {
            SetEntityModel(g_iRailcannon[client], szModel);
            SetRailcannonColor(client);
        }
    }
    
    return Plugin_Continue;
}

void SetRailcannonColor(int client)
{
    if (g_iRailcannon[client] != -1 && IsValidEntity(g_iRailcannon[client]))
    {
        SetEntityRenderMode(g_iRailcannon[client], RENDER_TRANSTEXTURE);
        SetEntityRenderColor(g_iRailcannon[client], 
            g_iPlayerColor[client][0], 
            g_iPlayerColor[client][1], 
            g_iPlayerColor[client][2], 
            50);
        
        SetGlowColor(g_iRailcannon[client], 
            g_iPlayerColor[client][0], 
            g_iPlayerColor[client][1], 
            g_iPlayerColor[client][2]);
    }
}

void SetGlowColor(int entity, int r, int g, int b)
{
    int colors[4];
    colors[0] = r;
    colors[1] = g;
    colors[2] = b;
    colors[3] = 255;
    
    SetVariantColor(colors);
    AcceptEntityInput(entity, "SetGlowColor");
}

float NormalizeAngle(float angle)
{
    while (angle > 360.0) angle -= 360.0;
    while (angle < 0.0) angle += 360.0;
    return angle;
}

void LoadRemovedState(int client)
{
    char sValue[8];
    LoadClientDataBySteamID(client, "removed_state", sValue, sizeof(sValue));
    
    if (strlen(sValue) > 0)
    {
        g_bRailcannonRemoved[client] = view_as<bool>(StringToInt(sValue));
    }
    else
    {
        g_bRailcannonRemoved[client] = false;
    }
}

void SaveRemovedState(int client)
{
    char sValue[8];
    IntToString(view_as<int>(g_bRailcannonRemoved[client]), sValue, sizeof(sValue));
    SaveClientDataBySteamID(client, "removed_state", sValue);
}

void LoadClientColor(int client)
{
    char sCookie[64];
    LoadClientDataBySteamID(client, "railcannon_color", sCookie, sizeof(sCookie));
    
    if (strlen(sCookie) > 0)
    {
        char sColors[3][12];
        if (ExplodeString(sCookie, " ", sColors, 3, 12) == 3)
        {
            g_iPlayerColor[client][0] = ClampColor(StringToInt(sColors[0]));
            g_iPlayerColor[client][1] = ClampColor(StringToInt(sColors[1]));
            g_iPlayerColor[client][2] = ClampColor(StringToInt(sColors[2]));
            return;
        }
    }
    
    g_iPlayerColor[client][0] = 255;
    g_iPlayerColor[client][1] = 50;
    g_iPlayerColor[client][2] = 150;
}

void SaveClientColor(int client)
{
    char sCookie[64];
    Format(sCookie, sizeof(sCookie), "%d %d %d", 
        g_iPlayerColor[client][0], 
        g_iPlayerColor[client][1], 
        g_iPlayerColor[client][2]);
    
    SaveClientDataBySteamID(client, "railcannon_color", sCookie);
}

int ClampColor(int value)
{
    if (value < 0) return 0;
    if (value > 255) return 255;
    return value;
}

bool IsClientValid(int client)
{
    return (client > 0 && 
            client <= MaxClients && 
            IsClientInGame(client) && 
            !IsFakeClient(client));
}

// 使用与Spread-Alohai.smx.txt完全相同的方法获取SteamID
bool GetClientSteam32(int client, char[] szSteam32, int maxlen)
{
    if (!IsClientValid(client))
        return false;
    
    // 使用与Spread-Alohai完全相同的参数: GetClientAuthId(client, 1, szSteam32, 32, true)
    return GetClientAuthId(client, AuthId_Steam2, szSteam32, maxlen, true);
}

// 保存客户端数据到SteamID配置文件
void SaveClientDataBySteamID(int client, const char[] key, const char[] value)
{
    char szSteam32[144];
    if (!GetClientSteam32(client, szSteam32, sizeof(szSteam32)))
    {
        LogError("无法获取客户端 %N 的SteamID", client);
        return;
    }
    
    // 验证SteamID格式是否正确
    if (StrContains(szSteam32, "STEAM_") != 0)
    {
        LogError("客户端 %N 的SteamID格式无效: %s", client, szSteam32);
        return;
    }
    
    KeyValues kv = new KeyValues("SteamIDData");
    if (!kv.ImportFromFile(g_szDataFile))
    {
        LogError("无法加载数据文件: %s", g_szDataFile);
        delete kv;
        return;
    }
    
    kv.JumpToKey(szSteam32, true);
    kv.SetString(key, value);
    kv.Rewind();
    
    if (!kv.ExportToFile(g_szDataFile))
    {
        LogError("无法保存数据到文件: %s", g_szDataFile);
    }
    
    delete kv;
}

// 从SteamID配置文件加载客户端数据
void LoadClientDataBySteamID(int client, const char[] key, char[] value, int maxlen)
{
    char szSteam32[144];
    if (!GetClientSteam32(client, szSteam32, sizeof(szSteam32)))
    {
        value[0] = '\0';
        LogError("无法获取客户端 %N 的SteamID", client);
        return;
    }
    
    // 验证SteamID格式是否正确
    if (StrContains(szSteam32, "STEAM_") != 0)
    {
        value[0] = '\0';
        LogError("客户端 %N 的SteamID格式无效: %s", client, szSteam32);
        return;
    }
    
    KeyValues kv = new KeyValues("SteamIDData");
    if (!kv.ImportFromFile(g_szDataFile))
    {
        value[0] = '\0';
        // 如果文件不存在，这不是错误，可能是第一次使用
        delete kv;
        return;
    }
    
    if (kv.JumpToKey(szSteam32, false))
    {
        kv.GetString(key, value, maxlen, "");
    }
    else
    {
        value[0] = '\0';
    }
    
    delete kv;
}