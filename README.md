# CS:GO SourceMod 插件

### match_announcer.sp
检测PugSetup的LIVE消息，在比赛开始时发送LIVE提示，每回合结束后显示双方比分。

依赖: [MultiColors](https://github.com/Bara/Multi-Colors)

### 浮游炮.sp
玩家头顶创建悬浮武器模型，射击时显示激光束。管理员!rcckey生成卡密，玩家!rckey激活，!rc打开菜单，!rcl设置颜色，!banfyp封禁玩家浮游炮权限。

依赖: 无

### abc.sp
检测玩家的sv_maxusrcmdprocessticks是否为16，不符合给15秒修改时间，超时踢出。支持SteamID白名单。

依赖: 无

---

## 安装

编译成smx放到addons/sourcemod/plugins/，重启服务器或sm plugins load加载。

