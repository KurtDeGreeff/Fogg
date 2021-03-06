
function Write-Success
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Message
    )

    Write-Host $Message -ForegroundColor Green
}


function Write-Information
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Message
    )

    Write-Host $Message -ForegroundColor Magenta
}


function Write-Notice
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Message
    )

    Write-Host $Message -ForegroundColor Yellow
}


function Write-Fail
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Message
    )

    Write-Host $Message -ForegroundColor Red
}


function Test-PathExists
{
    param (
        [string]
        $Path
    )

    return (![string]::IsNullOrWhiteSpace($Path) -and (Test-Path $Path))
}


function Test-Empty
{
    param (
        $Value
    )

    if ($Value -eq $null)
    {
        return $true
    }

    if ($Value.GetType().Name -ieq 'string')
    {
        return [string]::IsNullOrWhiteSpace($Value)
    }

    $type = $Value.GetType().BaseType.Name.ToLowerInvariant()
    switch ($type)
    {
        'valuetype'
            {
                return $false
            }

        'array'
            {
                return (($Value | Measure-Object).Count -eq 0 -or $Value.Count -eq 0)
            }
    }

    return ([string]::IsNullOrWhiteSpace($Value) -or ($Value | Measure-Object).Count -eq 0 -or $Value.Count -eq 0)
}


function Test-ArrayEmpty
{
    param (
        $Values
    )

    if (Test-Empty $Values)
    {
        return $true
    }

    foreach ($value in $Values)
    {
        if (!(Test-Empty $value))
        {
            return $false
        }
    }

    return $true
}


function Test-VMs
{
    param (
        [Parameter(Mandatory=$true)]
        $VMs,

        [Parameter(Mandatory=$true)]
        $FoggObject,

        $OS
    )

    Write-Information "Verifying VM config sections"

    # get the count of VM types to create
    $vmCount = ($VMs | Measure-Object).Count
    if ($vmCount -eq 0)
    {
        throw 'No list of VMs was found in Fogg Azure configuration file'
    }

    # is there an OS section?
    $hasOS = ($OS -ne $null)

    # loop through each VM verifying
    foreach ($vm in $VMs)
    {
        # ensure each VM has a tag
        if (Test-Empty $vm.tag)
        {
            throw 'All VM sections in Fogg Azure configuration file require a tag name'
        }

        # ensure that each VM section has a subnet map
        if (!$FoggObject.SubnetAddressMap.Contains($vm.tag))
        {
            throw "No subnet address mapped for the $($vm.tag) VM section"
        }

        # ensure VM count is not null or negative/0
        if ($vm.count -eq $null -or $vm.count -le 0)
        {
            throw "VM count cannot be null, 0 or negative: $($vm.count)"
        }

        # ensure the off count is not negative or greater than VM count
        if ($vm.off -ne $null -and ($vm.off -le 0 -or $vm.off -gt $vm.count))
        {
            throw "VMs to turn off cannot be negative or greater than VM count: $($vm.off)"
        }

        # if there's more than one VM (load balanced) a port is required
        if ($vm.count -gt 1 -and (Test-Empty $vm.port))
        {
            throw "A valid port value is required for the $($vm.tag) VM section for load balancing"
        }

        # ensure that each VM has an OS setting if global OS does not exist
        if (!$hasOS -and $vm.os -eq $null)
        {
            throw "VM section $($vm.tag) is missing OS settings section"
        }
    }

    Write-Success "VM sections verified"
    return $vmCount
}


function Test-VMOS
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Tag,

        $OS
    )

    if ($OS -eq $null)
    {
        return
    }

    if (Test-Empty $OS.size)
    {
        throw "$($Tag) OS settings must declare a size type"
    }

    if (Test-Empty $OS.publisher)
    {
        throw "$($Tag) OS settings must declare a publisher type"
    }

    if (Test-Empty $OS.offer)
    {
        throw "$($Tag) OS settings must declare a offer type"
    }

    if (Test-Empty $OS.skus)
    {
        throw "$($Tag) OS settings must declare a sku type"
    }

    if (Test-Empty $OS.type)
    {
        throw "$($Tag) OS settings must declare an OS type (Windows/Linux)"
    }

    if ($OS.type -ine 'windows' -and $OS.type -ine 'linux')
    {
        throw "$($Tag) OS settings must declare a valid OS type (Windows/Linux)"
    }
}


function Test-DSCPaths
{
    param (
        [Parameter(Mandatory=$true)]
        $FoggObject,

        [Parameter(Mandatory=$true)]
        $Paths
    )

    if (Test-Empty $Paths)
    {
        $FoggObject.HasDscScripts = $false
        return
    }

    Write-Information "Verifying DSC Scripts"

    $FoggObject.HasDscScripts = $true
    $FoggObject.DscMap = ConvertFrom-JsonObjectToMap $Paths

    ($FoggObject.DscMap.Clone()).Keys | ForEach-Object {
        $path = Resolve-Path (Join-Path $FoggObject.ConfigParent $FoggObject.DscMap[$_])
        $FoggObject.DscMap[$_] = $path

        if (!(Test-PathExists $path))
        {
            throw "DSC script path does not exist: $($path)"
        }
    }

    Write-Success "DSC verified"
}


function Get-JSONContent
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Path
    )

    $json = Get-Content -Path $Path -Raw | ConvertFrom-Json
    if (!$?)
    {
        throw "Failed to parse the JSON content from file: $($Path)"
    }

    return $json
}


function Get-PowerShellVersion
{
    try
    {
        return [decimal]((Get-Host).Version.Major)
    }
    catch
    {
        return [decimal]([string](Get-Host | Select-Object Version).Version)
    }
}


function Test-PowerShellVersion
{
    param (
        [Parameter(Mandatory=$true)]
        [decimal]
        $ExpectedVersion
    )

    return ((Get-PowerShellVersion) -ge $ExpectedVersion)
}


function Remove-RGTag
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Value
    )

    return ($Value -ireplace '-rg', '')
}


function ConvertFrom-JsonObjectToMap
{
    param (
        $JsonObject
    )

    $map = @{}

    if ($JsonObject -eq $null)
    {
        return $map
    }

    $JsonObject.psobject.properties.name | ForEach-Object {
        $map.Add($_, $JsonObject.$_)
    }

    return $map
}


function Get-ReplaceSubnet
{
    param (
        [Parameter(Mandatory=$true)]
        [string]
        $Value,

        [Parameter(Mandatory=$true)]
        $Subnets,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $CurrentTag
    )

    $regex = '^@\{(?<key>.*?)(\|(?<value>.*?)){0,1}\}$'
    if ($Value -imatch $regex)
    {
        $v = $Matches['value']
        if ([string]::IsNullOrWhiteSpace($v))
        {
            $v = $CurrentTag
        }

        if ($Matches['key'] -ine 'subnet' -or !$Subnets.Contains($v))
        {
            return $Value
        }

        return ($Value -ireplace [Regex]::Escape($Matches[0]), $Subnets[$v])
    }

    return $Value
}


function Get-SubnetPort
{
    param (
        [Parameter(Mandatory=$true)]
        [string[]]
        $Values
    )

    if (($Values | Measure-Object).Count -ge 2)
    {
        return $Values[1]
    }

    return '*'
}


function New-FoggObject
{
    param (
        [string]
        $ResourceGroupName,

        [string]
        $Location,

        [string]
        $SubscriptionName,

        $SubnetAddressMap,

        [string]
        $ConfigPath,

        [string]
        $FoggfilePath,

        [pscredential]
        $SubscriptionCredentials,

        [pscredential]
        $VMCredentials,

        [string]
        $VNetAddress,

        [string]
        $VNetResourceGroupName,

        [string]
        $VNetName
    )

    $useFoggfile = $false

    # are we needing to use a Foggfile? (either path passed, or all params empty)
    if (!(Test-Empty $FoggfilePath))
    {
        $FoggfilePath = (Resolve-Path $FoggfilePath)

        if (!(Test-Path $FoggfilePath))
        {
            throw "Path to Foggfile does not exist: $($FoggfilePath)"
        }

        $useFoggfile = $true
    }

    # if $FoggfilePath not explicitly passed, are all params empty, and does Foggfile exist at root?
    $foggParams = @(
        $ResourceGroupName,
        $Location,
        $SubscriptionName,
        $VNetAddress,
        $VNetResourceGroupName,
        $VNetName,
        $SubnetAddressMap,
        $ConfigPath
    )

    if (!$useFoggfile -and (Test-ArrayEmpty $foggParams))
    {
        if (!(Test-Path 'Foggfile'))
        {
            throw 'No Foggfile found in current directory'
        }

        $FoggfilePath = (Resolve-Path '.\Foggfile')
        $useFoggfile = $true
    }

    # if we're using a Foggfile, set params appropriately
    if ($useFoggfile)
    {
        Write-Information "Loading configuration from Foggfile"

        # load Foggfile
        $file = Get-JSONContent $FoggfilePath

        # Only set the params that haven't already got a value (cli overrides foggfile)
        if (Test-Empty $ResourceGroupName)
        {
            $ResourceGroupName = $file.ResourceGroupName
        }

        if (Test-Empty $Location)
        {
            $Location = $file.Location
        }

        if (Test-Empty $SubscriptionName)
        {
            $SubscriptionName = $file.SubscriptionName
        }

        if (Test-Empty $VNetAddress)
        {
            $VNetAddress = $file.VNetAddress
        }

        if (Test-Empty $VNetResourceGroupName)
        {
            $VNetResourceGroupName = $file.VNetResourceGroupName
        }

        if (Test-Empty $VNetName)
        {
            $VNetName = $file.VNetName
        }

        if (Test-Empty $ConfigPath)
        {
            # this should be relative to the Foggfile
            $ConfigPath = Resolve-Path (Join-Path (Split-Path -Parent -Path $FoggfilePath) $file.ConfigPath)
        }

        if (Test-Empty $SubnetAddressMap)
        {
            $SubnetAddressMap = ConvertFrom-JsonObjectToMap $file.SubnetAddresses
        }
    }

    # create fogg object with params
    $props = @{}
    $props.ResourceGroupName = $ResourceGroupName
    $props.ShortRGName = (Remove-RGTag $ResourceGroupName)
    $props.Location = $Location
    $props.SubscriptionName = $SubscriptionName
    $props.SubscriptionCredentials = $SubscriptionCredentials
    $props.VMCredentials = $VMCredentials
    $props.VNetAddress = $VNetAddress
    $props.VNetResourceGroupName = $VNetResourceGroupName
    $props.VNetName = $VNetName
    $props.UseExistingVNet = (!(Test-Empty $VNetResourceGroupName) -and !(Test-Empty $VNetName))
    $props.SubnetAddressMap = $SubnetAddressMap
    $props.ConfigPath = $ConfigPath
    $props.ConfigParent = (Split-Path -Parent -Path $ConfigPath)
    $props.HasDscScripts = $false
    $props.DscMap = @{}
    $props.NsgMap = @{}

    $foggObj = New-Object -TypeName PSObject -Property $props

    # test the fogg parameters
    Test-FoggObjectParameters $foggObj

    # post param alterations
    $foggObj.ResourceGroupName = $foggObj.ResourceGroupName.ToLowerInvariant()
    $foggObj.ShortRGName = $foggObj.ShortRGName.ToLowerInvariant()

    # return object
    return $foggObj
}

function Test-FoggObjectParameters
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        $FoggObject
    )

    # if no resource group name passed, fail
    if (Test-Empty $FoggObject.ResourceGroupName)
    {
        throw 'No resource group name supplied'
    }

    # if no location passed, fail
    if (Test-Empty $FoggObject.Location)
    {
        throw 'No location to deploy VMs supplied'
    }

    # if no vnet address or vnet resource group/name for existing vnet, fail
    if (!$FoggObject.UseExistingVNet -and (Test-Empty $FoggObject.VNetAddress))
    {
        throw 'No address prefix supplied to create virtual network'
    }

    # if no subnets passed, fail
    if (Test-Empty $FoggObject.SubnetAddressMap)
    {
        throw 'No address prefixes for virtual subnets supplied'
    }

    # if the config path doesn't exist, fail
    if (!(Test-Path $FoggObject.ConfigPath))
    {
        throw "Configuration path supplied does not exist: $($FoggObject.ConfigPath)"
    }

    # if no subscription name supplied, request one
    if (Test-Empty $FoggObject.SubscriptionName)
    {
        $FoggObject.SubscriptionName = Read-Host -Prompt 'SubscriptionName'
    }
}