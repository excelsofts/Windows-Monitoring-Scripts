function Add-MonitisCustomMonitorUpdater
{
    <#
    .Synopsis
        Creates a new custom monitor updater command.
    .Description
        Creates a new custom monitor updater command.
    .Example
        Add-MonitisCustomMonitorUpdater -Name HardwareTracking -ScriptBlock {
            Get-WmiObject Win32_ComputerSystem
        } -Property PrimaryOwnerName, Manufacturer, Model
    .Example
        Add-MonitisCustomMonitorUpdater -Name OSAssetTracking -ScriptBlock {
            Get-WmiObject Win32_OperatingSystem         
        } -Property Caption, SerialNumber        
    .Example
        Add-MonitisCustomMonitorUpdater -Name PageFile -Property PageFilePercentUsed, ComputerName -ScriptBlock {
            Get-Counter '\Paging File(_total)\% Usage' | 
                Select-Object -ExpandProperty CounterSamples |
                Select-Object -Property @{
                    name='PageFilePercentUsed'
                    expression = {$_.CookedValue}
                },@{
                    name='ComputerName'
                    expression = {$env:COMPUTERNAME}
                }
        }    
    #>
    param(
    # The name of the monitor to update
    [Parameter(Mandatory=$true)]
    [string]
    $Name,        
       
   
    # The ScriptBlock that collects information for the update
    [ScriptBlock]$ScriptBlock,
    
    # One or more FailureConditions.  If the update matches this filter, 
    # a property named 'error' will be in the update.  'Error' will contain the errors
    # produced by the failure condition, or true if the filter returned items but no error was thrown
    [ScriptBlock[]]$FailureConditon,
    
    # The properties to commit to monitis.  Whenever the scriptblock runs, 
    # the updater will output the properties
    [Parameter(Mandatory=$true)]
    [string[]]$Property,        
    
    # The accounts to update when a failure occurs.  The account is either a name or a contact info (email, phone #)
    [string[]]$UpdateAccount,
    
    [string]$TriggerParameter,
    
    [string]$TriggerValue,
    
    [switch]$TriggerOnGreaterThan,
    
    [switch]$TriggerOnLessThan,
    
    # Send Report
    [switch]$SendReport,    

    # The Monitis API key.  
    # If any command connects to Monitis, the ApiKey and SecretKey will be cached.

    [string]$ApiKey,
    
    # The Monitis Secret key.  
    # If any command connects to Monitis, the ApiKey and SecretKey will be cached    

    [string]$SecretKey
    )
    process {
        #region Reconnect To Monitis
        if ($psBoundParameters.ApiKey -and $psBoundParameters.SecretKey) {
            Connect-Monitis -ApiKey $ApiKey -SecretKey $SecretKey
        } elseif ($script:ApiKey -and $script:SecretKey) {
            Connect-Monitis -ApiKey $script:ApiKey -SecretKey $script:SecretKey
        }
        
        if (-not $apiKey) { $apiKey = $script:ApiKey } 
        
        if (-not $script:AuthToken) 
        {
            Write-Error "Must connect to Monitis first.  Use Connect-Monitis to connect"
            return
        } 
        #endregion    
        
        $dryRun = & $ScriptBlock |
            Select-Object $property
            
        if (-not $dryRun) {
        
            return
        }
                
        
        $first = $dryRun  |Select-Object -First 1 
        $types = foreach ($prop in $property) {
            $value = $first.$prop    
            if (($value -as [float]) -ne $null) {
                [float]
            } elseif (($value -as [int]) -ne $null) {
                [int]
            } elseif ($value -is [bool]) {
                [bool]
            } else {
                [string]
            }
        }
        
        try { 
            Add-MonitisCustomMonitor -Name $Name -Parameter $property -Type $types -ApiKey $script:ApiKey -SecretKey $script:SecretKey -ErrorAction Stop            
        } catch {
            $_ | Write-Error
        }
        
        if (-not $?) { return }
        if ($UpdateAccount) {
        $monitor = Get-MonitisCustomMonitor -Name $Name
        Get-MonitisContact | 
            Where-Object {
                $UpdateAccount -contains $_.Name -or
                $UpdateAccount -contains $_.ContactAccount
            } |
            ForEach-Object -Begin {
                $sendReportParameters = @{}
                if ($SendReport) {
                    $sendReportParameters.SendDailyReport = $true
                    $sendReportParameters.SendWeeklyReport = $true
                    $sendReportParameters.SendMonthlyReport = $true
                }
                if ($TriggerParameter) {
                    $sendReportParameters.TriggerParameter = $TriggerParameter
                }
                if ($psBoundParameters.TriggerValue) {
                    $sendReportParameters.TriggerValue = $TriggerValue
                }
                if ($psBoundParameters.TriggerOnGreaterThan) {
                    $sendReportParameters.TriggerOnGreaterThan = $TriggerOnGreaterThan
                }
                if ($psBoundParameters.TriggerOnLessThan) {
                    $sendReportParameters.TriggerOnLessThan = $TriggerOnLessThan
                }
            } {                
                Add-MonitisNotificationRule -TestId $monitor.MonitisTestId -ContactId $_.ContactId @sendReportParameters
            }                                
        }
        
        
$updater = [ScriptBlock]::Create("
function Update-Monitis${Name}
{
    <#
    .Synopsis
        Updates the custom monitor $name in Monitis
    .Description
        Runs and update script and updates the custom monitor $name in Monitis.
    .Example
        Update-Monitis${Name}
    .Link
        Add-CustomMonitorUpdater
    #>
    param()
        
    process {
        `$results = & {
            $ScriptBlock
        } | 
            Select-Object '$($property -join "','")' 
            
        if (-not `$results) { return }
        `$valueSet = @{}
        foreach (`$r in `$results) {
            foreach (`$prop in `$r.psObject.properties) {
                `$valueSet.(`$prop.Name) = try { `$prop.Value } catch {}
            }
        }
        Update-CustomMonitor -Name '$name' -Value `$valueSet -ValueOrder '$($property -join "','")' -ApiKey '$script:apikey' -SecretKey '$script:SecretKey'
    }    
}")       
        
        $updater | Set-Content "$psScriptRoot\UpdateCommands\Update-Monitis${Name}.ps1"
        Import-Module $psScriptRoot\Monitis.psd1 -Force -Global         
        Invoke-Expression "Update-Monitis${Name}"
        
    }
} 
