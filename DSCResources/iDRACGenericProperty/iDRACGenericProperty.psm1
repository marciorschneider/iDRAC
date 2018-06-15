$currentPath = Split-Path -Path $MyInvocation.MyCommand.Path -Parent

#$modulePathhelper            = (Join-Path -Path (Split-Path -Path $currentPath -Parent) -ChildPath 'Helper.psm1')

#Import-Module -Name $modulePathhelper

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
 
    
    try
    {
        # Running the racadm.exe to get the property. If the result code is 0 then we manipulate the output to extract the property value.
        $output = racadm.exe ("get " + $PropertyName)
    }
    catch
    {
        $ErrorMsg = $_.Exception.Message
        Write-Verbose $ErrorMsg
    }
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

    else
    {
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
        When set to 'Present' the option will be created.
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
        [ValidateSet('Present')]
        [String]
        $Ensure
    )

    $currentValue = Get-TargetResource -PropertyName $PropertyName -Ensure $Ensure
    
    # Testing for Ensure = Present
    if ($Ensure -eq 'Present')
    {
        if (($currentValue.Ensure -eq 'Present') -and ($currentValue.PropertyValue -eq $PropertyValue))
        {
            $return = $true
        }
        else
        {
            $return = $false
        }
    }
    # Testing for Ensure = Absent
    else
    {
        if ($currentValue.Ensure -eq 'Absent' -and $currentValue.PropertyValue -eq $null)
        {
            $return = $true
        }
        else
        {
            $return = $true
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
        When set to 'Present' the option will be created.
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
        [ValidateSet('Present')]
        [String]
        $Ensure
    )

    $currentValue = Get-TargetResource -PropertyName $PropertyName

    try
    {
        # Running the racadm.exe to set the property.
        $output = racadm.exe "set $PropertyName $PropertyValue"
    }
    catch
    {
        $ErrorMsg = $_.Exception.Message
        Write-Verbose $ErrorMsg
    }
}

Export-ModuleMember -Function *-TargetResource
