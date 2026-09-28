<#
.SYNOPSIS
    NVIDIA 笔记本显卡功耗墙自动设置工具。

.DESCRIPTION
    本脚本用于在 Windows 登录后自动设置 NVIDIA RTX 笔记本显卡的功耗墙。
    脚本以 EfiGuard + EfiDSEFix 方案为核心，通过临时关闭内核驱动签名强制，
    加载 Nvpwr.sys 内核驱动，再调用 NvpwrCtl.exe 下发目标功耗，最后恢复
    驱动签名强制状态。

    目标功耗由脚本打包为exe后的文件名决定，无需修改脚本内容：
        AUTO_POWER.exe         -> 默认 140 W
        AUTO_POWER_160.exe     -> 160 W
        AUTO_POWER_175.exe     -> 175 W
        AUTO_POWER_XXXX.exe    -> 对应 XXXX W（上限 1000 W）
    文件名不符合 AUTO_POWER 或 AUTO_POWER_数字 规则时，回退到默认 140 W。

    支持的 GPU 型号由 NvpwrCtl.exe 决定，本脚本根据 GPU 名自动选择
    Nvpwr profile 字符串：
        RTX 5070 Ti Laptop  -> 5070ti
        RTX 5080 Laptop     -> 5080
        RTX 5090 Laptop     -> 5090
        RTX 5050 Laptop     -> 5050
        RTX 5060 Laptop     -> 5060
        RTX 5070 Laptop     -> 5070

    推荐使用方式：以计划任务在“用户登录后延迟 30 秒”触发，可避免开机
    阶段 GPU 子系统尚未完成初始化导致的 MIXED 状态。若仍遇到 MIXED，
    脚本会自动重启显卡一次并重试。

.PARAMETER 无
    本脚本不接收命令行参数，所有行为由文件名和同目录依赖文件决定。

.NOTES
    方案      : EfiGuard + EfiDSEFix + Nvpwr.sys
    前提条件  :
        1. 系统必须通过 EfiGuard 启动，否则 EfiDSEFix 无法生效。
        2. 必须以管理员权限运行，否则 sc.exe / NvpwrCtl.exe 会失败。
        3. 必须与以下文件处于同一目录：
              EfiDSEFix.exe
              Nvpwr.sys
              NvpwrCtl.exe
    运行方式  :
        - 手动：右键以管理员身份运行编译后的 exe。
        - 计划任务：以 SYSTEM 或当前用户身份、最高权限运行，
          触发条件建议设为“登录后延迟 30 秒”。
    日志      :
        同目录下 auto.log，每次运行清空旧内容后重写。
    退出行为  :
        无论设置成功与否，均执行：
            1. EfiDSEFix.exe -e  恢复驱动签名强制（主路径 + 备用路径各一次）
            2. sc.exe stop Nvpwr 停止内核服务
        以便系统回到干净状态，避免反作弊检测到 DSE 未恢复。

    开源项目与致谢  :

        本脚本的核心命令链来源于以下开源项目：

        - EfiGuard / EfiDSEFix
          项目地址：https://github.com/Mattiwatti/EfiGuard
          用途：提供 EfiGuard 引导环境，并通过 EfiDSEFix.exe 在运行时
                临时关闭 / 恢复内核驱动签名强制（DSE）。

        - NvpwrControl / Nvpwr
          项目地址：https://github.com/LevinAi-arch/rtx-5070ti-laptop-160w-power-limit
          用途：提供 Nvpwr.sys 内核驱动与 NvpwrCtl.exe 命令行工具，
                用于设置 NVIDIA 笔记本显卡功耗墙。

        启动链设计来源：

        - B站用户 @B站是一只Moki_
          工具集发布页：https://www.bilibili.com/video/BV1WJe16dE2F/
          说明：本脚本采用的 EfiGuard + EfiDSEFix + Nvpwr 启动链，
                其命令顺序与参数方案来源于该作者发布的 GUI 工具集。
                
        本脚本为上述方案的自动化静默实现，面向开机或登录后计划任务场景，
        不包含 GUI，所有过程信息写入同目录 auto.log。

.LINK
    EfiGuard 项目        : https://github.com/Mattiwatti/EfiGuard
    NvpwrControl 项目    : https://github.com/LevinAi-arch/rtx-5070ti-laptop-160w-power-limit
    B站工具集发布页       : https://www.bilibili.com/video/BV1WJe16dE2F/
#>

# ============================================================
#  运行环境准备
# ============================================================

$ErrorActionPreference = 'Stop'

# 兼容 ps2exe 编译为 exe 后的自身路径获取。
$ExePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
if ([string]::IsNullOrWhiteSpace($ExePath)) {
    $ExePath = $MyInvocation.MyCommand.Path
}
$Root = Split-Path -Parent $ExePath
Set-Location -LiteralPath $Root

$LogFile = Join-Path $Root 'auto.log'

# 每次运行清空旧日志，避免日志随计划任务长期运行无限增长。
try {
    if (Test-Path -LiteralPath $LogFile) { Remove-Item -LiteralPath $LogFile -Force }
}
catch { }

# ============================================================
#  通用工具函数
# ============================================================

<#
.SYNOPSIS
    向同目录 auto.log 追加一行带时间戳的日志。
#>
function Write-Log {
    param([string]$Message)
    try {
        $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Message
        Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
    }
    catch { }
}

<#
.SYNOPSIS
    以完全隐藏的方式启动一个外部进程，并捕获其标准输出与错误输出。
#>
function Invoke-HiddenProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$Arguments
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = $Arguments
    $psi.WorkingDirectory = $Root
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    try {
        if (-not $p.Start()) {
            return [pscustomobject]@{ ExitCode = -1; StdOut = ''; StdErr = "无法启动：$FilePath" }
        }
        $stdoutTask = $p.StandardOutput.ReadToEndAsync()
        $stderrTask = $p.StandardError.ReadToEndAsync()
        $p.WaitForExit()
        return [pscustomobject]@{
            ExitCode = $p.ExitCode
            StdOut   = $stdoutTask.GetAwaiter().GetResult()
            StdErr   = $stderrTask.GetAwaiter().GetResult()
        }
    }
    finally {
        $p.Dispose()
    }
}

# ============================================================
#  服务状态管理
# ============================================================

<#
.SYNOPSIS
    查询 Nvpwr 内核服务的当前状态。
.DESCRIPTION
    返回 ABSENT / STOPPED / RUNNING / START_PENDING / STOP_PENDING / UNKNOWN。
#>
function Get-NvpwrServiceState {
    $r = Invoke-HiddenProcess -FilePath 'sc.exe' -Arguments 'query Nvpwr'
    if ($r.ExitCode -ne 0) { return 'ABSENT' }
    if ($r.StdOut -match 'STOP_PENDING')  { return 'STOP_PENDING' }
    if ($r.StdOut -match 'START_PENDING') { return 'START_PENDING' }
    if ($r.StdOut -match 'RUNNING')       { return 'RUNNING' }
    if ($r.StdOut -match 'STOPPED')       { return 'STOPPED' }
    return 'UNKNOWN'
}

<#
.SYNOPSIS
    读取 Nvpwr 服务当前注册的驱动路径（binPath）。
.DESCRIPTION
    通过 sc.exe qc Nvpwr 查询 BINARY_PATH_NAME。
    服务不存在或查询失败时返回空字符串。
#>
function Get-NvpwrServiceBinPath {
    $r = Invoke-HiddenProcess -FilePath 'sc.exe' -Arguments 'qc Nvpwr'
    if ($r.ExitCode -ne 0) { return '' }
    $m = [regex]::Match($r.StdOut, '(?im)^\s*BINARY_PATH_NAME\s*:\s*(.+?)\s*$')
    if (-not $m.Success) { return '' }
    # sc.exe 输出中的路径可能带两端引号，去掉后再返回。
    return $m.Groups[1].Value.Trim().Trim('"')
}

<#
.SYNOPSIS
    等待 Nvpwr 服务进入指定状态。
#>
function Wait-NvpwrServiceState {
    param(
        [Parameter(Mandatory = $true)][string]$Wanted,
        [int]$TimeoutSeconds = 20
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if ((Get-NvpwrServiceState) -eq $Wanted) { return $true }
        Start-Sleep -Milliseconds 300
    }
    return ((Get-NvpwrServiceState) -eq $Wanted)
}

# ============================================================
#  NvpwrCtl 输出解析
# ============================================================

<#
.SYNOPSIS
    解析 NvpwrCtl.exe 的 status / set 输出文本。
#>
function Parse-NvpwrCtlOutput {
    param([string]$Text)
    $info = [pscustomobject]@{
        State      = $null
        F7Input    = $null
        Upper      = $null
        CurrentF7  = $null
        Win32Error = $null
    }
    if ([string]::IsNullOrWhiteSpace($Text)) { return $info }

    $m = [regex]::Match($Text, '(?im)^\s*State\s*:\s*([A-Z_]+)')
    if ($m.Success) { $info.State = $m.Groups[1].Value }

    $m = [regex]::Match($Text, '(?im)^\s*F7\s+input\s*\([^)]*\)\s*:\s*(\d+)')
    if ($m.Success) { $info.F7Input = [long]$m.Groups[1].Value }

    $m = [regex]::Match($Text, '(?im)^\s*UPPER\s*\([^)]*\)\s*:\s*(\d+)')
    if ($m.Success) { $info.Upper = [long]$m.Groups[1].Value }

    $m = [regex]::Match($Text, '(?im)^\s*Current\s+F7\s*:\s*(\d+)')
    if ($m.Success) { $info.CurrentF7 = [long]$m.Groups[1].Value }

    $m = [regex]::Match($Text, 'Win32=(\d+)')
    if ($m.Success) { $info.Win32Error = [int]$m.Groups[1].Value }

    return $info
}

# ============================================================
#  参数解析与硬件识别
# ============================================================

<#
.SYNOPSIS
    根据可执行文件名解析目标功耗。
.DESCRIPTION
    匹配 AUTO_POWER 或 AUTO_POWER_<数字>，其他名称回退 140 W；
    上限 1000 W。
#>
function Get-TargetWattsFromFileName {
    param([string]$ExeFullPath)

    $defaultWatts = 140
    $maxWatts = 1000

    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($ExeFullPath)
    if ([string]::IsNullOrWhiteSpace($fileName)) { return $defaultWatts }

    $m = [regex]::Match($fileName, '^AUTO_POWER(?:_(\d+))?$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $m.Success) { return $defaultWatts }
    if (-not $m.Groups[1].Success) { return $defaultWatts }

    $parsed = 0
    if (-not [int]::TryParse($m.Groups[1].Value, [ref]$parsed)) { return $defaultWatts }
    if ($parsed -le 0) { return $defaultWatts }
    if ($parsed -gt $maxWatts) { return $maxWatts }
    return $parsed
}

<#
.SYNOPSIS
    获取本机第一块 NVIDIA 显卡的显示名称。
#>
function Get-NvidiaGpuName {
    $gpus = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '(?i)NVIDIA' })
    if ($gpus.Count -eq 0) { return $null }
    return $gpus[0].Name
}

<#
.SYNOPSIS
    根据 NVIDIA GPU 名解析 NvpwrCtl.exe 所需的 profile 字符串。
.DESCRIPTION
    顺序敏感：5070 Ti 必须先于 5070 匹配。
#>
function Get-NvpwrProfileFromGpuName {
    param([string]$GpuName)
    if ([string]::IsNullOrWhiteSpace($GpuName)) { return $null }
    if ($GpuName -match '(?i)RTX\s*5070\s*Ti\s*Laptop') { return '5070ti' }
    if ($GpuName -match '(?i)RTX\s*5080\s*Laptop')       { return '5080' }
    if ($GpuName -match '(?i)RTX\s*5090\s*Laptop')       { return '5090' }
    if ($GpuName -match '(?i)RTX\s*5050\s*Laptop')       { return '5050' }
    if ($GpuName -match '(?i)RTX\s*5060\s*Laptop')       { return '5060' }
    if ($GpuName -match '(?i)RTX\s*5070\s*Laptop')       { return '5070' }
    return $null
}

# ============================================================
#  服务与设备控制
# ============================================================

<#
.SYNOPSIS
    加载 Nvpwr 内核服务。
.DESCRIPTION
    统一处理所有服务状态，收敛到 STOPPED 后再启动。
    若服务已存在但其注册的驱动路径与当前 Nvpwr.sys 不一致，
    自动强制重建，避免因工具目录变更导致 sc start 返回错误 3。
    -ForceRecreate 用于显卡重启后获取全新内核实例。
#>
function Install-NvpwrService {
    param(
        [Parameter(Mandatory = $true)][string]$DriverPath,
        [switch]$ForceRecreate
    )

    $state = Get-NvpwrServiceState

    # 服务已存在时，先核对其注册的驱动路径是否与当前 Nvpwr.sys 一致。
    # 路径不一致说明是之前在其他目录注册的残留服务，必须强制重建。
    if ($state -ne 'ABSENT' -and -not $ForceRecreate) {
        $registeredPath = Get-NvpwrServiceBinPath
        if (-not [string]::IsNullOrWhiteSpace($registeredPath) -and
            $registeredPath -ne $DriverPath) {
            Write-Log 'Nvpwr 服务注册路径与当前驱动不一致，强制重建。'
            Write-Log ("  注册路径：{0}" -f $registeredPath)
            Write-Log ("  当前路径：{0}" -f $DriverPath)
            $ForceRecreate = $true
        }
    }

    if ($state -eq 'ABSENT' -or $ForceRecreate) {
        if ($state -ne 'ABSENT') {
            Write-Log "Nvpwr 服务已存在（当前状态：$state），执行强制重建..."
            Invoke-HiddenProcess -FilePath 'sc.exe' -Arguments 'stop Nvpwr' | Out-Null

            $deadline = (Get-Date).AddSeconds(20)
            while ((Get-Date) -lt $deadline) {
                if ((Get-NvpwrServiceState) -eq 'STOPPED') { break }
                Start-Sleep -Milliseconds 500
            }

            Write-Log '删除 Nvpwr 服务...'
            Invoke-HiddenProcess -FilePath 'sc.exe' -Arguments 'delete Nvpwr' | Out-Null

            $deadline = (Get-Date).AddSeconds(20)
            while ((Get-Date) -lt $deadline) {
                if ((Get-NvpwrServiceState) -eq 'ABSENT') { break }
                Start-Sleep -Milliseconds 500
            }

            $state = Get-NvpwrServiceState
            if ($state -ne 'ABSENT') {
                throw "Nvpwr 服务未能删除（当前状态：$state）。"
            }
        }

        Write-Log '创建 Nvpwr 内核服务...'
        $r = Invoke-HiddenProcess -FilePath 'sc.exe' -Arguments ('create Nvpwr type= kernel binPath= "' + $DriverPath + '"')
        Write-Log ("sc create 退出码={0} 输出={1} 错误={2}" -f $r.ExitCode, $r.StdOut.Trim(), $r.StdErr.Trim())
        if ($r.ExitCode -ne 0) { throw "创建 Nvpwr 服务失败：$($r.ExitCode)" }
    }
    else {
        Write-Log "Nvpwr 服务已存在（当前状态：$state）。"
    }

    # 统一收敛到 STOPPED。
    $stopIssued = $false
    for ($i = 0; $i -lt 60; $i++) {
        $state = Get-NvpwrServiceState
        if ($state -eq 'STOPPED' -or $state -eq 'ABSENT') { break }

        if ($state -eq 'RUNNING' -and -not $stopIssued) {
            Write-Log 'Nvpwr 正在运行，执行 sc stop Nvpwr...'
            Invoke-HiddenProcess -FilePath 'sc.exe' -Arguments 'stop Nvpwr' | Out-Null
            $stopIssued = $true
        }
        elseif ($state -eq 'STOP_PENDING' -and -not $stopIssued) {
            Write-Log 'Nvpwr 处于 STOP_PENDING，等待进入 STOPPED...'
            $stopIssued = $true
        }
        elseif ($state -eq 'START_PENDING') {
            Write-Log 'Nvpwr 处于 START_PENDING，等待状态稳定...'
        }

        Start-Sleep -Milliseconds 500
    }

    $state = Get-NvpwrServiceState
    if ($state -ne 'STOPPED' -and $state -ne 'ABSENT') {
        throw "Nvpwr 服务未能进入 STOPPED（最终状态：$state）。"
    }

    Write-Log '启动 Nvpwr 内核服务...'
    $r = Invoke-HiddenProcess -FilePath 'sc.exe' -Arguments 'start Nvpwr'
    Write-Log ("sc start 退出码={0} 输出={1} 错误={2}" -f $r.ExitCode, $r.StdOut.Trim(), $r.StdErr.Trim())
    if ($r.ExitCode -ne 0) { throw "启动 Nvpwr 服务失败：$($r.ExitCode)" }

    if (-not (Wait-NvpwrServiceState -Wanted 'RUNNING' -TimeoutSeconds 20)) {
        throw 'Nvpwr 服务未在超时内进入 RUNNING。'
    }
    Write-Log 'Nvpwr 服务已进入 RUNNING。'
}

<#
.SYNOPSIS
    重启本机唯一的 NVIDIA 显示设备。
.DESCRIPTION
    通过 Disable-PnpDevice / Enable-PnpDevice 强制重新枚举显卡，
    用于清除 Nvpwr 驱动读到的 MIXED 残留状态。
#>
function Restart-NvidiaGpu {
    Write-Log '开始重启 NVIDIA 显卡设备...'
    try {
        $devices = @(Get-PnpDevice -Class Display -PresentOnly | Where-Object {
            $_.InstanceId -like 'PCI\VEN_10DE*' -and $_.Status -ne 'Unknown'
        })
        if ($devices.Count -ne 1) {
            Write-Log ("必须且只能检测到一块 NVIDIA 显卡，当前检测到 {0} 块。跳过重启。" -f $devices.Count)
            return $false
        }

        $gpu = $devices[0]
        Write-Log ("正在禁用显卡：{0}" -f $gpu.FriendlyName)
        Disable-PnpDevice -InstanceId $gpu.InstanceId -Confirm:$false
        Start-Sleep -Seconds 3

        Write-Log '正在启用显卡...'
        Enable-PnpDevice -InstanceId $gpu.InstanceId -Confirm:$false
        Start-Sleep -Seconds 5

        $after = Get-PnpDevice -InstanceId $gpu.InstanceId
        Write-Log ("显卡重启完成，当前状态：{0}" -f $after.Status)
        return $true
    }
    catch {
        Write-Log ("重启显卡失败：{0}" -f $_.Exception.Message)
        return $false
    }
}

# ============================================================
#  功耗设置核心流程
# ============================================================

<#
.SYNOPSIS
    执行一次 set 调用并校验结果。
.DESCRIPTION
    返回值：
        Success           设置成功
        LowBoundExceeded  目标低于驱动允许的最小值，永久失败
        Transient         其他失败，可重试
#>
function Invoke-SetAndVerify {
    param(
        [Parameter(Mandatory = $true)][string]$CtlPath,
        [Parameter(Mandatory = $true)][string]$ProfileStr,
        [Parameter(Mandatory = $true)][int]$TargetWatts,
        [Parameter(Mandatory = $true)][long]$TargetRaw
    )

    Write-Log ("执行 set {0} {1}" -f $ProfileStr, $TargetWatts)
    $r = Invoke-HiddenProcess -FilePath $CtlPath -Arguments "set $ProfileStr $TargetWatts"
    $combined = "$($r.StdOut)`r`n$($r.StdErr)"
    $post = Parse-NvpwrCtlOutput -Text $combined
    Write-Log ("set 退出码={0} State={1} F7input={2} UPPER={3} CurrentF7={4} Win32={5}" -f `
        $r.ExitCode, $post.State, $post.F7Input, $post.Upper, $post.CurrentF7, $post.Win32Error)

    if ($r.ExitCode -eq 0 -and ($null -eq $post.CurrentF7 -or $post.CurrentF7 -eq $TargetRaw)) {
        Write-Log ("成功：Current F7 = {0}（目标 {1} W）" -f $post.CurrentF7, $TargetWatts)
        return 'Success'
    }

    if ($null -ne $post.F7Input -and $post.F7Input -gt 0 -and $TargetRaw -lt $post.F7Input) {
        Write-Log ("目标 {0} W 低于驱动允许的最小值 {1} W，永久失败。" -f `
            $TargetWatts, ($post.F7Input / 1000))
        return 'LowBoundExceeded'
    }

    Write-Log 'set 未成功，判为瞬态失败。'
    return 'Transient'
}

<#
.SYNOPSIS
    执行一次功耗设置尝试。
.DESCRIPTION
    流程：
        1. 加载后固定等待 5 秒，模拟原版 GUI 用户点击前的天然延迟。
        2. 调用 NvpwrCtl.exe set <profile> <watts>。
        3. 校验 Current F7 是否等于目标值。
#>
function Invoke-PowerAttempt {
    param(
        [Parameter(Mandatory = $true)][string]$CtlPath,
        [Parameter(Mandatory = $true)][string]$ProfileStr,
        [Parameter(Mandatory = $true)][int]$TargetWatts,
        [Parameter(Mandatory = $true)][long]$TargetRaw
    )

    Start-Sleep -Seconds 5
    return (Invoke-SetAndVerify -CtlPath $CtlPath -ProfileStr $ProfileStr `
        -TargetWatts $TargetWatts -TargetRaw $TargetRaw)
}

# ============================================================
#  主流程
# ============================================================

$script:CtlPath = Join-Path $Root 'NvpwrCtl.exe'

# -------- 权限检查 --------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if (-not $isAdmin) {
    Write-Log '未以管理员身份运行，退出。'
    exit 1
}

# -------- 目标功耗解析 --------
$targetWatts = Get-TargetWattsFromFileName -ExeFullPath $ExePath
$targetRaw   = [long]$targetWatts * 1000

$dseDisabled = $false
$dseRestored = $false
$succeeded   = $false

try {
    Write-Log '===== 开始设置显卡功耗 ====='
    Write-Log ("exe 路径：{0}" -f $ExePath)
    Write-Log ("解析目标功耗：{0} W（原始文件名：{1}）" -f $targetWatts, ([System.IO.Path]::GetFileName($ExePath)))

    # -------- 依赖文件检查 --------
    foreach ($file in @('EfiDSEFix.exe', 'Nvpwr.sys', 'NvpwrCtl.exe')) {
        $path = Join-Path $Root $file
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "缺少文件：$path" }
    }
    Write-Log '必需文件检查通过。'

    # -------- 硬件识别 --------
    $gpuName = Get-NvidiaGpuName
    if ([string]::IsNullOrWhiteSpace($gpuName)) {
        throw '未检测到 NVIDIA 显卡。'
    }
    $profileStr = Get-NvpwrProfileFromGpuName -GpuName $gpuName
    if ([string]::IsNullOrWhiteSpace($profileStr)) {
        throw "无法从 GPU 名识别 Nvpwr profile：$gpuName"
    }
    Write-Log ("检测到 GPU：{0}" -f $gpuName)
    Write-Log ("使用 Nvpwr profile：{0}" -f $profileStr)

    # -------- 临时关闭驱动签名强制 --------
    Write-Log '执行 EfiDSEFix -d 临时关闭驱动签名强制...'
    $r = Invoke-HiddenProcess -FilePath (Join-Path $Root 'EfiDSEFix.exe') -Arguments '-d'
    $dseDisabled = $true
    Write-Log ("EfiDSEFix -d 退出码={0} 输出={1} 错误={2}" -f $r.ExitCode, $r.StdOut.Trim(), $r.StdErr.Trim())

    Start-Sleep -Seconds 2

    $driverPath = (Resolve-Path -LiteralPath (Join-Path $Root 'Nvpwr.sys')).Path

    # -------- 加载服务 --------
    Install-NvpwrService -DriverPath $driverPath

    # -------- 第一次尝试 --------
    Write-Log '--- 第一次尝试 ---'
    $result = Invoke-PowerAttempt -CtlPath $script:CtlPath -ProfileStr $profileStr `
        -TargetWatts $targetWatts -TargetRaw $targetRaw

    if ($result -eq 'Success') {
        $succeeded = $true
    }
    elseif ($result -eq 'LowBoundExceeded') {
        Write-Log '目标低于驱动最小值，永久失败，不重启显卡。'
    }
    else {
        # 瞬态失败：先 restore 归一化，再 set 一次。
        Write-Log '第一次尝试失败，尝试 restore 归一化后再 set...'
        $rst = Invoke-HiddenProcess -FilePath $script:CtlPath -Arguments 'restore'
        Write-Log ("restore 退出码={0}" -f $rst.ExitCode)
        Start-Sleep -Seconds 2

        $retryR = Invoke-HiddenProcess -FilePath $script:CtlPath -Arguments "set $profileStr $targetWatts"
        $retryCombined = "$($retryR.StdOut)`r`n$($retryR.StdErr)"
        $retryInfo = Parse-NvpwrCtlOutput -Text $retryCombined
        Write-Log ("restore+set 退出码={0} State={1} CurrentF7={2} Win32={3}" -f `
            $retryR.ExitCode, $retryInfo.State, $retryInfo.CurrentF7, $retryInfo.Win32Error)

        if ($retryR.ExitCode -eq 0 -and ($null -eq $retryInfo.CurrentF7 -or $retryInfo.CurrentF7 -eq $targetRaw)) {
            Write-Log ("成功（restore 后重试）：Current F7 = {0}" -f $retryInfo.CurrentF7)
            $succeeded = $true
        }
        else {
            # 仍然失败：重启显卡 + 强制重建服务，再试一次。
            Write-Log 'restore 后重试仍失败，重启显卡并重建服务后重试...'
            $restarted = Restart-NvidiaGpu
            if ($restarted) {
                Start-Sleep -Seconds 5
                try {
                    Install-NvpwrService -DriverPath $driverPath -ForceRecreate

                    Write-Log '--- 第二次尝试（显卡重启后） ---'
                    $result2 = Invoke-PowerAttempt -CtlPath $script:CtlPath -ProfileStr $profileStr `
                        -TargetWatts $targetWatts -TargetRaw $targetRaw
                    if ($result2 -eq 'Success') {
                        $succeeded = $true
                    }
                    else {
                        Write-Log ("第二次尝试失败，最终结果：{0}" -f $result2)
                    }
                }
                catch {
                    Write-Log ("重试阶段异常：{0}" -f $_.Exception.Message)
                }
            }
            else {
                Write-Log '显卡重启失败，无法继续重试。'
            }
        }
    }
}
catch {
    Write-Log ("错误：{0}" -f $_.Exception.Message)
}
finally {
    # -------- 恢复驱动签名强制（主路径） --------
    if ($dseDisabled -and -not $dseRestored) {
        try {
            Write-Log '执行 EfiDSEFix -e 恢复驱动签名强制...'
            $r = Invoke-HiddenProcess -FilePath (Join-Path $Root 'EfiDSEFix.exe') -Arguments '-e'
            Write-Log ("EfiDSEFix -e 退出码={0} 输出={1} 错误={2}" -f $r.ExitCode, $r.StdOut.Trim(), $r.StdErr.Trim())
        }
        catch {
            Write-Log ("恢复 DSE 失败：{0}" -f $_.Exception.Message)
        }
        $dseRestored = $true
    }

    # -------- 恢复驱动签名强制（备用路径） --------
    # 无论前面是否执行过 -e，这里再执行一次，确保 DSE 一定回到开启状态。
    try {
        Write-Log '备用：再次执行 EfiDSEFix -e...'
        $r = Invoke-HiddenProcess -FilePath (Join-Path $Root 'EfiDSEFix.exe') -Arguments '-e'
        Write-Log ("备用 EfiDSEFix -e 退出码={0} 输出={1} 错误={2}" -f $r.ExitCode, $r.StdOut.Trim(), $r.StdErr.Trim())
    }
    catch {
        Write-Log ("备用恢复 DSE 失败：{0}" -f $_.Exception.Message)
    }

    # -------- 停止 Nvpwr 服务 --------
    try {
        $r = Invoke-HiddenProcess -FilePath 'sc.exe' -Arguments 'stop Nvpwr'
        Write-Log ("sc stop 退出码={0}" -f $r.ExitCode)
    }
    catch { }

    Write-Log ("===== 结束 成功={0} =====" -f $succeeded)
}
