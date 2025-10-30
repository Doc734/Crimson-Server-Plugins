#include <sourcemod>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.0.0"
#define REQUIRED_VALUE "16"
#define CVAR_NAME "sv_maxusrcmdprocessticks"

// 豁免的 SteamID 列表（可以添加多个）
char g_sExemptSteamIDs[][] = {
    "STEAM_1:1:692324972",  // 示例 SteamID
    ""  // 结束标记，不要删除
};

// 玩家数据
Handle g_hPlayerTimer[MAXPLAYERS + 1];
bool g_bIsChecking[MAXPLAYERS + 1];

public Plugin myinfo = 
{
    name = "Check MaxUsrCmdProcessTicks",
    author = "Your Name",
    description = "检测玩家的 sv_maxusrcmdprocessticks 设置，不符合则踢出",
    version = PLUGIN_VERSION,
    url = ""
};

public void OnPluginStart()
{
    // 初始化所有在线玩家
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            CheckClientConVar(i);
        }
    }
    
    // 创建定期检测定时器，每1秒检测一次所有玩家
    CreateTimer(1.0, Timer_PeriodicCheck, _, TIMER_REPEAT);
}

public Action Timer_PeriodicCheck(Handle timer)
{
    // 定期检查所有在线玩家
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            // 如果玩家正在被检查（已经在警告流程中），则跳过
            if (g_bIsChecking[i])
                continue;
            
            CheckClientConVar(i);
        }
    }
    return Plugin_Continue;
}

public void OnClientPutInServer(int client)
{
    // 重置玩家数据
    ResetClientData(client);
    
    // 如果不是机器人，开始检测
    if (!IsFakeClient(client))
    {
        // 延迟 2 秒后开始检测，避免玩家刚连接
        CreateTimer(2.0, Timer_StartCheck, GetClientUserId(client));
    }
}

public void OnClientDisconnect(int client)
{
    // 清理玩家数据
    CleanupClient(client);
}

public Action Timer_StartCheck(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client == 0)
        return Plugin_Stop;
    
    CheckClientConVar(client);
    return Plugin_Stop;
}

void CheckClientConVar(int client)
{
    if (!IsClientInGame(client) || IsFakeClient(client))
        return;
    
    // 检查是否在豁免列表中
    char szSteam32[144];
    GetClientAuthId(client, AuthId_Steam2, szSteam32, sizeof(szSteam32), true);
    
    for (int i = 0; i < sizeof(g_sExemptSteamIDs); i++)
    {
        if (g_sExemptSteamIDs[i][0] == '\0')  // 空字符串，结束循环
            break;
        
        if (StrEqual(szSteam32, g_sExemptSteamIDs[i], true))
        {
            // 该 SteamID 在豁免列表中，不检测
            return;
        }
    }
    
    // 查询客户端 ConVar
    QueryClientConVar(client, CVAR_NAME, OnConVarQueried, GetClientUserId(client));
}

public void OnConVarQueried(QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue, any userid)
{
    // 检查客户端是否还在线
    if (GetClientOfUserId(userid) != client)
        return;
    
    if (!IsClientInGame(client))
        return;
    
    // 检查查询结果
    if (result != ConVarQuery_Okay)
    {
        return;
    }
    
    // 检查值是否正确
    if (!StrEqual(cvarValue, REQUIRED_VALUE))
    {
        // 值不正确，开始警告流程
        StartWarningProcess(client, cvarValue);
    }
    else
    {
        // 值正确，如果正在检查中则取消
        if (g_bIsChecking[client])
        {
            CancelWarningProcess(client);
            PrintToChat(client, "[SM] 检测到你已修改 \x04%s\x01 为 \x04%s\x01，已取消踢出", CVAR_NAME, REQUIRED_VALUE);
        }
    }
}

void StartWarningProcess(int client, const char[] currentValue)
{
    // 如果已经在检查中，先清理
    if (g_bIsChecking[client])
    {
        CleanupClient(client);
    }
    
    g_bIsChecking[client] = true;
    
    // 第一次提示（0秒）
    PrintToChat(client, "[SM] 你的 \x04%s\x01 当前值为 \x04%s\x01，需要设置为 \x04%s", CVAR_NAME, currentValue, REQUIRED_VALUE);
    PrintToChat(client, "[SM] 15秒后将被踢出服务器，请立即修改！");
    
    // 创建定时器 - 5秒后提示还利10秒
    g_hPlayerTimer[client] = CreateTimer(5.0, Timer_Warning10Sec, GetClientUserId(client));
}

void CancelWarningProcess(int client)
{
    g_bIsChecking[client] = false;
    
    if (g_hPlayerTimer[client] != null)
    {
        KillTimer(g_hPlayerTimer[client]);
        g_hPlayerTimer[client] = null;
    }
}

public Action Timer_Warning10Sec(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client == 0 || !IsClientInGame(client))
        return Plugin_Stop;
    
    g_hPlayerTimer[client] = null;
    QueryClientConVar(client, CVAR_NAME, OnConVarRecheck_10Sec, userid);
    
    return Plugin_Stop;
}

public void OnConVarRecheck_10Sec(QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue, any userid)
{
    if (GetClientOfUserId(userid) != client || !IsClientInGame(client))
        return;
    
    if (!g_bIsChecking[client])
        return;
    
    // 检查是否已修改
    if (result == ConVarQuery_Okay && StrEqual(cvarValue, REQUIRED_VALUE))
    {
        CancelWarningProcess(client);
        PrintToChat(client, "[SM] 检测到你已修改 \x04%s\x01 为 \x04%s\x01，已取消踢出", CVAR_NAME, REQUIRED_VALUE);
        return;
    }
    
    // 还未修改，提示还利10秒
    PrintToChat(client, "[SM] 还剩 \x04 10 秒\x01！请立即修改 \x04%s\x01 为 \x04%s", CVAR_NAME, REQUIRED_VALUE);
    
    // 5秒后提示还剩5秒
    g_hPlayerTimer[client] = CreateTimer(5.0, Timer_Warning5Sec, userid);
}

public Action Timer_Warning5Sec(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client == 0 || !IsClientInGame(client))
        return Plugin_Stop;
    
    g_hPlayerTimer[client] = null;
    QueryClientConVar(client, CVAR_NAME, OnConVarRecheck_5Sec, userid);
    
    return Plugin_Stop;
}

public void OnConVarRecheck_5Sec(QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue, any userid)
{
    if (GetClientOfUserId(userid) != client || !IsClientInGame(client))
        return;
    
    if (!g_bIsChecking[client])
        return;
    
    if (result == ConVarQuery_Okay && StrEqual(cvarValue, REQUIRED_VALUE))
    {
        CancelWarningProcess(client);
        PrintToChat(client, "[SM] 检测到你已修改 \x04%s\x01 为 \x04%s\x01，已取消踢出", CVAR_NAME, REQUIRED_VALUE);
        return;
    }
    
    PrintToChat(client, "[SM] 还剩 \x04 5 秒\x01！");
    
    // 2秒后提示还剩3秒
    g_hPlayerTimer[client] = CreateTimer(2.0, Timer_Warning3Sec, userid);
}

public Action Timer_Warning3Sec(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client == 0 || !IsClientInGame(client))
        return Plugin_Stop;
    
    g_hPlayerTimer[client] = null;
    QueryClientConVar(client, CVAR_NAME, OnConVarRecheck_3Sec, userid);
    
    return Plugin_Stop;
}

public void OnConVarRecheck_3Sec(QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue, any userid)
{
    if (GetClientOfUserId(userid) != client || !IsClientInGame(client))
        return;
    
    if (!g_bIsChecking[client])
        return;
    
    if (result == ConVarQuery_Okay && StrEqual(cvarValue, REQUIRED_VALUE))
    {
        CancelWarningProcess(client);
        PrintToChat(client, "[SM] 检测到你已修改 \x04%s\x01 为 \x04%s\x01，已取消踢出", CVAR_NAME, REQUIRED_VALUE);
        return;
    }
    
    PrintToChat(client, "[SM] 还剩 \x04 3 秒\x01！");
    
    // 1秒后提示还剩2秒
    g_hPlayerTimer[client] = CreateTimer(1.0, Timer_Warning2Sec, userid);
}

public Action Timer_Warning2Sec(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client == 0 || !IsClientInGame(client))
        return Plugin_Stop;
    
    g_hPlayerTimer[client] = null;
    QueryClientConVar(client, CVAR_NAME, OnConVarRecheck_2Sec, userid);
    
    return Plugin_Stop;
}

public void OnConVarRecheck_2Sec(QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue, any userid)
{
    if (GetClientOfUserId(userid) != client || !IsClientInGame(client))
        return;
    
    if (!g_bIsChecking[client])
        return;
    
    if (result == ConVarQuery_Okay && StrEqual(cvarValue, REQUIRED_VALUE))
    {
        CancelWarningProcess(client);
        PrintToChat(client, "[SM] 检测到你已修改 \x04%s\x01 为 \x04%s\x01，已取消踢出", CVAR_NAME, REQUIRED_VALUE);
        return;
    }
    
    PrintToChat(client, "[SM] 还剩 \x04 2 秒\x01！");
    
    // 1秒后提示还剩1秒
    g_hPlayerTimer[client] = CreateTimer(1.0, Timer_Warning1Sec, userid);
}

public Action Timer_Warning1Sec(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client == 0 || !IsClientInGame(client))
        return Plugin_Stop;
    
    g_hPlayerTimer[client] = null;
    QueryClientConVar(client, CVAR_NAME, OnConVarRecheck_1Sec, userid);
    
    return Plugin_Stop;
}

public void OnConVarRecheck_1Sec(QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue, any userid)
{
    if (GetClientOfUserId(userid) != client || !IsClientInGame(client))
        return;
    
    if (!g_bIsChecking[client])
        return;
    
    if (result == ConVarQuery_Okay && StrEqual(cvarValue, REQUIRED_VALUE))
    {
        CancelWarningProcess(client);
        PrintToChat(client, "[SM] 检测到你已修改 \x04%s\x01 为 \x04%s\x01，已取消踢出", CVAR_NAME, REQUIRED_VALUE);
        return;
    }
    
    PrintToChat(client, "[SM] 还剩 \x04 1 秒\x01！");
    
    // 1秒后踢出
    g_hPlayerTimer[client] = CreateTimer(1.0, Timer_KickClient, userid);
}

public Action Timer_KickClient(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client == 0 || !IsClientInGame(client))
        return Plugin_Stop;
    
    g_hPlayerTimer[client] = null;
    QueryClientConVar(client, CVAR_NAME, OnConVarRecheck_Final, userid);
    
    return Plugin_Stop;
}

public void OnConVarRecheck_Final(QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue, any userid)
{
    if (GetClientOfUserId(userid) != client || !IsClientInGame(client))
        return;
    
    if (!g_bIsChecking[client])
        return;
    
    // 最后一次检查
    if (result == ConVarQuery_Okay && StrEqual(cvarValue, REQUIRED_VALUE))
    {
        CancelWarningProcess(client);
        PrintToChat(client, "[SM] 检测到你已修改 \x04%s\x01 为 \x04%s\x01，已取消踢出", CVAR_NAME, REQUIRED_VALUE);
        return;
    }
    
    // 仍未修改，踢出玩家
    CleanupClient(client);
    KickClient(client, "未按要求设置 %s 为 %s", CVAR_NAME, REQUIRED_VALUE);
}

void ResetClientData(int client)
{
    g_hPlayerTimer[client] = null;
    g_bIsChecking[client] = false;
}

void CleanupClient(int client)
{
    if (g_hPlayerTimer[client] != null)
    {
        KillTimer(g_hPlayerTimer[client]);
        g_hPlayerTimer[client] = null;
    }
    g_bIsChecking[client] = false;
}