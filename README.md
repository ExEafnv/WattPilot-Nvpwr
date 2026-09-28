# WattPilot-Nvpwr

> 无 GUI 静默自动设置 NVIDIA 笔记本显卡功耗墙。
> 通过 exe 文件名决定目标功耗，适合计划任务登录后自动运行。

---

## 目录

- [简介](#简介)
- [重要说明](#重要说明)
- [你需要自行准备的依赖](#你需要自行准备的依赖)
- [支持的显卡](#支持的显卡)
- [使用前提](#使用前提)
- [使用步骤](#使用步骤)
- [日志说明](#日志说明)
- [退出时的安全行为](#退出时的安全行为)
- [风险点与免责声明](#风险点与免责声明)
- [维护状态](#维护状态)
- [常见问题](#常见问题)
- [致谢](#致谢)
- [许可](#许可)

---

## 简介

WattPilot-Nvpwr 是一个静默的功耗墙自动设置工具。将编译好的 exe 加入计划任务，用户登录后延迟 30 秒即可自动完成功耗墙设置，无需打开 GUI、手动选择、点击 Apply。

目标功耗由 exe 文件名决定：

| 文件名 | 目标功耗 |
|--------|----------|
| `AUTO_POWER.exe` | 140 W（默认） |
| `AUTO_POWER_160.exe` | 160 W |
| `AUTO_POWER_170.exe` | 170 W |
| `AUTO_POWER_175.exe` | 175 W |
| `AUTO_POWER_XXXX.exe` | XXXX W（上限 1000 W） |

本工具是「Nvpwr-Ctrl-GUI-EfiGuard」工具集的**自动化补充版本**，不是替代。喜欢手动调节的用户建议继续使用原 GUI 工具集；希望开机自动生效的用户可以使用本工具。

---

## 重要说明

**本仓库只提供以下内容：**

- `AUTO_POWER.ps1`：PowerShell 源代码。
- Releases 页面中编译好的 `AUTO_POWER*.exe`。

**本仓库不包含、也不会提供以下依赖文件：**

- `EfiDSEFix.exe`
- `Nvpwr.sys`
- `NvpwrCtl.exe`

这些文件来自上游开源项目，需要你**自行获取**，并与 `AUTO_POWER*.exe` 放在同一目录下才能运行。

---

## 你需要自行准备的依赖

请按以下步骤准备文件。

### 1. 获取 EfiDSEFix.exe

从 EfiGuard 官方仓库下载：

https://github.com/Mattiwatti/EfiGuard/releases

解压后可以找到 `EfiDSEFix.exe`。

### 2. 获取 Nvpwr.sys 与 NvpwrCtl.exe

从 NvpwrControl 项目或原 GUI 工具集获取：

https://github.com/LevinAi-arch/rtx-5070ti-laptop-160w-power-limit


### 3. 新建文件夹并放置文件

新建一个短路径文件夹，例如：

```
C:\WattPilot\
```

将以下文件全部放入该文件夹：

```
C:\WattPilot\
├─ AUTO_POWER.exe        （或 AUTO_POWER_170.exe 等）
├─ EfiDSEFix.exe         （自行获取）
├─ Nvpwr.sys             （自行获取）
└─ NvpwrCtl.exe          （自行获取）
```

四个文件必须处于同一目录，缺一不可。

---

## 支持的显卡

本工具依赖 `Nvpwr.sys`，支持以下 GPU（由 `NvpwrCtl.exe` 决定）：

- RTX 5070 Ti Laptop
- RTX 5080 Laptop
- RTX 5090 Laptop
- RTX 5050 Laptop
- RTX 5060 Laptop
- RTX 5070 Laptop

---

## 使用前提

使用前必须满足以下全部条件：

1. **系统已通过 EfiGuard 启动**
   WattPilot 依赖 `EfiDSEFix.exe` 临时关闭驱动签名强制（DSE）。只有在 EfiGuard 修补过内核的环境下，`EfiDSEFix.exe -d` 才会生效。普通 Windows 启动方式下，工具会报错或 `set` 失败。

2. **BIOS 中已关闭 Secure Boot**
   EfiGuard 需要在关闭 Secure Boot 的环境下加载。

3. **NVIDIA 驱动版本与 Nvpwr.sys 兼容**
   当前版本针对 616.92 驱动。其他版本可能不兼容。

4. **以管理员权限运行**
   `sc.exe`、`NvpwrCtl.exe`、`EfiDSEFix.exe` 均需要管理员权限。

5. **硬件为 50 系 NVIDIA 笔记本显卡**
   详见上一节支持的显卡列表。

---

## 使用步骤

### 第一步：准备 EfiGuard 启动环境

如果已经配置好 EfiGuard 并能在启动时看到 EfiGuard 的启动信息，可以跳过这一步。

1. 从 https://github.com/Mattiwatti/EfiGuard/releases 下载 EfiGuard。
2. 准备一个 FAT32 格式的 U 盘。
3. 将 `Loader.efi` 重命名为 `bootx64.efi`，与 `EfiGuardDxe.efi` 一起放入 U 盘的 `EFI/Boot/` 目录。
4. 重启电脑，从 U 盘启动，确认能看到 EfiGuard 提示信息。
5. 进入 BIOS 关闭 Secure Boot。

如果以上步骤不熟悉，建议先查阅 EfiGuard 官方文档。

### 第二步：准备依赖文件

按照「你需要自行准备的依赖」一节，获取 `EfiDSEFix.exe`、`Nvpwr.sys`、`NvpwrCtl.exe`，并与 `AUTO_POWER*.exe` 放入同一文件夹。

### 第三步：手动测试

1. 右键 `AUTO_POWER_170.exe`（或你选定的目标文件）。
2. 选择“以管理员身份运行”。
3. 等待约 5~15 秒，工具在后台静默完成设置。
4. 打开同目录 `auto.log`，确认出现 `成功=True`。

### 第四步：加入计划任务

确认手动运行成功后，以管理员身份打开 PowerShell 执行：

```powershell
$TaskName = 'WattPilot Auto Set Power'
$ExePath  = 'C:\WattPilot\AUTO_POWER_170.exe'
$WorkDir  = Split-Path $ExePath -Parent

$Action    = New-ScheduledTaskAction -Execute $ExePath -WorkingDirectory $WorkDir
$Trigger   = New-ScheduledTaskTrigger -AtLogOn
$Trigger.Delay = 'PT30S'
$Principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
$Settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 15)

Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings -Force
```

---

## 日志说明

运行日志写入同目录 `auto.log`，每次运行清空旧内容后重写。

关键日志行：

**成功：**

```
成功：Current F7 = 170000（目标 170 W）
===== 结束 成功=True =====
```

**目标低于驱动最小值：**

```
目标 140 W 低于驱动允许的最小值 145 W，永久失败。
```

**MIXED 状态（建议重启系统）：**

```
set 退出码=6 State=MIXED ...
```

---

## 退出时的安全行为

无论设置成功或失败，工具退出前都会执行：

```
EfiDSEFix.exe -e    恢复驱动签名强制（主路径 + 备用路径各一次）
sc.exe stop Nvpwr   停止内核服务
```

若某次运行异常中断导致 DSE 未恢复，可手动执行：

```
EfiDSEFix.exe -e
```

恢复后建议重启一次系统。

---

## 风险点与免责声明

**请在使用前完整阅读以下内容。使用本工具即表示你已知悉并自行承担全部风险。**

### 风险点

1. **硬件损坏风险**
   提高显卡功耗墙会显著增加供电与散热压力。可能导致显卡、供电模块、电池或主板损坏。因修改功耗导致的任何硬件损坏，由使用者自行承担。

2. **系统稳定性风险**
   本工具使用内核驱动并临时关闭驱动签名强制。可能导致蓝屏、系统无法启动、驱动冲突或其他不可预期的问题。

3. **反作弊与账号风险**
   本方案修补了 `ntoskrnl.exe`，部分反作弊系统可能识别到内核补丁，从而导致游戏账号被限制或封禁。请自行评估风险。

4. **安全风险**
   关闭 Secure Boot、使用 EfiGuard、临时关闭 DSE 都会降低系统安全防护级别。请勿在存有敏感数据的机器上使用。

5. **数据丢失风险**
   系统不稳定可能导致未保存的数据丢失。请在使用前备份重要文件。

### 免责声明

本工具按“现状”提供，不附带任何明示或暗示的担保。作者不对使用本工具所造成的任何直接或间接损失负责，包括但不限于硬件损坏、数据丢失、系统故障、账号封禁、法律纠纷等。

请仅在你自己拥有或有权操作的设备上使用本工具。

---

## 维护状态

本项目**可能不会持续维护**。作者仅出于个人需求整理并发布，不承诺修复后续问题、适配新驱动或增加新功能。

如果你希望继续使用或改进，可以：

- 基于本仓库提供的 `AutoSetGpuPower-Silent.ps1` 自行修改。
- 借助 AI 工具（如 ChatGPT、Claude 等）根据你的显卡型号、驱动版本、需求进行适配或优化。
- 参考上游项目自行更新依赖文件。

---

## 源码与自行编译

本仓库提供的 `AUTO_POWER.ps1` 为 PowerShell 源码。Releases 中的
`AUTO_POWER*.exe` 由该源码经 `ps2exe` 编译生成。

如果你修改了源码，想自行重新编译，可以用以下命令：

```powershell
ps2exe -InputFile "AUTO_POWER.ps1" -OutputFile "AUTO_POWER_170.exe" -NoConsole
```

---

参数说明：

- `-InputFile`：源码文件路径。
- `-OutputFile`：编译后的 exe 文件名。文件名中的数字决定目标功耗，
  例如 `AUTO_POWER_170.exe` 就是 170 W。
- `-NoConsole`：不显示控制台窗口，符合静默运行的设计。

`ps2exe` 是一个开源工具，可在 PowerShell Gallery 安装：

```powershell
Install-Module -Name ps2exe -Scope CurrentUser
```

如果你不需要修改源码，直接下载 Releases 中的 exe 即可，无需自行编译。

## 常见问题

### Q1：为什么下载包里没有 `EfiDSEFix.exe`、`Nvpwr.sys`、`NvpwrCtl.exe`？

这些文件来自上游开源项目，不属于本仓库发布范围。请按「你需要自行准备的依赖」一节自行获取。

### Q2：运行时报“未检测到 NVIDIA 显卡”

确认硬件是否为 NVIDIA RTX 50 系笔记本显卡。台式机显卡、40 系及更早型号不在支持范围内。

### Q3：`EfiDSEFix -d` 返回非零或报错

说明当前系统不是通过 EfiGuard 启动的。检查 Secure Boot 是否已关闭，启动时是否看到 EfiGuard 提示信息。

### Q4：`sc start` 返回 3（系统找不到指定的路径）

通常是 Nvpwr 服务注册的驱动路径与当前 `Nvpwr.sys` 不一致。可在管理员 PowerShell 中手动清理：

```powershell
sc.exe stop Nvpwr
sc.exe delete Nvpwr
```

然后再次运行 WattPilot。

### Q5：日志反复出现 `State=MIXED`

说明 NVIDIA 驱动内部状态已经漂移。**建议重启系统**，重启后立即运行 WattPilot。

### Q6：进游戏后被反作弊拦截

本方案修补了内核，虽然退出时恢复了 DSE，但内核补丁在本次开机周期内仍然存在。**重启系统可清除全部内核补丁。**

### Q7：设置成功但游戏跑不满功耗

功耗墙为驱动层上限，实际功耗仍受笔记本 EC、BIOS、电源适配器、散热等限制。这不属于工具问题。

### Q8：如何卸载

1. 删除计划任务 `WattPilot Auto Set Power`。
2. 在管理员 PowerShell 中执行：

   ```powershell
   sc.exe stop Nvpwr
   sc.exe delete Nvpwr
   ```

3. 删除 `C:\WattPilot\` 目录。
4. 如需彻底移除 EfiGuard，请从 UEFI 启动项中删除对应条目并恢复 Secure Boot。

---

## 致谢

本工具的核心命令链来源于以下开源项目：

- **EfiGuard / EfiDSEFix**
  https://github.com/Mattiwatti/EfiGuard
- **NvpwrControl / Nvpwr**
  https://github.com/LevinAi-arch/rtx-5070ti-laptop-160w-power-limit

启动链设计来源：

- **B站用户 @B站是一只Moki_**
  https://www.bilibili.com/video/BV1WJe16dE2F/

本工具为该工具集的自动化补充版本，无 GUI，面向登录后计划任务场景。感谢原作者对启动链的整理与工具集的发布。

---

## 许可

本项目源码采用 **GPL-3.0** 协议。

本仓库不包含 `EfiDSEFix.exe`、`Nvpwr.sys`、`NvpwrCtl.exe`。这些文件来自上游项目，遵循其各自开源协议。
