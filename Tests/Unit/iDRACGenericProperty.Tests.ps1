#region HEADER

# Unit Test Template Version: 1.2.1
$script:moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ( (-not (Test-Path -Path (Join-Path -Path $script:moduleRoot -ChildPath 'DSCResource.Tests'))) -or `
     (-not (Test-Path -Path (Join-Path -Path $script:moduleRoot -ChildPath 'DSCResource.Tests\TestHelper.psm1'))) )
{
    & git @('clone','https://github.com/PowerShell/DscResource.Tests.git',(Join-Path -Path $script:moduleRoot -ChildPath 'DSCResource.Tests'))
}

Import-Module -Name (Join-Path -Path $script:moduleRoot -ChildPath (Join-Path -Path 'DSCResource.Tests' -ChildPath 'TestHelper.psm1')) -Force

$TestEnvironment = Initialize-TestEnvironment `
    -DSCModuleName 'iDRAC' `
    -DSCResourceName 'iDRACGenericProperty' `
    -TestType Unit

#endregion HEADER

function Invoke-TestSetup {
}

function Invoke-TestCleanup {
    Restore-TestEnvironment -TestEnvironment $TestEnvironment
}

# Begin Testing
try
{
    Invoke-TestSetup

    InModuleScope 'iDRACGenericProperty' {
       
        $propertyName  = 'idrac.iPv4.DNS1'
        $propertyValue = '1.1.1.1'
        $ensure        = 'Present'

        $testParams = @{
            PropertyName = $propertyName
        }

        $getFakeProperty = {
            return @('[Key=idrac.Embedded.1#IPv4.1]','DNS1=172.21.12.56','')
        }

        $getFakePropertyDNS1 = {
            return @('[Key=idrac.Embedded.1#IPv4.1]','DNS1=1.1.1.1','')
        }

        $getFakePropertyNonExistingRacname = {
            return @('[Key=idrac.ActiveDirectory]','racname=','')
        }

        $getFakePropertyExistingRacname = {
            return @('[Key=idrac.ActiveDirectory]','racname=sampleracname','')
        }

        Describe 'iDRAC\Get-TargetResource' {

            Mock racadm.exe -MockWith $getFakeProperty

            It 'Returns a "System.Collections.Hashtable" object type' {

                $result = Get-TargetResource @testParams
                $result | Should BeOfType [System.Collections.Hashtable]
            }

            It 'Returns all correct values'{
                
                $result = Get-TargetResource @testParams
                $result.Ensure        | Should Be $ensure
                $result.PropertyName  | Should Be $propertyName

            }
        }
        
        Describe 'iDRAC\Test-TargetResource' {

            Mock racadm.exe -MockWith $getFakePropertyDNS1

            It 'Returns a "System.Boolean" object type' {
            
                $result = Test-TargetResource @testParams -PropertyValue $propertyValue -Ensure Present
                $result | Should BeOfType [System.Boolean]
            }
            
            It 'Returns $true when the option exists and Ensure = Present' {
                
                $result = Test-TargetResource @testParams -Ensure 'Present' -PropertyValue $propertyValue
                $result | Should Be $true
            }

            It 'Returns $false when the option does not exist and Ensure = Present' {
            
                Mock racadm.exe -MockWith  $getFakePropertyNonExistingRacname

                $result = Test-TargetResource -PropertyName 'idrac.ActiveDirectory.racname' -PropertyValue 'sampleRacName' -Ensure 'Present' 
                $result | Should Be $false
            }

            It 'Returns $false when the option exists and Ensure = Absent ' {

                Mock racadm.exe -MockWith $getFakePropertyExistingRacname

                $result = Test-TargetResource -PropertyName 'idrac.ActiveDirectory.racname' -PropertyValue 'sampleRacName' -Ensure 'Absent'
                $result | Should Be $false
            }
        }

        Describe 'iDRAC\Set-TargetResource' {
        
            It 'Should call "racadm.exe set" when "Ensure" = "Present" and property does not exist' {

                Mock racadm.exe -MockWith  $getFakePropertyNonExistingRacname
                
                Set-TargetResource -PropertyName 'idrac.ActiveDirectory.racname' -PropertyValue 'sampleRacName' -Ensure 'Present'
                Assert-MockCalled -CommandName racadm.exe -Scope It
            }
        }
    }
}
finally
{
    Invoke-TestCleanup
}
