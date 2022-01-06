[CmdletBinding()]
param (
    # Parameter help description
    [Parameter()]
    [string]
    $Path,

    # Parameter help description
    [Parameter()]
    [string]
    $LogPath="$($env:Temp)"
)

function Get-TimeStamp {
    Get-Date -Format "MM-dd-yyyy_HH.mm.ss"
}

function Get-RoundNumber {
    [CmdletBinding()]
    param (
        [Parameter()]
        [float]
        $number,

        [Parameter()]
        [int]
        $precision
    )

    $([MATH]::Round($number,$precision))
}

function Get-PrettySize {
    [CmdletBinding()]
    param (
        [Parameter()]
        [float]
        $bytes
    )

    $inverse = $false

    if($bytes -lt 0){
        $bytes = -$bytes
        $script:inverse = $true
    }

    switch ($bytes){
        ({$_ -ge 1KB}){
            $output = "$(Get-RoundNumber -number($bytes/1KB) -precision 2) KB"
        }
        ({$_ -ge 1MB}){
            $output = "$(Get-RoundNumber -number($bytes/1MB) -precision 2) MB"
        }
        ({$_ -ge 1GB}){
            $output = "$(Get-RoundNumber -number($bytes/1GB) -precision 2) GB"
        }
        ({$_ -ge 1TB}){
            $output = "$(Get-RoundNumber -number($bytes/1TB) -precision 2) TB"
        }
        default{
            $output = "$(Get-RoundNumber -number $bytes -precision 2) B"
        }
    }

    if($inverse){
        $output = "-$output"
    }

    $output
}

function Get-PrettyDuration {
    [CmdletBinding()]
    param (
        [Parameter()]
        [float]
        $milliseconds
    )

    switch ($milliseconds) {
        ({$_ -ge 3600000}){
            return "$(Get-RoundNumber -number $($milliseconds/3600000) -precision 2) hours"
        }
        ({$_ -ge 60000}){
            return "$(Get-RoundNumber -number $($milliseconds/60000) -precision 2) mins"
        }
        ({$_ -ge 1000}){
            return "$(Get-RoundNumber -number $($milliseconds/1000) -precision 2) secs"
        }
        Default {
            return "$(Get-RoundNumber -number $milliseconds -precision 2) ms"
        }
    }
}

function Update-Progress {
    [CmdletBinding()]
    param (
        [Parameter()]
        [int]
        $ID = 0,

        # Parameter help description
        [Parameter(Mandatory="true")]
        [string]
        $Action,

        # Parameter help description
        [Parameter()]
        [string]
        $Status,

        # Parameter help description
        [Parameter(Mandatory="true")]
        [long]
        $curstep,

        # Parameter help description
        [Parameter(Mandatory="true")]
        [long]
        $maxstep
    )
    $progress = ($curstep/$maxstep)*100
    if($progress -gt 100){
        LogAndConsole "WARN: Progress > 100, $Action : $Status"
        $curstep = 1
        $maxstep = 1
    }

    $pComplete = [MATH]::Round((($curstep/$maxstep)*100), 2)

    $params = @{
        Id          = $ID
        Activity    = $Action
        CurrentOperation = "Completed $curstep`/$maxstep ($pComplete%)"
        PercentComplete = $pComplete
    }

    if([string]::IsNullOrWhiteSpace($Status) -eq $false){
        $params.Status = $Status
    }

    if($pComplete -eq 100){
        $params.Completed = $true
    }

    if($($host.name) -eq "ConsoleHost"){
        Write-Progress @params
    }else{
        Clear-Host
        Write-Output "$($Params.Status) - $($Params.CurrentOperation)"
    }
}

function New-EventLogEntry {
    [CmdletBinding()]
    param (
        # Parameter help description
        [Parameter()]
        [string]
        $Message, 

        # Parameter help description
        [Parameter()]
        [string]
        $LogName = "Application", 


        # Parameter help description
        [Parameter()]
        [string]
        $Source = $script:SeqName, 

        # Parameter help description
        [Parameter()]
        [Int]
        $EventID = 1
    )

    switch -Wildcard ($Message) {
        'Err*' { $EntryType = "Error" }
        'Warn*' {$EntryType = "Warning"}
        Default {$EntryType = "Information" }
    }

    Write-EventLog -LogName $LogName -Source $Source -EntryType $EntryType -EventId $EventID -Message $Message
    New-LogEntry -Message $Message
}

function New-LogEntry {
    [CmdletBinding()]
    param (
        # Parameter help description
        [Parameter()]
        [string]
        $Message, 

        # Parameter help description
        [Parameter()]
        [string]
        $Path = $script:LogFile
    )

    if((Test-Path -Path $LogFile) -eq $false){
        New-Item -Path $Path -ItemType File -Force | Out-Null
    }

    Write-Verbose "$(Get-TimeStamp) $Message"
    Write-Output "$(Get-TimeStamp) $Message" | Out-File -FilePath $Path -Encoding default -Append
}

function LogAndConsole {
    [CmdletBinding()]
    param (
        # Parameter help description
        [Parameter()]
        [string]
        $Message,

        # Parameter help description
        [Parameter()]
        [string]
        $TextColor = "Cyan",

        # Parameter help description
        [Parameter()]
        [switch]
        $NoNewLine
    )

    New-LogEntry -Message $Message

    switch -Wildcard ($Message) {
        'Err*' { $TextColor = "Red" }
        'Warn*' {$TextColor = "Yellow"}
    }

    $Params = @{
        Object = "$(Get-TimeStamp) $Message"
        ForegroundColor = $TextColor
    }
    if($NoNewLine){
        $Params.NoNewLine = $true
    }

    Write-Host @Params
}

function LogBinaryData {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]
        $Path
    )

    if((Test-Path -Path $path) -eq $false){
        LogAndConsole "WARN: $Path not found"
        return
    }

    New-LogEntry "Retrieving binary information for $Path"
    $file = Get-Item -Path $Path
    New-LogEntry "PATH: $($file.FullName)"
    New-LogEntry "VERS: $($file.VersionInfo.ProductVersion)"
    New-LogEntry "SIZE: $($file.Length.ToString())"
    New-LogEntry "HASH: $((Get-FileHash -Path $($file.FullName).Hash))"
}

function Test-RegValue {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]
        $Path,
        
        # Parameter help description
        [Parameter()]
        [string]
        $ValueName,

        # Parameter help description
        [Parameter()]
        [switch]
        $PassThru
    )

    #path doesn't exist
    if((Test-Path -Path $path) -eq $false){
        return $false
    }

    #value is missing pr empty
    if([string]::IsNullOrWhiteSpace($(Get-ItemPropertyValue -Path $Path -Name $ValueName))){
        return $false
    }

    #path and value exist, and caller wants the value
    if($PassThru){
        return $(Get-ItemPropertyValue -Path $Path -Name $ValueName)
    }

    #value exists...
    return $true
}

function New-RegEntry {
    [CmdletBinding()]
    param (
        # Parameter help description
        [Parameter()]
        [string]
        $Path,

        # Parameter help description
        [Parameter()]
        [string]
        $ValueName,

        # Parameter help description
        [Parameter()]
        [string]
        $ValueData,

        # Parameter help description
        [Parameter()]
        [string]
        $type
    )

    if((Test-Path -Path $Path) -eq $false){
        New-LogEntry "Creating $Path"
        try{ New-Item -Path $Path -Force -ErrorAction Stop | Out-Null }
        catch{ LogAndConsole "ERR: $($_.Exception.Message)" }
    }

    New-LogEntry "Setting $Path|$ValueName to $ValueData"
    try{ New-ItemProperty -Path $path -Name $ValueName -Value $ValueData -PropertyType $type -Force -ErrorAction Stop | Out-Null }
    catch{ LogAndConsole "ERR: $($_.Exception.Message)" }

    if((Test-RegValue -Path $path -ValueName $valuename -PassThru) -eq $ValueData){
        New-LogEntry "Success!"
    }else{
        LogAndConsole "WARN: $Path|$ValueName could not be validated"
    }
}

function Start-Command {
    [CmdletBinding()]
    param (
        # Parameter help description
        [Parameter()]
        [string]
        $FilePath, 

        # Parameter help description
        [Parameter()]
        [string[]]
        $Arguments, 

        # Parameter help description
        [Parameter()]
        [string]
        $WorkingDir,

        # Parameter help description
        [Parameter()]
        [string]
        $MonitorFile,

        # Parameter help description
        [Parameter()]
        [switch]
        $DontWait,

        # Parameter help description
        [Parameter()]
        [switch]
        $NewWindow
    )

    BEGIN {
        $ErrorActionPreference = 'Stop'

        $retObj = [PSCustomObject]@{
            Action          = ""
            Command         = "$FilePath" 
            Arguments       = "$Arguments"
            PID             = 0
            RunTime         = 0
            ExitCode        = -2147023293
        }

        if((Test-Path -Path $FilePath) -eq $false){
            LogAndConsole "Err: $Command not found"
            $retObj.ExitCode = 3
            return $retObj
        }

        $LogGuid = $((New-GUID).GUID)
        $stdout = "$($env:temp)\$LogGuid.Out"
        $stderr = "$($env:temp)\$LogGuid.Err"

        if($MonitorFile) { $stdout = $MonitorFile }
    }

    PROCESS {
        $params = @{
            FilePath                = $FilePath
            RedirectStandardError   = $stderr
            RedirectStandardOut     = $stdout
            Wait                    = (!$DontWait)
            NoNewWindow             = (!$NewWindow)
            PassThru                = $true
        }

        if([string]::IsNullOrEmpty($Arguments) -eq $false){ $params.ArgumentList = $Arguments }
        if([string]::IsNullOrEmpty($WorkingDir) -eq $false){ $params.WorkingDir = $WorkingDir }

        try{
            New-EventLogEntry -Message "Calling $FilePath $Arguments"
            New-LogEntry -Message "Output logging to {$LogGuid}"
            $cmd = Start-Process @params
        }catch{
            LogAndConsole -Message "Err: $($_.Exception.Message)"
            $retObj.ExitCode = $_.Exception.HResult
            return $retObj
        }
    }

    END {
        if($DontWait){
            New-EventLogEntry "Command was launched (PID: $($cmd.id)) with the DontWait switch"
            return $cmd
        }

        if((Test-Path -Path $stdout) -eq $true){
            $cmdOut = Get-Content -Path $stdout -Raw
            if(([string]::IsNullOrWhiteSpace($cmdOut)) -eq $false){
                New-LogEntry "`r`n::CMDOUT:: `r`n$($cmdout.trim())`r`n::CMDOUT::"
            }
        }

        if((Test-Path -Path $stderr) -eq $true){
            $cmdErr = Get-Content -Path $stderr -Raw
            if(([string]::IsNullOrWhiteSpace($cmdErr)) -eq $false){
                LogAndConsole "`r`n::CMDERR:: `r`n$($cmdErr.trim())`r`n::CMDERR::"
            }
        }

        Remove-Item -Path $stderr, $stdout -Force -ErrorAction Ignore

        $RunTime = Get-PrettyDuration -milliseconds (((Get-Date -Date $cmd.ExitTime) - (Get-Date -Date $cmd.StartTime)).TotalSeconds * 1000)
        New-EventLogEntry "Command returned $($cmd.ExitCode)"

        $retObj.PID = $cmd.Id
        $retObj.ExitCode = $cmd.ExitCode
        $retObj.RunTime = $RunTime
        return $retObj
    }
}

$ScriptName = (Split-Path -Path "$($MyInvocation.MyCommand.Name)" -Leaf).Replace('.ps1', '')
$LogFile = "$LogPath\$ScriptName.log"
LogAndConsole "Starting $ScriptName"
LogAndConsole "Version 1.0"
LogAndConsole "Logging to $LogFile"


#Get Sequence Information 
[xml]$SequenceDefintion = Get-Content $Path
$SeqName = $SequenceDefintion.sequence.Name
$SeqVersion = $SequenceDefintion.sequence.Version
$actions = $SequenceDefintion.sequence.GetElementsByTagName("action")

#Create New Event Log Provider
New-EventLog -LogName "Application" -Source $SeqName
New-EventLogEntry -Message "$SeqName version $SeqVersion starting"
New-EventLogEntry -Message "There are $($actions.Count) actions on the sequence stack"

#$actions | Format-Table -AutoSize

$commandStatus = @()
$x=0

if((Test-RegValue -Path "HKLM:\Software\$SeqName" -ValueName "Status" -PassThru) -eq "Reboot"){
    [int]$x = $(Get-ItemPropertyValue -Path "HKLM:\Software\$SeqName" -Name "LastAction")
    $x++
    LogAndConsole "Existing Sequence Detected...Continuing With Action # $x"
}

for($i = $x; $i -lt ($actions.count); $i++){
    New-LogEntry "Running Step $($i + 1)" 
    $action = $actions[$i]
    Update-Progress -Action "Running Step $($i + 1)" -Status "$($action.name)" -curstep $i -maxstep (($actions.count))

    $command = Start-Command -FilePath $($action.filepath) -Arguments ($action.arguments) -WorkingDir $($action.workingdir)
    $command.Action = "$($action.name)"
    $commandStatus += $command

    if(($action.critical -eq "true") -and ($command.exitcode -ne 0)){
        LogAndConsole "Err: Critical Action Failed... ending sequence"
        break
    }

    if($action.reboot -eq $true){
        LogAndConsole "Warn: Action requires a reboot... "
        New-RegEntry -Path "HKLM:\Software\$SeqName" -ValueName "Status" -ValueData "Reboot"
        New-RegEntry -Path "HKLM:\Software\$SeqName" -ValueName "LastAction" -ValueData $i
        exit(3010)
    }
}
Update-Progress -Action "Completed..." -curstep $x -maxstep $($actions.count)

$commandStatus | Select Action, Command, Arguments, RunTime, ExitCode | Format-Table -AutoSize

New-RegEntry -Path "HKLM:\Software\$SeqName" -ValueName "Status" -ValueData "Completed"
New-RegEntry -Path "HKLM:\Software\$SeqName" -ValueName "LastAction" -ValueData $i
LogAndConsole "Sequence Complete"