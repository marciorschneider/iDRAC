<#
    .SYNOPSiS
       This example disables the root user on the iDRAC.
#>
Configuration Example    
{
    iDRACGenericProperty DisableRoot
    {
        Ensure = 'Present'
        PropertyName = 'idrac.users.2.enable'
        PropertyValue = 'disabled'
    }
}
