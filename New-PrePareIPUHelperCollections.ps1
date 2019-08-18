Function New-QueryBasedCollectionInFolder($Name, $Query, $QueryName, $Folder, $Schedule, $LimitingCollectionName) {
    $Col = New-CMDeviceCollection -Name $Name -LimitingCollectionName $LimitingCollectionName -RefreshSchedule $Schedule -RefreshType Periodic
    Add-CMDeviceCollectionQueryMembershipRule -CollectionName $Name -QueryExpression $Query -RuleName $QueryName
    Move-CMObject -FolderPath $Folder -InputObject (Get-CMDeviceCollection -Name $Col.Name)

}

#region Create Root Folder
New-Item -Name 'In-Place Upgrade' -Path ".\DeviceCollection"
#endregion

#region Create Collections

$ModayEvening = New-CMSchedule -Start "01/01/2019 11:00 PM" -DayOfWeek Monday -RecurCount 1
$Folder = ".\DeviceCollection\In-Place Upgrade" 


$ColName1 = "0. Win10 Machines"
$Query = 'select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System where OperatingSystemNameandVersion like ''%Workstation 10.0%'''
New-QueryBasedCollectionInFolder -Name $ColName1 -Query $Query -QueryName "All Win10" -Folder $Folder -Schedule $ModayEvening -LimitingCollectionName "All Systems"


$ColName2 = "1. Prepare Win10 IPU"
New-CMDeviceCollection -Name $ColName2 -LimitingCollectionName $ColName1 -RefreshType None | Out-Null
Move-CMObject -FolderPath $Folder -InputObject (Get-CMDeviceCollection -Name $ColName2)


$ColName3 = "2. Ready for Win10 IPU [Change DeploymentID]"
$Query = 'select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System inner join SMS_ClassicDeploymentAssetDetails on SMS_ClassicDeploymentAssetDetails.DeviceID = SMS_R_System.ResourceID where SMS_ClassicDeploymentAssetDetails.DeploymentID = ''CHANGEMEHERE'' and SMS_ClassicDeploymentAssetDetails.StatusType = ''1'''
New-QueryBasedCollectionInFolder -Name $ColName3 -Query $Query -QueryName "Success of Prepare Win10 IPU" -Folder $Folder -Schedule $ModayEvening -LimitingCollectionName $ColName2


$ColName4 = "3. Deploy Win10 IPU"
New-CMDeviceCollection -Name $ColName4 -LimitingCollectionName $ColName3 -RefreshType None | Out-Null
Move-CMObject -FolderPath $Folder -InputObject (Get-CMDeviceCollection -Name $ColName4)


$ColName5 = "4. Failed Prepare Win10 IPU [Change DeploymentID]"
$Query = 'select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System inner join SMS_ClassicDeploymentAssetDetails on SMS_ClassicDeploymentAssetDetails.DeviceID = SMS_R_System.ResourceID where SMS_ClassicDeploymentAssetDetails.DeploymentID = ''CHANGEMEHERE'' and SMS_ClassicDeploymentAssetDetails.StatusType = ''5'''
New-QueryBasedCollectionInFolder -Name $ColName5 -Query $Query -QueryName "Failed Prepare Win10 IPU (Status Type 5)" -Folder $Folder -Schedule $ModayEvening -LimitingCollectionName $ColName1


$ColName6 = "5. Failed Win10 IPU"
$Query = 'select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System where SMS_R_System.ResourceId in (select ResourceID from SMS_SUMDeploymentAssetDetails where LastEnforcementMessageID = 6  and iscompliant != ''1'' and AssignmentUniqueID = ''{16779344}'')'
New-QueryBasedCollectionInFolder -Name $ColName6 -Query $Query -QueryName "Failed Win10 IPU (Update Status Message)" -Folder $Folder -Schedule $ModayEvening -LimitingCollectionName $ColName4

Write-Host "It may take a few minutes for the collections to appear"

#endregion