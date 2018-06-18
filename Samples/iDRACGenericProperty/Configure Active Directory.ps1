<#
    .SYNOPSiS
       This example configures an iDRAC device to authenticate agains Active Directory.
#>
Configuration Example    
{
    Import-DscResource -ModuleName idrac
    iDRACGenericProperty iDRACWindowsServerEnabled
    {
        Ensure = 'Present'
        PropertyName = 'idrac.ActiveDirectory.Enable'
        PropertyValue = 'Enabled'
    }    
    iDRACGenericProperty iDRACWindowsServerSchema
    {
        Ensure = 'Present'
        PropertyName = 'idrac.ActiveDirectory.schema'
        PropertyValue = '1'
    }
    iDRACGenericProperty iDRACWindowsServerDCLookupDomainName
    {
        Ensure = 'Present'
        PropertyName = 'idrac.ActiveDirectory.DCLookupDomainName'
        PropertyValue = 'contoso.com'
    }
    iDRACGenericProperty RacDomain
    {
        Ensure = 'Present'
        PropertyName = 'idrac.ActiveDirectory.RacDomain'
        PropertyValue = 'contoso.com'
    }
    iDRACGenericProperty RacName
    {
        Ensure = 'Present'
        PropertyName = 'idrac.ActiveDirectory.RacName'
        PropertyValue = 'SampleServer-iDRACDeviceConfiguration'
    }
    iDRACGenericProperty DNS1
    {
        Ensure = 'Present'
        PropertyName = 'idrac.iPv4.DNS1'
        PropertyValue = '1.1.1.1'
    }
    iDRACGenericProperty DNS2
    {
        Ensure = 'Present'
        PropertyName = 'idrac.iPv4.DNS2'
        PropertyValue = '2.2.2.2'
    }

    iDRACGenericProperty NTPEnable
    {
        Ensure = 'Present'
        PropertyName = 'idrac.NTPConfigGroup.NTPEnable'
        PropertyValue = 'Enabled'
    }
    iDRACGenericProperty NTP1
    {
        Ensure = 'Present'
        PropertyName = 'idrac.NTPConfigGroup.NTP1'
        PropertyValue = 'ntp.contoso.com'
    }
}