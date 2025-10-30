#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <multicolors>

public Plugin myinfo = 
{
    name = "Match Announcer (LIVE + Score)",
    description = "Announces LIVE message and round scores",
    author = "Your Name",
    version = "1.0",
    url = ""
};

// 全局变量
bool g_bMatchStarted = false;       // 比赛是否已开始
bool g_bLiveMessageShown = false;   // 是否已发送过 LIVE 消息
bool g_bDetectedPugSetupLive = false; // 当前回合是否检测到 PugSetup LIVE
int g_iTScore;
int g_iCTScore;

// PugSetup LIVE 消息的两种格式
#define PUGSETUP_LIVE_1 "[\x05PugSetup\x01] Match is \x04LIVE"
#define PUGSETUP_LIVE_2 "\x01[\x05PugSetup\x01] Match is \x04LIVE"

public void OnPluginStart()
{
    // 监听事件
    HookEvent("round_start", Event_RoundStart, EventHookMode_Pre);
    HookEvent("round_freeze_end", Event_RoundFreezeEnd);
    HookEvent("round_end", Event_RoundEnd, EventHookMode_Post);
    
    // 监听聊天消息以检测 PugSetup LIVE
    if (GetUserMessageType() == UM_Protobuf) 
    { 
        HookUserMessage(GetUserMessageId("TextMsg"), TextMsg, true); 
    }
}

public void OnMapStart()
{
    // 换图时重置所有标志
    g_bMatchStarted = false;
    g_bLiveMessageShown = false;
    g_bDetectedPugSetupLive = false;
    g_iTScore = 0;
    g_iCTScore = 0;
}

public Action TextMsg(UserMsg msg_id, Protobuf pb, const int[] players, int playersNum, bool reliable, bool init) 
{ 
    if (!reliable || pb.ReadInt("msg_dst") != 3) 
    { 
        return Plugin_Continue; 
    } 

    char buffer[256]; 
    pb.ReadString("params", buffer, sizeof(buffer), 0); 

    // 检测 PugSetup LIVE 消息
    if (StrContains(buffer, PUGSETUP_LIVE_1) != -1 || StrContains(buffer, PUGSETUP_LIVE_2) != -1) 
    { 
        g_bMatchStarted = true;
        g_bDetectedPugSetupLive = true;
    } 

    return Plugin_Continue;
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    // 检测热身状态
    bool inWarmup = view_as<bool>(GameRules_GetProp("m_bWarmupPeriod"));
    
    if (inWarmup)
    {
        // 在热身中，重置所有状态
        g_bMatchStarted = false;
        g_bLiveMessageShown = false;
        g_bDetectedPugSetupLive = false;
    }
    // 不在热身时，不重置任何标志（保持检测到的 PugSetup LIVE 状态）
    
    // 更新比分
    g_iTScore = GetTeamScore(2);
    g_iCTScore = GetTeamScore(3);
}

public void Event_RoundFreezeEnd(Event event, const char[] name, bool dontBroadcast)
{
    // 功能1：发送 LIVE 消息（只发送一次）
    if (!g_bLiveMessageShown && g_bDetectedPugSetupLive)
    {
        // 发送3次 LIVE 消息
        for (int i = 0; i < 3; i++)
        {
            CPrintToChatAll("[crimson.{orange}code{default}] The match is now {orange}LIVE{default}.");
        }
        
        g_bLiveMessageShown = true;
    }
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    // 功能2：显示回合结束比分
    
    // 检查1：比赛是否已开始
    if (!g_bMatchStarted)
    {
        return;
    }
    
    // 获取队伍比分
    g_iTScore = GetTeamScore(2);  // T队比分
    g_iCTScore = GetTeamScore(3); // CT队比分
    
    // 检查2：比分是否为 0:0
    if (g_iTScore == 0 && g_iCTScore == 0)
    {
        return;
    }
    
    // 向所有真实玩家发送比分信息
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            int team = GetClientTeam(i);
            char buffer[128];
            
            // 根据玩家所在队伍，调整显示格式
            if (team == 2) // T队玩家
            {
                Format(buffer, sizeof(buffer), "[crimson.{orange}code{default}] {orange}TERRORISTS {green}%d{default} - {green}%d{orange} COUNTER-TERRORISTS", g_iTScore, g_iCTScore);
            }
            else if (team == 3) // CT队玩家
            {
                Format(buffer, sizeof(buffer), "[crimson.{orange}code{default}] {orange}TERRORISTS {green}%d{default} - {green}%d{orange} COUNTER-TERRORISTS", g_iTScore, g_iCTScore);
            }
            else // 观察者或其他
            {
                Format(buffer, sizeof(buffer), "[crimson.{orange}code{default}] {orange}TERRORISTS {green}%d{default} - {green}%d{orange} COUNTER-TERRORISTS", g_iTScore, g_iCTScore);
            }
            
            CPrintToChat(i, buffer);
        }
    }
}

