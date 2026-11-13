<#
.SYNOPSIS
  Bulk-creates Active Directory users from a CSV file.
.EXAMPLE
  .\New-LabUsers.ps1 -CsvPath .\new_hires.csv -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$CsvPath,
    [string]$Domain  = 'homelab.local',
    [string]$LogDir  = "$PSScriptRoot\logs"
)

Import-Module ActiveDirectory -ErrorAction Stop

# Department -> OU and group. Anything not listed here is rejected.
$domainDN = ($Domain.Split('.') | ForEach-Object { "DC=$_" }) -join ','
$departments = @{
    'IT'    = @{ OU = "OU=IT,OU=_Users,$domainDN";    Group = 'IT-Staff' }
    'HR'    = @{ OU = "OU=HR,OU=_Users,$domainDN";    Group = 'HR-Staff' }
    'Sales' = @{ OU = "OU=Sales,OU=_Users,$domainDN"; Group = 'Sales-Staff' }
}

$tempPassword = Read-Host 'Temporary password for new users' -AsSecureString
$results = @()
$row = 1

foreach ($user in (Import-Csv $CsvPath)) {
    $row++
    $first = $user.FirstName.Trim()
    $last  = $user.LastName.Trim()
    $dept  = $user.Department.Trim()
    $sam   = ($first.Substring(0,1) + $last).ToLower() -replace '[^a-z0-9]', ''

    if (-not $departments.ContainsKey($dept)) {
        $status = 'ERROR'; $note = "Unknown department '$dept'"
    }
    elseif (Get-ADUser -Filter "SamAccountName -eq '$sam'") {
        $status = 'SKIPPED'; $note = 'Already exists'
    }
    else {
        $target = $departments[$dept]
        if ($PSCmdlet.ShouldProcess("$sam in $($target.OU)", 'Create AD user')) {
            try {
                New-ADUser -Name "$first $last" -GivenName $first -Surname $last `
                    -SamAccountName $sam -UserPrincipalName "$sam@$Domain" `
                    -Department $dept -Path $target.OU `
                    -AccountPassword $tempPassword -ChangePasswordAtLogon $true `
                    -Enabled $true -ErrorAction Stop
                Add-ADGroupMember -Identity $target.Group -Members $sam -ErrorAction Stop
                $status = 'CREATED'; $note = "OU=$dept, group $($target.Group)"
            } catch {
                $status = 'ERROR'; $note = $_.Exception.Message
            }
        } else {
            $status = 'WHATIF'; $note = "Would create in OU=$dept"
        }
    }

    Write-Host ('{0,-8} row {1,-3} {2,-10} {3}' -f $status, $row, $sam, $note)
    $results += [pscustomobject]@{
        Time = Get-Date -Format s; Row = $row; User = $sam; Status = $status; Note = $note
    }
}

New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$logFile = Join-Path $LogDir ("provision_{0:yyyy-MM-dd_HHmm}.csv" -f (Get-Date))
$results | Export-Csv $logFile -NoTypeInformation
Write-Host "Done. Log saved to $logFile"
