# Load Localization Data
Import-Module -Name (Join-Path -Path (Join-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) `
                         -ChildPath 'Modules' ) -ChildPath 'CommonResourceHelper.psm1')

$script:localizedData = Get-LocalizedData -ResourceName 'iDRACGenericProperty' -ScriptRoot $PSScriptRoot

<#
    .SYNOPSIS
        This function gets an iDRAC generic property value.

    .PARAMETER PropertyName
        The property name.
#>
function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]  
        [String]
        $PropertyName
    )
    
    # Running the racadm.exe to get the property. If the result code is 0 then we manipulate the output to extract the property value.
    $GettingPropertyMessage = $localizedData.GettingPropertyMessage -f $PropertyName
    Write-Verbose $GettingPropertyMessage
    $output = racadm.exe ("get " + $PropertyName)

    if ($LASTEXITCODE -eq 0)
    {
        # We want the second element in the output
        $tempString = $output[1]
        $tempString = $tempString.toLower()
        
        # We need to extract the property name from the full iDRAC property
        $PropertyName = $PropertyName.ToLower()
        $simplePropertyName = $PropertyName.Substring($PropertyName.LastIndexOf('.') + 1)

        # Extracting the property value
        $propertyValue = $tempString.Substring($tempString.IndexOf($simplePropertyName) + $simplePropertyName.Length + 1)

        $hashTable = @{
            PropertyName  = $PropertyName
            PropertyValue = $propertyValue
            Ensure        = 'Present'
        }
    }

    # If the exit code from racadm is not equal zero we assume that was an error
    else
    {
        Write-Error $LASTEXITCODE
        
        $hashTable = @{
            PropertyName  = $null
            PropertyValue = $null
            Ensure        = 'Absent'
        }
    }

$hashTable
}

<#
    .SYNOPSIS
        This function tests an iDRAC generic property value.

    .PARAMETER PropertyName
        The property name.

    .PARAMETER PropertyValue
        The property value.

    .PARAMETER Ensure
        When set to 'Present' the option will be created. If set to 'Absent' value will be compared and if equal will return $false.
#>
function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]  
        [String]
        $PropertyName,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]  
        [String]
        $PropertyValue,        
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('Present','Absent')]
        [String]
        $Ensure
    )

    $currentValue = Get-TargetResource -PropertyName $PropertyName
    
    $TestingPropertyMessage = $localizedData.TestingPropertyMessage -f $PropertyName, $PropertyValue
    Write-Verbose $TestingPropertyMessage

    # Testing for Ensure = Present
    if ($Ensure -eq 'Present')
    {
        if ($currentValue.PropertyValue -eq $PropertyValue)
        {
            $MatchPropertyMessage = $localizedData.MatchPropertyMessage -f $PropertyName, $PropertyValue
            Write-Verbose $MatchPropertyMessage
            $return = $true
        }
        else
        {
            $NotMatchPropertyMessage = $localizedData.NotMatchPropertyMessage -f $PropertyName, $PropertyValue
            Write-Verbose $NotMatchPropertyMessage
            $return = $false
        }
    }
    # Testing for Ensure = Absent
    else
    {
        if ($currentValue.PropertyValue -ne $PropertyValue)
        {
            $return = $true
        }
        else
        {
            $return = $false
        }
    }

    $return
}


<#
    .SYNOPSIS
        This function sets an iDRAC generic property value.

    .PARAMETER PropertyName
        The property name.

    .PARAMETER PropertyValue
        The property value.

    .PARAMETER Ensure
        When set to 'Present' the option will be created. If set to 'Absent will do nothing.'
#>
function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]  
        [String]
        $PropertyName,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]  
        [String]
        $PropertyValue,        
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('Present','Absent')]
        [String]
        $Ensure
    )

    $currentValue = Get-TargetResource -PropertyName $PropertyName

    
    $SettingPropertyMessage = $localizedData.SettingPropertyMessage -f $PropertyName, $PropertyValue
    Write-Verbose $SettingPropertyMessage
    
    # Running the racadm.exe to set the property.
    $output = racadm.exe "set $PropertyName $PropertyValue"

    # If the exit code is not zero return it on the error output
    if($LASTEXITCODE -ne 0)
    {
        Write-Error $LASTEXITCODE
    }
    else
    {
        Write-Verbose "Sucess"
    }
}

Export-ModuleMember -Function *-TargetResource
