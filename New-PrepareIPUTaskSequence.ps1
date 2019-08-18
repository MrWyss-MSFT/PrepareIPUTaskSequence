$TaskSequenceName = "Template Prepare In-Place Upgrade"
$Languages = "DE-DE", "FR-FR", "IT-IT"

#region Create Dummy Package
if ($Null -eq (Get-CMPackage -Name "Dummy [Driver] Package Package" -Fast)) {
    $DummyPackagePath = New-Item -Path c:\temp\dummy -ItemType directory -Force
    $DummyPackage = New-CMPackage -Name "Dummy [Driver] Package Package" -Path $DummyPackagePath -Description "Can be driver package or a regular package"
}
else {
    $DummyPackage = Get-CMPackage -Name "Dummy [Driver] Package Package" -Fast
}
#endregion

#region Create a new Task Sequence
$TS = New-CMTaskSequence -CustomTaskSequence -Name $TaskSequenceName
#endregion

#region Create the Root Group
$PrepareIPUGroup = New-CMTaskSequenceGroup -Name "Prepare IPU"
Add-CMTaskSequenceStep -InsertStepStartIndex 0 -TaskSequenceName $TS.Name -Step $PrepareIPUGroup
#endregion

#region Check Readiness Step
$CheckReadinessArgs = @{
    Name        = "Check Readiness"
    CheckMemory = $True
    Memory      = 2000
    CheckSpeed  = $True
    Speed       = 1000
    CheckSpace  = $True
    DiskSpace   = 20000
    CheckOS     = $True
    OS          = "Client"
}
$PrestartCheckStep = New-CMTSStepPrestartCheck @CheckReadinessArgs

Set-CMTaskSequenceGroup -TaskSequenceName $TS.Name -StepName $PrepareIPUGroup.Name -AddStep $PrestartCheckStep -InsertStepStartIndex 0 
#endregion

#region LanguageDetection Step
$LanguageDetectionScript = {
    # Script OSDDetectInstalledLP.ps1 - Version 170810
    # 161008 - Added OSArchitecture and OSVersion detection
    # 161009 - Added OSSKU detection
    # 170118 - Added LTSB to SKU List and fixed architecture detection for spanish installations which return 64-Bits
    # 170810 - Changed UILanguage detection (feedback from blog post - Kudos to Dan)
    # ----------------------------------------------------------------------------------------------------------------------------------------
    # ***** Disclaimer *****
    # This file is provided "AS IS" with no warranties, confers no 
    # rights, and is not supported by the authors or Microsoft 
    # Corporation. Its use is subject to the terms specified in the 
    # Terms of Use (http://www.microsoft.com/info/cpyright.mspx).
    # ----------------------------------------------------------------------------------------------------------------------------------------
    # Purpose of this script is to easily detect all languages installed on the current OS
    # Additional information like OS Version, Architecture and OSSKU will be enumerated as well
    # After running this Script inside a Task Sequence zou will have folloging variables accessable
    # OSVersion - Sample Value: 6.3.9600
    # OSArchitecture - Sample Value: 64-Bit
    # OSSKU - Sample Value: ENTERPRISE
    # CurrentOSLanguage - Sample Value: de-de
    # MUILanguageCount - Sample Value: 2
    # OSDDefaultUILanguage - Sample Value: de-de (is only applicable if OSDRegionalSettings.ps1 was used to install device)
    # Dynamic Variable where Name matches the detected Language for example de-de - Sample Value: True
    # ----------------------------------------------------------------------------------------------------------------------------------------
    # Declare Variables
    # ----------------------------------------------------------------------------------------------------------------------------------------

    [String]$LogFile = "$env:WinDir\CCM\Logs\" + $($((Split-Path $MyInvocation.MyCommand.Definition -leaf)).replace("ps1", "log"))
    #[String]$ScriptPath = split-path $SCRIPT:MyInvocation.MyCommand.Path -parent
    [String]$CurrentOSLanguage

    # ----------------------------------------------------------------------------------------------------------------------------------------
    # Function Section
    # ----------------------------------------------------------------------------------------------------------------------------------------

    Function Write-ToLog([string]$message, [string]$file) {
        <#
    .SYNOPSIS
        Writing log to the logfile
    .DESCRIPTION
        Function to write logging to a logfile. This should be done in the End phase of the script.
    #>
        If (-not($file)) { $file = $LogFile }        
        $Date = $(get-date -uformat %Y-%m-%d-%H.%M.%S)
        $message = "$Date `t$message"
        Write-Verbose $message
        Write-Host $message
        #Write Log to log file Without ASCII not able to read with tracer.
        Out-File $file -encoding ASCII -input $message -append
    }

    Try {
        $tsenv = New-Object -COMObject Microsoft.SMS.TSEnvironment
        Write-ToLog "Script is running inside a Task Sequence"
        $RunningInTs = $True
    }
    Catch {
        Write-ToLog "Script is running outside a Task Sequence"
    }

    $WMIResult = get-wmiobject -class "Win32_OperatingSystem" -namespace "root\CIMV2"

    foreach ($objItem in $WMIResult) {
        $MUILanguageCount = $objItem.MUILanguages.count
        $OSArchitecture = $objItem.OSArchitecture
        If ($OSArchitecture -match "32") { $OSArchitecture = "32-Bit" }
        If ($OSArchitecture -match "64") { $OSArchitecture = "64-Bit" }
        $OSVersion = $objItem.Version
        $OperatingSystemSKU = $objItem.OperatingSystemSKU
        Write-ToLog "OSVersion detected: $OSVersion"
        If ($RunningInTs) { $tsenv.Value("OSVersion") = $OSVersion }
        Write-ToLog "OSArchitecture detected: $OSArchitecture"
        If ($RunningInTs) { $tsenv.Value("OSArchitecture") = $OSArchitecture }
        $OSSKU = switch ($OperatingSystemSKU) { 
            1 { "ULTIMATE" } 
            4 { "ENTERPRISE" } 
            5 { "BUSINESS" }
            7 { "STANDARD_SERVER" }
            10 { "ENTERPRISE_SERVER" }
            27 { "ENTERPRISE_N" } 
            28 { "ULTIMATE_N" }
            48 { "PROFESSIONAL" } 
            125 { "ENTERPRISE_LTSB" } 
            default { "UNKNOWN" }
        }
        Write-ToLog "OSSKU $OperatingSystemSKU detected: $OSSKU"
        If ($RunningInTs) { $tsenv.Value("OSSKU") = $OSSKU }

        ForEach ($Mui in $objItem.MUILanguages) {
            Write-ToLog "MUILanguage: $Mui"
            If ($RunningInTs) { $tsenv.Value($Mui) = $True }
        }
        $LCID = $objItem.OSLanguage
        Write-ToLog "Current LCID detected: $LCID"
    } 

    Write-ToLog "MUILanguage Count: $MUILanguageCount"

    If ($MUILanguageCount -gt 1) {
        Write-ToLog "MUIdetected: True"
        If ($RunningInTs) {
            $tsenv.Value("MUIdetected") = $True
        }
    } 
    <#
# Translate LCID information to locale information sample 1031 to en-us
# Convert $LCID to HEX
$LCID = [Convert]::ToString($LCID, 16)
# ensure $LCID is 4 digits
If($LCID.Length -eq 3){$LCID = "0"+$LCID} 

$CurrentOSLanguageLCID = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Classes\MIME\Database\Rfc1766' -Name $LCID).$LCID -split ";"
If($CurrentOSLanguageLCID[0].Length -eq 2)
    {
        $CurrentOSLanguage = ($CurrentOSLanguageLCID[0]+"-"+$CurrentOSLanguageLCID[0])
    }
    Else
    {
        $CurrentOSLanguage = $CurrentOSLanguageLCID[0]
    }
#>

    # Using PowerShell to detect OS Language - Feedback from Dan blog post (http://aka.ms/osdsupportteam
    $CurrentOSLanguage = (Get-UICulture).Name


    Write-ToLog "Detected current OS Language: $CurrentOSLanguage"
    If ($RunningInTs) { $tsenv.Value("CurrentOSLanguage") = $CurrentOSLanguage }

    # Just in case OSDRegionalSettings.ps1 has been used for bare metal install check for Get-WinUILanguageOverride
    Try {
        $OSDDefaultUILanguage = Get-WinUILanguageOverride
        If ($OSDDefaultUILanguage -eq $Null) {
            Write-ToLog "No UI Language Override detected"
        }
        Else {
            Write-ToLog "WinUILanguageOverride detected variable OSDDefaultUILanguage set to value: $OSDDefaultUILanguage"
            If ($RunningInTs) { $tsenv.Value("OSDDefaultUILanguage") = $OSDDefaultUILanguage }
        }
    }
    catch {
        Write-ToLog "No UI Language Override detected"
    }

}
$LanguageDetectionArgs = @{
    Name            = "Detect Language Packs"
    SourceScript    = $LanguageDetectionScript
    ExecutionPolicy = "Bypass"

}
$LanguageDetectionStep = New-CMTSStepRunPowerShellScript @LanguageDetectionArgs
Set-CMTaskSequenceGroup -TaskSequenceName $TS.Name -StepName $PrepareIPUGroup.Name -AddStep $LanguageDetectionStep -InsertStepStartIndex 1
#endregion

#region Create the Multi Language System Group with Condition
$MultiLanguageGroupCondition = New-CMTaskSequenceStepConditionVariable -OperatorType Equals -ConditionVariableName "MUIdetected" -ConditionVariableValue "True"
$MultiLanguageGroup = New-CMTaskSequenceGroup -Name "Multi Language System Group" -Condition $MultiLanguageGroupCondition
Set-CMTaskSequenceGroup -TaskSequenceName $TS.Name -StepName $PrepareIPUGroup.Name -AddStep $MultiLanguageGroup -InsertStepStartIndex 2 
#endregion

#region Set TSVar LanguagePack Download Path
$LangPackDownloadPathTSVarArgs = @{
    Name                      = "Set TSVar LanguagePack Download Path"
    TaskSequenceVariable      = "SetupConfig_InstallLangPacks"
    TaskSequenceVariableValue = "c:\Windows\Temp\IPU\LP"
   
}
$LangPackDownloadPathTSVarStep = New-CMTSStepSetVariable @LangPackDownloadPathTSVarArgs
Set-CMTaskSequenceGroup -TaskSequenceName $TS.Name -StepName $MultiLanguageGroup.Name -AddStep $LangPackDownloadPathTSVarStep -InsertStepStartIndex 0
#endregion

#region Download Language Pack Steps
Foreach ($Language in $Languages) { 
    $DownloadLanguagePackArgs = @{
        Name                = "Download Language Pack & FOD $Language"
        Path                = "%SetupConfig_InstallLangPacks%"
        DestinationVariable = "LanguagePacksExist"
        LocationOption      = "CustomPath"
        AddPackage          = $DummyPackage
    }
    $DownloadLanguagePackStepCondition = New-CMTaskSequenceStepConditionVariable -OperatorType Exists -ConditionVariableName $Language
    $DownloadLanguagePackStep = New-CMTSStepDownloadPackageContent @DownloadLanguagePackArgs -Condition $DownloadLanguagePackStepCondition
    Set-CMTaskSequenceGroup -TaskSequenceName $TS.Name -StepName $MultiLanguageGroup.Name -AddStep $DownloadLanguagePackStep  -InsertStepStartIndex 1
}
#endregion

#region Create the Drivers Group
$DriversGroup = New-CMTaskSequenceGroup -Name "Drivers" -Disable
Set-CMTaskSequenceGroup -TaskSequenceName $TS.Name -StepName $PrepareIPUGroup.Name -AddStep $DriversGroup -InsertStepStartIndex 3
#endregion

#region Set TSVar Drivers Download Path
$DriversDownloadPathTSVarArgs = @{
    Name                      = "Set TSVar Drivers Download Path"
    TaskSequenceVariable      = "SetupConfig_InstallDrivers"
    TaskSequenceVariableValue = "c:\Windows\Temp\IPU\Drivers"
   
}
$DriversDownloadPathTSVarStep = New-CMTSStepSetVariable @DriversDownloadPathTSVarArgs
Set-CMTaskSequenceGroup -TaskSequenceName $TS.Name -StepName $DriversGroup.Name -AddStep $DriversDownloadPathTSVarStep -Description "Only use Win10 n+1 Drivers that don't work on the current Version"  -InsertStepStartIndex 0
#endregion

#region Download Drivers Step
$DownloadDriversArgs = @{
    Name                = "Download Virtual Machines Drivers"
    LocationOption      = "CustomPath"
    Path                = "%SetupConfig_InstallDrivers%"
    DestinationVariable = "DriversExist"
    AddPackage          = $DummyPackage
}
$DownloadDriversStepCondition = New-CMTaskSequenceStepConditionQueryWMI -Namespace "root\cimv2" -Query 'SELECT * FROM Win32_ComputerSystem WHERE Model LIKE "%Virtual Machine%"'
$DownloadDriversStep = New-CMTSStepDownloadPackageContent @DownloadDriversArgs -Condition $DownloadDriversStepCondition
Set-CMTaskSequenceGroup -TaskSequenceName $TS.Name -StepName $DriversGroup.Name -AddStep $DownloadDriversStep -InsertStepStartIndex 1
#endregion

#region Create the 3rd Party Disk Encryption Group
$3rdPartyEncGroup = New-CMTaskSequenceGroup -Name "3rd Party Disk Encryption" -Disable
Set-CMTaskSequenceGroup -TaskSequenceName $TS.Name -StepName $PrepareIPUGroup.Name -AddStep $3rdPartyEncGroup  -InsertStepStartIndex 4
#endregion

#region Set TSVar 3rdParty Download Path
$3rdPartyEncTSVarArgs = @{
    Name                      = "Set TSVar Disk Encryption Download Path"
    TaskSequenceVariable      = "SetupConfig_ReflectDrivers"
    TaskSequenceVariableValue = "c:\Windows\Temp\IPU\Disk"
   
}
$3rdPartyEncTSVarStep = New-CMTSStepSetVariable @3rdPartyEncTSVarArgs
Set-CMTaskSequenceGroup -TaskSequenceName $TS.Name -StepName $3rdPartyEncGroup.Name -AddStep $3rdPartyEncTSVarStep -InsertStepStartIndex 0 -Description "Use this if your 3rd Party Diskencryption requires drivers for the IPU"
#endregion

#region Download 3rd Party Encryption Step
$Download3rdPartyEncArgs = @{
    Name                = "Download 3rd Party Disk Encryption"
    LocationOption      = "CustomPath"
    Path                = "%SetupConfig_ReflectDrivers%"
    DestinationVariable = "DiskEncryptionExist"
    AddPackage          = $DummyPackage
}
$Download3rdPartyEncStep = New-CMTSStepDownloadPackageContent @Download3rdPartyEncArgs
Set-CMTaskSequenceGroup -TaskSequenceName $TS.Name -StepName $3rdPartyEncGroup.Name -AddStep $Download3rdPartyEncStep -InsertStepStartIndex 1
#endregion

#region Create the Additional Setup Params Group
$AdditionsSetupGroup = New-CMTaskSequenceGroup -Name "Additional Setup Parameters" 
Set-CMTaskSequenceGroup -TaskSequenceName $TS.Name -StepName $PrepareIPUGroup.Name -AddStep $AdditionsSetupGroup -InsertStepStartIndex 5
#endregion

#region Set TSVar Priority
$AdditionsSetupParamsTSVarArgs = @{
    Name                      = "Priority = Normal"
    TaskSequenceVariable      = "SetupConfig_Priority"
    TaskSequenceVariableValue = "Normal"
    Description               = "Prefix = SetupConfig_"
   
}
$AdditionsSetupParamsTSVarStep = New-CMTSStepSetVariable @AdditionsSetupParamsTSVarArgs
Set-CMTaskSequenceGroup -TaskSequenceName $TS.Name -StepName $AdditionsSetupGroup.Name -AddStep $AdditionsSetupParamsTSVarStep -InsertStepStartIndex 0 -Description "https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-setup-command-line-options" 
#endregion

#region Create the Setupconfig.ini Group
$SetupConfigINIGroup = New-CMTaskSequenceGroup -Name "Setupconfig.ini"
Set-CMTaskSequenceGroup -TaskSequenceName $TS.Name -StepName $PrepareIPUGroup.Name -AddStep $SetupConfigINIGroup -InsertStepStartIndex 6
#endregion

#region Setupconfig.ini PowerShell Step
$CreateSetupConfigIniScript = {

    #region Variables
    [String]$LogFile = "$env:WinDir\CCM\Logs\" + $($((Split-Path $MyInvocation.MyCommand.Definition -leaf)).replace("ps1", "log"))
    [String]$SetupConfigPath = $env:SystemDrive + "\Users\Default\AppData\Local\Microsoft\Windows\WSUS"
    [String]$SetupConfigFilePath = "$SetupConfigPath\SetupConfig.ini"
    #endregion

    #region Functions
    #region Write-ToLog
    Function Write-ToLog([string]$message, [string]$file) {
        <#
    .SYNOPSIS
        Writing log to the logfile
    .DESCRIPTION
        Function to write logging to a logfile. This should be done in the End phase of the script.
    #>
        If (-not($file)) { $file = $LogFile }        
        $Date = $(get-date -uformat %Y-%m-%d-%H.%M.%S)
        $message = "$Date `t$message"
        Write-Verbose $message
        Write-Host $message
        #Write Log to log file Without ASCII not able to read with tracer.
        Out-File $file -encoding ASCII -input $message -append
    }
    #endregion

    #region Out-IniFile
    Function Out-IniFile($InputObject, $FilePath) {
        $outFile = New-Item -ItemType file -Path $Filepath -Force
        foreach ($i in $InputObject.keys) {
            if (!($($InputObject[$i].GetType().Name) -eq "Hashtable")) {
                #No Sections
                Add-Content -Path $outFile -Value "$i=$($InputObject[$i])"
            }
            else {
                #Sections
                Add-Content -Path $outFile -Value "[$i]"
                Foreach ($j in ($InputObject[$i].keys | Sort-Object)) {
                    if ($j -match "^Comment[\d]+") {
                        Add-Content -Path $outFile -Value "$($InputObject[$i][$j])"
                    }
                    else {
                        Add-Content -Path $outFile -Value "$j=$($InputObject[$i][$j])" 
                    }
                }
                Add-Content -Path $outFile -Value ""
            }
        }
    }
    #endregion
    #endregion

    Try {
        $tsenv = New-Object -COMObject Microsoft.SMS.TSEnvironment
        Write-ToLog "Script is running inside a Task Sequence"
        $RunningInTs = $True
    }
    Catch {
        Write-ToLog "Script is running outside a Task Sequence"
    }

      
    
    if ($RunningInTs) {

        # Get All TS Vars and filter for SetupConfig.ini Parameters
        [hashtable]$SetupConfigIniParams = @{ }
        $AllTSVars = $tsenv.GetVariables()
        ForEach ($Var in $AllTSVars) { 
            if ($Var -like "SetupConfig_*") {
                $Value = $tsenv.Value($Var)
                $Name = $Var -replace ("SetupConfig_", "")
                Write-ToLog "Found TS Variable Value Pair: $Name = $Value"
                $SetupConfigIniParams.Add($Name, $Value)
            }
        }
        If ($SetupConfigIniParams.Count -gt 0) {
            Write-ToLog "Create SetupConfig.ini"
    
            #region Create Folder
            If (Test-Path -Path $SetupConfigPath -ne $True) {
                New-Item -Path $SetupConfigPath -ItemType directory -Force
                Write-ToLog "Create Folder: $SetupConfigPath"
            }
            else {
                Write-ToLog "Folder: $SetupConfigPath already exists"
            }
            #endregion
    
    
            #region Create SetupConfig.ini
            $SetupConfig = @{"SetupConfig" = $SetupConfigIniParams}
            Out-IniFile -InputObject $SetupConfig -FilePath $SetupConfigFilePath
            Write-ToLog "Created $SetupConfigFilePath"
            #endregion
            exit 0
    
    
        }
        else {
            Write-ToLog -message "SetupConfig.ini not required, cannot find TSVar Name beginning with SetupConfig_, exit script"
            exit 0
        }
    }
    else {
        Write-ToLog -message "End script as it has not been invoked by a Tasksequence"
        exit 0
    }
}

$SetupConfigPoshArgs = @{
    Name            = "Create Setupconfig.ini"
    SourceScript    = $CreateSetupConfigIniScript
    ExecutionPolicy = "Bypass"
}
$SetupConfigPoshStep = New-CMTSStepRunPowerShellScript @SetupConfigPoshArgs
Set-CMTaskSequenceGroup -TaskSequenceName $TS.Name -StepName $SetupConfigINIGroup.Name -AddStep $SetupConfigPoshStep -InsertStepStartIndex 0
#endregion