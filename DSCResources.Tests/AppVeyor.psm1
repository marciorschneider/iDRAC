Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelper.psm1') -Force

<#
    .SYNOPSIS
        This module provides functions for building and testing DSC Resources in AppVeyor.

        These functions will only work if called within an AppVeyor CI build task.
#>

$customTasksModulePath = Join-Path -Path $env:APPVEYOR_BUILD_FOLDER `
                                   -ChildPath '.AppVeyor\CustomAppVeyorTasks.psm1'
if (Test-Path -Path $customTasksModulePath)
{
    Import-Module -Name $customTasksModulePath
    $customTaskModuleLoaded = $true
}
else
{
    $customTaskModuleLoaded = $false
}

# Load the test helper module.
$testHelperPath = Join-Path -Path $PSScriptRoot -ChildPath 'TestHelper.psm1'
Import-Module -Name $testHelperPath -Force

<#
    .SYNOPSIS
        Prepares the AppVeyor build environment to perform tests and packaging on a
        DSC Resource module.

        Performs the following tasks:
        1. Installs Nuget Package Provider DLL.
        2. Installs Nuget.exe to the AppVeyor Build Folder.
        3. Installs the Pester PowerShell Module.
        4. Executes Invoke-CustomAppveyorInstallTask if defined in .AppVeyor\CustomAppVeyorTasks.psm1
           in resource module repository.

    .EXAMPLE
        Invoke-AppveyorInstallTask -PesterMaximumVersion 3.4.3
#>
function Invoke-AppveyorInstallTask
{
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    param
    (
        [Version]
        $PesterMaximumVersion
    )

    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force

    # Install Nuget.exe to enable package creation
    $nugetExePath = Join-Path -Path $env:TEMP `
                              -ChildPath 'nuget.exe'
    Install-NugetExe -OutFile $nugetExePath

    $installPesterParameters = @{
        Name = 'Pester'
        Force = $true
    }

    $installModuleSupportsSkipPublisherCheck = (Get-Command Install-Module).Parameters['SkipPublisherCheck']
    if ($installModuleSupportsSkipPublisherCheck)
    {
        $installPesterParameters['SkipPublisherCheck'] = $true
    }

    if ($PesterMaximumVersion)
    {
        $installPesterParameters['MaximumVersion'] = $PesterMaximumVersion
    }

    Install-Module @installPesterParameters

    # Execute the custom install task if defined
    if ($customTaskModuleLoaded `
        -and (Get-Command -Module $CustomAppVeyorTasks `
                          -Name Invoke-CustomAppveyorInstallTask `
                          -ErrorAction SilentlyContinue))
    {
        Invoke-CustomAppveyorInstallTask
    }

    Write-Info -Message 'Install Task Complete.'
}

<#
    .SYNOPSIS
        Executes the tests on a DSC Resource in the AppVeyor build environment.

        Executes Start-CustomAppveyorTestTask if defined in .AppVeyor\CustomAppVeyorTasks.psm1
        in resource module repository.

    .PARAMETER Type
        This controls the method of running the tests.
        To use execute tests using a test harness function specify 'Harness', otherwise
        leave empty to use default value 'Default'.

    .PARAMETER MainModulePath
        This is the relative path of the folder that contains the module manifest.
        If not specified it will default to the root folder of the repository.

    .PARAMETER CodeCoverage
        This will switch on Code Coverage evaluation in Pester.

    .PARAMETER ExcludeTag
        This is the list of tags that will be used to prevent tests from being run if
        the tag is set in the describe block of the test.
        This wll default to 'Examples' and 'Markdown'.

    .PARAMETER HarnessModulePath
        This is the full path and filename of the test harness module.
        If not specified it will default to 'Tests\TestHarness.psm1'.

    .PARAMETER HarnessFunctionName
        This is the function name in the harness module to call to execute tests.
        If not specified it will default to 'Invoke-TestHarness'.

    .PARAMETER CodeCovIo
        This will switch on reporting of code coverage to codecov.io.
        Require -CodeCoverage when running with -type default.

    .PARAMETER DisableConsistency
        This will switch off monitoring (consistency) for the Local Configuration
        Manager (LCM), setting ConfigurationMode to 'ApplyOnly', on the node
        running tests.

    .PARAMETER RunTestInOrder
        This will cause the integration tests to be run in order. First, the
        common tests will run, followed by the unit tests. Finally the integration
        tests will be run in the order defined.
        Each integration test configuration file ('*.config.ps1') must be decorated
        with an attribute `Microsoft.DscResourceKit.IntegrationTest` containing
        a named attribute argument 'OrderNumber' and be assigned a numeric value
        (`1`, `2`, `3`,..). If the integration test is not decorated with the
        attribute, then that test will run among the last tests, after all the
        integration test with a specific order has run.

    .PARAMETER RunInContainer
        This enables running unit tests in a Docker Windows container. The parameter
        can only be used when the parameter RunTestInOrder is also used.
#>
function Invoke-AppveyorTestScriptTask
{
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    param
    (
        [ValidateSet('Default','Harness')]
        [String]
        $Type = 'Default',

        [ValidateNotNullOrEmpty()]
        [String]
        $MainModulePath = $env:APPVEYOR_BUILD_FOLDER,

        [Parameter(ParameterSetName = 'DefaultCodeCoverage')]
        [Switch]
        $CodeCoverage,

        [Parameter(ParameterSetName = 'Harness')]
        [Parameter(ParameterSetName = 'DefaultCodeCoverage')]
        [Switch]
        $CodeCovIo,

        [Parameter(ParameterSetName = 'DefaultCodeCoverage')]
        [Parameter(ParameterSetName = 'Default')]
        [String[]]
        $ExcludeTag = @('Examples','Markdown'),

        [Parameter(ParameterSetName = 'Harness',
            Mandatory = $true)]
        [String]
        $HarnessModulePath = 'Tests\TestHarness.psm1',

        [Parameter(ParameterSetName = 'Harness',
            Mandatory = $true)]
        [String]
        $HarnessFunctionName = 'Invoke-TestHarness',

        [Parameter()]
        [Switch]
        $DisableConsistency,

        [Parameter()]
        [Switch]
        $RunTestInOrder,

        [Parameter()]
        [Switch]
        $RunInContainer
    )

    # Convert the Main Module path into an absolute path if it is relative
    if (-not ([System.IO.Path]::IsPathRooted($MainModulePath)))
    {
        $MainModulePath = Join-Path -Path $env:APPVEYOR_BUILD_FOLDER `
                                    -ChildPath $MainModulePath
    }

    $testResultsFile = Join-Path -Path $env:APPVEYOR_BUILD_FOLDER `
                                 -ChildPath 'TestsResults.xml'

    # Execute custom test task if defined
    if ($customTaskModuleLoaded `
        -and (Get-Command -Module $CustomAppVeyorTasks `
                          -Name Start-CustomAppveyorTestTask `
                          -ErrorAction SilentlyContinue))
    {
        Start-CustomAppveyorTestTask
    }

    if ($DisableConsistency.IsPresent)
    {
        $disableConsistencyMofPath = Join-Path -Path $env:temp -ChildPath 'DisableConsistency'
        if (-not (Test-Path -Path $disableConsistencyMofPath))
        {
            $null = New-Item -Path $disableConsistencyMofPath -ItemType Directory -Force
        }

        # have LCM Apply only once.
        Configuration Meta
        {
            LocalConfigurationManager
            {
                ConfigurationMode = 'ApplyOnly'
            }
        }
        meta -outputPath $disableConsistencyMofPath

        Set-DscLocalConfigurationManager -Path $disableConsistencyMofPath -Force -Verbose
        $null = Remove-Item -LiteralPath $disableConsistencyMofPath -Recurse -Force -Confirm:$false
    }

    $moduleName = Split-Path -Path $env:APPVEYOR_BUILD_FOLDER -Leaf
    $testsPath = Join-Path -Path $env:APPVEYOR_BUILD_FOLDER -ChildPath 'Tests'

    $configurationFiles = Get-ChildItem -Path $testsPath -Include '*.config.ps1' -Recurse
    foreach ($configurationFile in $configurationFiles)
    {
        # Get the list of additional modules required by the example
        $requiredModules = Get-ResourceModulesInConfiguration -ConfigurationPath $configurationFile.FullName |
            Where-Object -Property Name -ne $moduleName

        if ($requiredModules)
        {
            Install-DependentModule -Module $requiredModules
        }
    }

    switch ($Type)
    {
        'Default'
        {
            # Execute the standard tests using Pester.
            $pesterParameters = @{
                OutputFormat = 'NUnitXML'
                OutputFile   = $testResultsFile
                PassThru     = $True
            }

            if ($ExcludeTag.Count -gt 0)
            {
                $pesterParameters += @{
                    ExcludeTag = $ExcludeTag
                }
            }

            <#
                Only add CodeCoverage parameter at this point if we are not running
                unit tests in a container. If unit tests are running in a container
                then the container logic will handle this.
            #>
            if ($CodeCoverage -and -not $RunInContainer.IsPresent)
            {
                Write-Warning -Message 'Code coverage statistics are being calculated. This will slow the start of the tests while the code matrix is built. Please be patient.'

                # Only add code path for DSCResources if they exist.
                $codeCoveragePaths = @(
                    "$env:APPVEYOR_BUILD_FOLDER\*.psm1"
                )

                if (Test-IsRepositoryDscResourceTests)
                {
                    <#
                        The repository being tested is DscResource.Tests.
                        DscResource.Tests need a different set of paths for
                        code coverage.
                    #>
                    $codeCoveragePaths += "$env:APPVEYOR_BUILD_FOLDER\**\*.psm1"
                }
                else
                {
                    <#
                        Define the folders to check, if found add the path for
                        code coverage.
                    #>
                    $possibleModulePaths = @(
                        'DSCResources',
                        'DSCClassResources'
                    )

                    foreach ($possibleModulePath in $possibleModulePaths)
                    {
                        if (Test-Path -Path "$env:APPVEYOR_BUILD_FOLDER\$possibleModulePath")
                        {
                            $codeCoveragePaths += "$env:APPVEYOR_BUILD_FOLDER\$possibleModulePath\*.psm1"
                            $codeCoveragePaths += "$env:APPVEYOR_BUILD_FOLDER\$possibleModulePath\**\*.psm1"
                        }
                    }
                }

                $pesterParameters += @{
                    CodeCoverage = $codeCoveragePaths
                }
            }

            $getChildItemParameters = @{
                Path = $env:APPVEYOR_BUILD_FOLDER
                Recurse = $true
            }

            # Get all tests '*.Tests.ps1'.
            $getChildItemParameters['Filter'] = '*.Tests.ps1'
            $testFiles = Get-ChildItem @getChildItemParameters

            <#
                If it is another repository other than DscResource.Tests
                then remove the DscResource.Tests unit tests from the list
                of tests to run. Issue #189.
            #>
            if (-not (Test-IsRepositoryDscResourceTests))
            {
                $testFiles = $testFiles | Where-Object -FilterScript {
                    $_.FullName -notmatch 'DSCResource.Tests\\Tests'
                }
            }

            if ($RunTestInOrder)
            {
                <#
                    This is an array of test files containing path
                    and optional order number.
                #>
                $testObjects = @()

                # Add all tests to the array with order number set to $null.
                foreach ($testFile in $testFiles)
                {
                    $testObjects += @(
                        [PSCustomObject] @{
                            TestPath = $testFile.FullName
                            OrderNumber = $null
                        }
                    )
                }

                <#
                    Make sure all common tests are always run first
                    by setting order number to zero (0).
                #>
                $testObjects | Where-Object -FilterScript {
                    $_.TestPath -match 'DSCResource.Tests'
                } | ForEach-Object -Process {
                    $_.OrderNumber = 0
                }

                # Get each integration test config files ('*.config.ps1').
                $getChildItemParameters['Filter'] = '*.config.ps1'
                $integrationTestConfigurationFiles = Get-ChildItem @getChildItemParameters

                <#
                    In each file, search for existens of attribute 'IntegrationTest' with a
                    named attribute argument 'OrderNumber'.
                #>
                foreach ($integrationTestConfigurationFile in $integrationTestConfigurationFiles)
                {
                    $orderNumber = Get-DscIntegrationTestOrderNumber `
                        -Path $integrationTestConfigurationFile.FullName

                    if ($orderNumber)
                    {
                        <#
                            Build the correct integration test file name, by
                            replacing '.config.ps1' with '.Integration.Tests.ps1'.
                        #>
                        $testFileName = $integrationTestConfigurationFile.FullName `
                            -replace '.config.ps1', '.Integration.Tests.ps1'

                        <#
                            If the test must run in order, find the correct
                            test and add the order number to object in the array..
                        #>
                        ($testObjects | Where-Object -FilterScript {
                            $_.TestPath -eq $testFileName
                        }).OrderNumber = $orderNumber
                    }
                }

                <#
                    This is an array of the test files in the correct
                    order they will be run.

                    - First the common tests will always run.
                    - Secondly the tests that use mocks will run (unit tests),
                      unless they should be run in a container.
                    - Finally, those the tests that actually changes things
                      (integration tests) will run in order.
                #>
                $testObjectOrder = @()

                # Add tests that have OrderNumber -eq 0
                $testObjectOrder += $testObjects | Where-Object -FilterScript {
                    $_.OrderNumber -eq 0
                }

                <#
                    If we should run unit test in a Docker Windows container, then
                    that should be kicked off first.
                #>
                if ($RunInContainer.IsPresent)
                {
                    # Import the module containing the container helper functions.
                    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'DscResource.Container')

                    Write-Info -Message 'Using a Docker Windows container to run unit tests.'

                    # Filter out tests that uses mocks (unit tests).
                    $testObjectOrderContainer += $testObjects | Where-Object -FilterScript {
                        $null -eq $_.OrderNumber `
                        -and $_.TestPath -notmatch 'Integration.Tests'
                    }

                    $containerName = 'unittest'
                    $newContainerParameters = @{
                        Name = $containerName
                        TestPath = $testObjectOrderContainer.TestPath
                        ProjectPath = $env:APPVEYOR_BUILD_FOLDER
                    }

                    <#
                        If code coverage was chosen, then evaluate the files
                        needed to be able to calculate coverage for the files
                        tested in the container. The rest of the files are left
                        for the tests running in the build worker.
                    #>
                    if ($CodeCoverage)
                    {
                        # Read all the test files to get an object for each.
                        $testFile = Get-ChildItem -Path $testObjectOrderContainer.TestPath -File

                        $moduleFilePath = @(
                            '{0}\*.psm1' -f $env:APPVEYOR_BUILD_FOLDER
                            '{0}\DSCResources\*.psm1' -f $env:APPVEYOR_BUILD_FOLDER
                            '{0}\DSCResources\**\*.psm1' -f $env:APPVEYOR_BUILD_FOLDER
                        )

                        <#
                            Read all module files. This array list will end up
                            with only the module files that should be used for
                            code coverage in the build worker.
                        #>
                        [System.Collections.ArrayList] $moduleFile = `
                            Get-ChildItem -Path $moduleFilePath -File -Filter '*.psm1'

                        <#
                            This will contain all the modules files that will be
                            used for code coverage in the container.
                        #>
                        $codeCoverageFile = @()

                        foreach ($currentTestFile in $testFile)
                        {
                            $scriptBaseName = $currentTestFile.BaseName -replace '\.Tests'

                            $coverageFile = $moduleFile | Where-Object -FilterScript {
                                $_.FullName -match "$scriptBaseName\.psm1"
                            }

                            if ($coverageFile)
                            {
                                $codeCoverageFile += $coverageFile.FullName

                                $moduleFile.Remove($coverageFile)
                            }
                        }

                        <#
                            Here the code coverage is assigned. The container
                            get the module files it needs for calculating
                            code coverage ($codeCoverageFile), and the build
                            worker gets the remaining module files to calculate
                            code coverage on ($moduleFile.FullName).
                        #>
                        $newContainerParameters['CodeCoverage'] = $codeCoverageFile
                        $pesterParameters['CodeCoverage'] = $moduleFile.FullName
                    }

                    $containerIdentifier = New-Container @newContainerParameters

                    <#
                        This will always start the container. If for some reason
                        the container fails, the problem will be handled after
                        waiting for the container to finish (or fail). At that
                        point if the container exits with a code other than 0,
                        then the docker logs will be gathered and sent as an
                        artifact. If PowerShell.exe returned an error record then
                        that will be thrown.

                        We could have waited here for X seconds to check
                        whether the container seems to have started the task
                        (and not exited with an error code). But to save seconds
                        we assume that the container will always be able to start
                        the task successfully.
                    #>
                    Start-Container -ContainerIdentifier $containerIdentifier | Out-Null

                    Write-Info -Message 'Container is started. Build worker will continue run other tests.'

                    <#
                        If we run in a container then the result file that is
                        generated by the test running in the build worker should
                        use a different name than the default, to differentiate
                        it from the container test result files.
                    #>
                    $testResultsFile = Join-Path -Path $env:APPVEYOR_BUILD_FOLDER `
                                                 -ChildPath 'worker_TestsResults.xml'

                    $pesterParameters['OutputFile'] = $testResultsFile
                }
                else
                {
                    # Add tests that uses mocks (unit tests).
                    $testObjectOrder += $testObjects | Where-Object -FilterScript {
                        $null -eq $_.OrderNumber `
                        -and $_.TestPath -notmatch 'Integration.Tests'
                    }
                }

                # Add integration tests that must run in the correct order
                $testObjectOrder += $testObjects | Where-Object -FilterScript {
                    $null -ne $_.OrderNumber `
                    -and $_.OrderNumber -ne 0
                } | Sort-Object -Property 'OrderNumber'

                # Then add the rest of the integration tests.
                $testObjectOrder += $testObjects | Where-Object -FilterScript {
                    $null -eq $_.OrderNumber `
                    -and $_.TestPath -match 'Integration.Tests'
                }

                # Add all the paths to the Invoke-Pester Path parameter.
                $pesterParameters += @{
                    Path = $testObjectOrder.TestPath
                }

                <#
                    This runs the tests on the build worker.

                    If the option was to run tests in a container, then this
                    will only run the remaining tests. The name of the result
                    file that is generated by this test run was changed by the
                    container logic, to differentiate the test result from the
                    container test result.
                #>
                $results = Invoke-Pester @pesterParameters

                <#
                    If we ran unit test in a Docker Windows container, then
                    we need to wait for the container to finish running tests.
                #>
                if ($RunInContainer.IsPresent)
                {
                    $waitContainerParameters = @{
                        ContainerIdentifier = $containerIdentifier

                        <#
                            Wait 1 hour for the container to finish the tests.
                            If the container has not returned before that time,
                            the test will fail.
                        #>
                        Timeout = 3600
                    }

                    $containerExitCode = Wait-Container @waitContainerParameters

                    if ($containerExitCode -ne 0)
                    {
                        $containerErrorObject = Get-ContainerLog -ContainerIdentifier $containerIdentifier

                        # Upload the Docker Windows container log.
                        $containerDockerLogFileName = '{0}-DockerLog.txt' -f $containerName
                        $containerDockerLogPath = Join-Path -Path $env:APPVEYOR_BUILD_FOLDER -ChildPath $containerDockerLogFileName
                        $containerErrorObject | Out-File -FilePath $containerDockerLogPath -Encoding ascii
                        Push-TestArtifact -Path $containerDockerLogPath

                        Write-Warning -Message ('The container named ''{0}'' failed with exit code {1}. See artifact ''{2}'' for the logs. Throwing the error reported by Docker (in the log output):' -f $containerName, $containerExitCode, $containerDockerLogFileName)

                        <#
                            Loop thru the output and throw if PowerShell, that was
                            started in the container, returned an error record.
                            All other other output is ignored (sent to Out-Null).
                        #>
                        $containerErrorObject | ForEach-Object -Process {
                            if ($_ -is [System.Management.Automation.ErrorRecord])
                            {
                                throw $_
                            }
                        } | Out-Null

                        <#
                            No error record was found that could be thrown above.
                            Write a warning that we couldn't find an error.
                        #>
                        Write-Warning -Message 'Container exited with an error, but no error record was found in the container log, so the error could not be caught.'
                    }

                    Write-Info -Message ('Container named ''{0}'' has finish running tests.' -f $containerName)

                    <#
                        Get the <container>_Transcript.txt from the container
                        and upload it as an artifact.
                    #>
                    $containerTestsTranscriptFilePath = Join-Path `
                        -Path $env:APPVEYOR_BUILD_FOLDER `
                        -ChildPath ('{0}_Transcript.txt' -f $containerName)

                    $copyItemFromContainerParameters = @{
                        ContainerIdentifier = $containerIdentifier
                        Path = $containerTestsTranscriptFilePath
                        Destination = $env:APPVEYOR_BUILD_FOLDER
                    }

                    Copy-ItemFromContainer @copyItemFromContainerParameters
                    Push-TestArtifact -Path $containerTestsTranscriptFilePath

                    <#
                        Get the <container>TestsResults.xml from the container
                        and upload it as an artifact.
                    #>
                    $containerTestsResultsFilePath = Join-Path `
                        -Path $env:APPVEYOR_BUILD_FOLDER `
                        -ChildPath ('{0}_TestsResults.xml' -f $containerName)

                    $copyItemFromContainerParameters['Path'] = $containerTestsResultsFilePath
                    Copy-ItemFromContainer @copyItemFromContainerParameters
                    Push-TestArtifact -Path $containerTestsResultsFilePath

                    <#
                        Get the <container>TestsResults.json from the container
                        and upload it as an artifact.
                    #>
                    $containerTestsResultsJsonPath = Join-Path `
                        -Path $env:APPVEYOR_BUILD_FOLDER `
                        -ChildPath ('{0}_TestsResults.json' -f $containerName)

                    $copyItemFromContainerParameters['Path'] = $containerTestsResultsJsonPath
                    Copy-ItemFromContainer @copyItemFromContainerParameters
                    Push-TestArtifact -Path $containerTestsResultsJsonPath

                    Write-Info -Message ('Start listing test results from container named ''{0}''.' -f $containerName)

                    $containerPesterResult = Get-Content -Path $containerTestsResultsJsonPath | ConvertFrom-Json

                    # Output the final unit test results.
                    $outTestResultParameters = @{
                        TestResult = $containerPesterResult.TestResult
                        WaitForAppVeyorConsole = $true
                        Timeout = 5
                    }

                    Out-TestResult @outTestResultParameters

                    # Output the missed commands when code coverage is used.
                    if ($CodeCoverage.IsPresent)
                    {
                        $outMissedCommandParameters = @{
                            MissedCommand = $containerPesterResult.CodeCoverage.MissedCommands
                            WaitForAppVeyorConsole = $true
                            Timeout = 5
                        }

                        Out-MissedCommand @outMissedCommandParameters
                    }

                    Write-Info -Message ('End of test results from container named ''{0}''.' -f $containerName)
                }
            }
            else
            {
                $pesterParameters += @{
                    Path = $testFiles.FullName
                }

                $results = Invoke-Pester @pesterParameters
            }

            break
        }

        'Harness'
        {
            # Copy the DSCResource.Tests folder into the folder containing the resource PSD1 file.
            $dscTestsPath = Join-Path -Path $MainModulePath `
                                      -ChildPath 'DSCResource.Tests'
            Copy-Item -Path $PSScriptRoot -Destination $MainModulePath -Recurse
            $testHarnessPath = Join-Path -Path $env:APPVEYOR_BUILD_FOLDER `
                                         -ChildPath $HarnessModulePath

            # Execute the resource tests as well as the DSCResource.Tests\meta.tests.ps1
            Import-Module -Name $testHarnessPath
            $results = & $HarnessFunctionName -TestResultsFile $testResultsFile `
                                             -DscTestsPath $dscTestsPath

            # Delete the DSCResource.Tests folder because it is not needed
            Remove-Item -Path $dscTestsPath -Force -Recurse
            break
        }

        default
        {
            throw "An unhandled type '$Type' was specified."
        }
    }

    $pesterTestResult = $results.TestResult

    if ($RunInContainer.IsPresent)
    {
        $pesterTestResult += $containerPesterResult.TestResult
    }

    foreach ($result in $pesterTestResult)
    {
        [string] $describeName = $result.Describe -replace '\\', '/'
        [string] $contextName = $result.Context -replace '\\', '/'
        $componentName = '{0}; Context: {1}' -f $describeName, $contextName
        $appVeyorResult = $result.Result
        # Convert any result not know by AppVeyor to an AppVeyor Result
        switch ($result.Result)
        {
            'Pending'
            {
                $appVeyorResult = 'Skipped'
            }
        }

        $addAppVeyorTestParameters = @{
            Name = $result.Name
            Framework = 'NUnit'
            Filename = $componentName
            Outcome = $appVeyorResult
            Duration = $result.Time.TotalMilliseconds
        }

        if ($result.FailureMessage)
        {
            $addAppVeyorTestParameters += @{
                ErrorMessage = $result.FailureMessage
                ErrorStackTrace = $result.StackTrace
            }
        }

        Add-AppveyorTest @addAppVeyorTestParameters
    }

    Push-TestArtifact -Path $testResultsFile

    if ($CodeCovIo.IsPresent)
    {
        if ($CodeCoverage.IsPresent)
        {
            # Get the code coverage result from build worker test run.
            $entireCodeCoverage = $results.CodeCoverage

            # Check whether we run in a container, and the build worker reported coverage
            if ($RunInContainer.IsPresent -and $entireCodeCoverage)
            {
                # Concatenate the code coverage result from the container test run.
                $containerCodeCoverage = $containerPesterResult.CodeCoverage
                $entireCodeCoverage.NumberOfCommandsAnalyzed += $containerCodeCoverage.NumberOfCommandsAnalyzed
                $entireCodeCoverage.NumberOfFilesAnalyzed += $containerCodeCoverage.NumberOfFilesAnalyzed
                $entireCodeCoverage.NumberOfCommandsExecuted += $containerCodeCoverage.NumberOfCommandsExecuted
                $entireCodeCoverage.NumberOfCommandsMissed += $containerCodeCoverage.NumberOfCommandsMissed
                $entireCodeCoverage.MissedCommands += $containerCodeCoverage.MissedCommands
                $entireCodeCoverage.HitCommands += $containerCodeCoverage.HitCommands
                $entireCodeCoverage.AnalyzedFiles += $containerCodeCoverage.AnalyzedFiles
            }
            elseif ($RunInContainer.IsPresent)
            {
                # The container was the only one reporting code coverage.
                $entireCodeCoverage = $containerPesterResult.CodeCoverage
            }

            if ($entireCodeCoverage)
            {
                Write-Info -Message 'Uploading CodeCoverage to CodeCov.io...'
                Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'DscResource.CodeCoverage')
                $jsonPath = Export-CodeCovIoJson -CodeCoverage $entireCodeCoverage -repoRoot $env:APPVEYOR_BUILD_FOLDER
                Invoke-UploadCoveCoveIoReport -Path $jsonPath
            }
            else
            {
                Write-Warning -Message 'Could not create CodeCov.io report because Pester results object did not contain a CodeCoverage object'
            }
        }
        else
        {
            Write-Warning -Message 'Could not create CodeCov.io report because code coverage was not enabled when calling Invoke-AppveyorTestScriptTask.'
        }
    }

    Write-Verbose -Message "Test result Type: $($results.GetType().FullName)"

    Write-Info -Message 'Done running tests.'

    $pesterFailedCount = $results.FailedCount

    if ($RunInContainer -and $containerPesterResult.FailedCount)
    {
        Write-Warning -Message ('The tests that ran in the container named ''{0}'' report errors. Please look at the artifact ''{1}'' for more detailed errors.' -f $containerName, $testsTranscriptFileName)
        $pesterFailedCount += $containerPesterResult.FailedCount
    }

    if ($pesterFailedCount -gt 0)
    {
        throw ('{0} tests failed.' -f $pesterFailedCount)
    }

    Write-Info -Message 'Test Script Task Complete.'
}

<#
    .SYNOPSIS
        Performs the after tests tasks for the AppVeyor build process.

        This includes:
        1. Optional: Produce and upload Wiki documentation to AppVeyor.
        2. Set version number in Module Manifest to build version
        3. Zip up the module content and produce a checksum file and upload to AppVeyor.
        4. Pack the module into a Nuget Package.
        5. Upload the Nuget Package to AppVeyor.

        Executes Start-CustomAppveyorAfterTestTask if defined in .AppVeyor\CustomAppVeyorTasks.psm1
        in resource module repository.

    .PARAMETER Type
        This controls the additional processes that can be run after testing.
        To produce wiki documentation specify 'Wiki', otherwise leave empty to use
        default value 'Default'.

    .PARAMETER MainModulePath
        This is the relative path of the folder that contains the module manifest.
        If not specified it will default to the root folder of the repository.

    .PARAMETER ResourceModuleName
        Name of the Resource Module being produced.
        If not specified will default to GitHub repository name.

    .PARAMETER Author
        The Author string to insert into the NUSPEC file for the package.
        If not specified will default to 'Microsoft'.

    .PARAMETER Owners
        The Owners string to insert into the NUSPEC file for the package.
        If not specified will default to 'Microsoft'.
#>
function Invoke-AppveyorAfterTestTask
{

    [CmdletBinding(DefaultParameterSetName = 'Default')]
    param
    (
        [Parameter()]
        [ValidateSet('Default','Wiki')]
        [String]
        $Type = 'Default',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]
        $MainModulePath = $env:APPVEYOR_BUILD_FOLDER,

        [Parameter()]
        [String]
        $ResourceModuleName = (($env:APPVEYOR_REPO_NAME -split '/')[1]),

        [Parameter()]
        [String]
        $Author = 'Microsoft',

        [Parameter()]
        [String]
        $Owners = 'Microsoft'
    )

    # Convert the Main Module path into an absolute path if it is relative
    if (-not ([System.IO.Path]::IsPathRooted($MainModulePath)))
    {
        $MainModulePath = Join-Path -Path $env:APPVEYOR_BUILD_FOLDER `
                                    -ChildPath $MainModulePath
    }

    if ($Type -eq 'Wiki')
    {
        # Write the PowerShell help files
        $docoPath = Join-Path -Path $MainModuleFolder `
                              -ChildPath 'en-US'
        New-Item -Path $docoPath -ItemType Directory

        # Clone the DSCResources Module to the repository folder
        $docoHelperPath = Join-Path -Path $PSScriptRoot `
                                    -ChildPath 'DscResource.DocumentationHelper\DscResource.DocumentationHelper.psd1'
        Import-Module -Name $docoHelperPath
        New-DscResourcePowerShellHelp -OutputPath $docoPath -ModulePath $MainModulePath -Verbose

        # Generate the wiki content for the release and zip/publish it to appveyor
        $wikiContentPath = Join-Path -Path $env:APPVEYOR_BUILD_FOLDER -ChildPath "wikicontent"
        New-Item -Path $wikiContentPath -ItemType Directory
        New-DscResourceWikiSite -OutputPath $wikiContentPath -ModulePath $MainModulePath -Verbose

        $zipFileName = Join-Path -Path $env:APPVEYOR_BUILD_FOLDER `
                                 -ChildPath "$($ResourceModuleName)_$($env:APPVEYOR_BUILD_VERSION)_wikicontent.zip"
        Compress-Archive -Path (Join-Path -Path $wikiContentPath -ChildPath '*') `
                         -DestinationPath $zipFileName
        Get-ChildItem -Path $zipFileName | ForEach-Object -Process {
            Push-AppveyorArtifact -Path $_.FullName -FileName $_.Name
        }

        # Remove the readme files that are used to generate documentation so they aren't shipped
        $readmePaths = Join-Path -Path $MainModuleFolder `
                                 -ChildPath '**\readme.md'
        Get-ChildItem -Path $readmePaths -Recurse | Remove-Item -Confirm:$false
    }

    # Set the Module Version in the Manifest to the AppVeyor build version
    $manifestPath = Join-Path -Path $MainModulePath `
                              -ChildPath "$ResourceModuleName.psd1"
    $manifestContent = Get-Content -Path $manifestPath -Raw
    $regex = '(?<=ModuleVersion\s+=\s+'')(?<ModuleVersion>.*)(?='')'
    $manifestContent = $manifestContent -replace $regex,$env:APPVEYOR_BUILD_VERSION
    Set-Content -Path $manifestPath -Value $manifestContent -Force

    # Zip and Publish the Main Module Folder content
    $zipFileName = Join-Path -Path $env:APPVEYOR_BUILD_FOLDER `
                             -ChildPath "$($ResourceModuleName)_$($env:APPVEYOR_BUILD_VERSION).zip"
    Compress-Archive -Path (Join-Path -Path $MainModulePath -ChildPath '*') `
                     -DestinationPath $zipFileName
    New-DscChecksum -Path $env:APPVEYOR_BUILD_FOLDER -Outpath $env:APPVEYOR_BUILD_FOLDER
    Get-ChildItem -Path $zipFileName | ForEach-Object -Process {
        Push-AppveyorArtifact -Path $_.FullName -FileName $_.Name
    }
    Get-ChildItem -Path "$zipFileName.checksum" | ForEach-Object -Process {
        Push-AppveyorArtifact -Path $_.FullName -FileName $_.Name
    }

    # Create the Nuspec file for the Nuget Package in the Main Module Folder
    $nuspecPath = Join-Path -Path $MainModulePath `
                            -ChildPath "$ResourceModuleName.nuspec"
    $nuspecParams = @{
        packageName = $ResourceModuleName
        destinationPath = $MainModulePath
        version = $env:APPVEYOR_BUILD_VERSION
        author = $Author
        owners = $Owners
        licenseUrl = "https://github.com/PowerShell/DscResources/blob/master/LICENSE"
        projectUrl = "https://github.com/$($env:APPVEYOR_REPO_NAME)"
        packageDescription = $ResourceModuleName
        tags = "DesiredStateConfiguration DSC DSCResourceKit"
    }
    New-Nuspec @nuspecParams

    # Create the Nuget Package
    $nugetExePath = Join-Path -Path $env:TEMP `
                              -ChildPath 'nuget.exe'
    Start-Process -FilePath $nugetExePath -Wait -ArgumentList @(
        'Pack',$nuspecPath
        '-OutputDirectory',$env:APPVEYOR_BUILD_FOLDER
        '-BasePath',$MainModulePath
    )

    # Push the Nuget Package up to AppVeyor
    $nugetPackageName = Join-Path -Path $env:APPVEYOR_BUILD_FOLDER `
                                  -ChildPath "$ResourceModuleName.$($env:APPVEYOR_BUILD_VERSION).nupkg"
    Get-ChildItem $nugetPackageName | ForEach-Object -Process {
        Push-AppveyorArtifact -Path $_.FullName -FileName $_.Name
    }

    # Execute custom after test task if defined
    if ($customTaskModuleLoaded `
        -and (Get-Command -Module $CustomAppVeyorTasks `
                          -Name Start-CustomAppveyorAfterTestTask `
                          -ErrorAction SilentlyContinue))
    {
        Start-CustomAppveyorAfterTestTask
    }

    Write-Info -Message 'After Test Task Complete.'
}

<#
    .SYNOPSIS
        Uploads test artifacts

    .PARAMETER Path
        The path to the test artifacts

    .EXAMPLE
        Push-TestArtifact -Path .\TestArtifact.log

#>
function Push-TestArtifact
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]
        $Path
    )

    $resolvedPath = (Resolve-Path $Path).ProviderPath
    if (${env:APPVEYOR_JOB_ID})
    {
        <# does not work with Pester 4.0.2
        $url = "https://ci.appveyor.com/api/testresults/nunit/$($env:APPVEYOR_JOB_ID)"
        Write-Info -Message "Uploading Test Results: $resolvedPath ; to: $url"
        (New-Object 'System.Net.WebClient').UploadFile($url, $resolvedPath)
        #>

        Write-Info -Message "Uploading Test Artifact: $resolvedPath"
        Push-AppveyorArtifact $resolvedPath
    }
    else
    {
        Write-Info -Message "Test Artifact: $resolvedPath"
    }
}

Export-ModuleMember -Function *
