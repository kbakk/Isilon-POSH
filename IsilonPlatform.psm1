﻿function New-isiSession{

<#
.SYNOPSIS
    New Isilon Sessison

.DESCRIPTION
    Establishes a new Session with an Isilon Cluster

.EXAMPLE
    New-isiSession -ComputerName 172.19.20.21 -Username root -Password a -Cluster Isilon1

.EXAMPLE
    New-isiSession -ComputerName isilon.domain.com -Username root -Password a -Cluster Isilon2 -default

.EXAMPLE
    "isilon1.domain.com","isilon2.domain.com" | New-isiSession -Username root -Password a

#>

    Param(
            [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true,ValueFromPipeline=$true)][ValidateNotNullOrEmpty()][string] $ComputerName, 
            [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][string] $Username, 
            [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][string] $Password,
            [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][string]$Cluster,
            [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)][switch]$default)

    Begin{
        
        # test if the isi_session variables already exists
        if(!(test-path ('variable:\isi_sessions')) ){
            $script:isi_sessions = @()
        }
        if(!(test-path ('variable:\isi_sessiondefault')) ){
            $script:isi_sessiondefault = $Cluster
        }

    } 
    Process {

        if (!$Cluster) {
            $Cluster = $ComputerName
        }

        $ComputerName = ([System.Net.Dns]::GetHostAddresses($ComputerName)).IPAddressToString
        $baseurl = "https://$ComputerName`:8080"

        #create Jason Object for Input Values
        $jobj = convertto-json (New-Object PSObject -Property @{username= $Username;password = $Password; services = ("platform",“namespace”)})

        #create session
        $ISIObject = Invoke-RestMethod -Uri "$baseurl/session/1/session" -Body $jobj -ContentType "application/json; charset=utf-8" -Method POST -SessionVariable session -ErrorAction Stop -ErrorVariable myErr -TimeoutSec 15 -DisableKeepAlive

        #remove cluster if entry exists
        Clear-isiSession -Cluster $Cluster
        
        #add new cluster
        $script:isi_sessions += New-Object -TypeName psObject -Property @{cluster = $Cluster; url=$baseurl; session= $session; timeout_absolute=(Get-Date).AddSeconds($ISIObject.timeout_absolute); timeout=(Get-Date).AddSeconds($ISIObject.timeout_inactive); timeout_inactive=$ISIObject.timeout_inactive;username=$ISIObject.username}

        #if default $true or default cluster not present set current cluster 
        if ($default -or (@($isi_sessions | where { $_.cluster -eq $isi_sessiondefault} ).count -eq 0)){
            $script:isi_sessiondefault = $Cluster
        }

        Remove-Variable Cluster

    }
    
    End {
        
        
    }
}

function Get-isiSessioninfo {

<#
.SYNOPSIS
    Get Isilon Sessison Info

.DESCRIPTION

.EXAMPLE
    Get-isiSessioninfo

.EXAMPLE
    Get-isiSessioninfo -Cluster Isilon1

.EXAMPLE
    "isilon1.domain.com","isilon2.domain.com" | Get-isiSessioninfo


.NOTES
    

#>
    Param([Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true,ValueFromPipeline=$true)][string]$Cluster=$isi_sessiondefault)

    Begin{

    }
    Process{
        Send-isiAPI -Method 'GET' -Resource "/session/1/session" -Cluster $Cluster
    }

    End{

    }
}

function Get-isiSession {

<#
.SYNOPSIS
    Display Isilon Sessisons

.DESCRIPTION

.EXAMPLE
    Get-isiSession

.EXAMPLE
    Get-isiSession -Cluster Isilon1

.NOTES
    

#>

    Param([string]$Cluster,[switch]$default)

    if($default){
        $isi_sessiondefault
    }
    Elseif($Cluster){
        $isi_sessions | where { $_.cluster -eq $Cluster }
    }else{
        $isi_sessions
    }
}

function Clear-isiSession {

<#
.SYNOPSIS
    Clear Isilon Sessison

.DESCRIPTION

.EXAMPLE
    Clear-isiSession

.EXAMPLE
    Clear-isiSession -Cluster Isilon1

.NOTES
    

#>

    param ([Parameter(Mandatory=$False,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,Position=0)][string]$Cluster)

    if($Cluster){

        foreach($clust in $Cluster){   
            $script:isi_sessions = @($isi_sessions | where { $_.cluster -ne $clust })
        }

    } Else {
        remove-variable -scope script isi_sessions
        remove-variable -scope script isi_sessiondefault
    }
}

function Remove-isiSession {

<#
.SYNOPSIS
    Removes Isilon Sessison

.DESCRIPTION

.EXAMPLE
    Remove-isiSession

.EXAMPLE
    Remove-isiSession -Cluster Isilon1

.EXAMPLE
    "isilon1.domain.com","isilon2.domain.com" | Remove-isiSession

.NOTES
    

#>

    Param([Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true,ValueFromPipeline=$true)][string]$Cluster=$isi_sessiondefault)

    Begin{

    }

    Process{        

        if (@($isi_sessions | where { $_.cluster -eq $Cluster} ).count -eq 1){
            
            #remove session on the isilon cluster
            Send-isiAPI -Resource "/session/1/session" -Cluster $Cluster -Method 'delete'
            #remove entry if exists
            Clear-isiSession -Cluster $Cluster

        }

        if (@($isi_sessions | where { $_.cluster -eq $isi_sessiondefault} ).count -eq 0){
            $script:isi_sessiondefault = $isi_sessions[0].cluster
        }
        

    }

    End{
    }
        
}

function Send-isiAPI{

<#
.SYNOPSIS
    sends Rest Command to Ision API

.DESCRIPTION

.EXAMPLE
    Send-isiAPI -Resource "/platform/1/protocols/smb/shares" -Cluster IsilonC1 -Method GET

.NOTES

#>

    Param(
    [Parameter(Mandatory=$True)][string]$Resource,[string]$Method="GET",
    $body,
    [string]$Cluster=$isi_sessiondefault)

    $isi_session = Get-isiSession -Cluster $Cluster
    $url = $isi_session.url + $Resource
    $session = $isi_session.session
    $Method = $Method.ToUpper()
    $timeout = 60
    
    if (!$Cluster){
        Write-Error "No Cluster connected!"

    }elseif (@($isi_sessions | where { $_.cluster -eq $Cluster }).count -eq 0){
        Write-Error "Cluster $Cluster not connected!"
        

    }elseif (((Get-Date) -gt $isi_session.timeout) -or ((Get-Date) -gt $isi_session.timeout_absolute)){
        Write-Error "Session timeout for $Cluster!"
        

    }else{
        
        switch($Method){
            "GET_JSON"{ 
                #$ISIObject = Invoke-RestMethod -Uri $url -Method GET -WebSession $session -TimeoutSec $timeout
                $ISIObject = (Invoke-WebRequest -Uri $url -Method GET -WebSession $session -TimeoutSec $timeout).content

             }
            "GET"{ 
                #$ISIObject = Invoke-RestMethod -Uri $url -Method $Method -WebSession $session -TimeoutSec $timeout
                $ISIObject = (Invoke-WebRequest -Uri $url -Method $Method -WebSession $session -TimeoutSec $timeout).content | ConvertFrom-Json

             }
            "POST"{ 
                #$ISIObject = Invoke-RestMethod -Uri $url -Method $Method -WebSession $session -Body $body -ContentType "application/json; charset=utf-8" -TimeoutSec $timeout
                $ISIObject = (Invoke-WebRequest -Uri $url -Method $Method -WebSession $session -Body $body -ContentType "application/json; charset=utf-8" -TimeoutSec $timeout).content | ConvertFrom-Json
            }
            "PUT"{ 
                #$ISIObject = Invoke-RestMethod -Uri $url -Method $Method -WebSession $session -Body $body -ContentType "application/json; charset=utf-8" -TimeoutSec $timeout
                $ISIObject = (Invoke-WebRequest -Uri $url -Method $Method -WebSession $session -Body $body -ContentType "application/json; charset=utf-8" -TimeoutSec $timeout).content | ConvertFrom-Json
            }
            "DELETE"{ 
                #$ISIObject = Invoke-RestMethod -Uri $url -Method $Method -WebSession $session -TimeoutSec $timeout
                $ISIObject = (Invoke-WebRequest -Uri $url -Method $Method -WebSession $session -TimeoutSec $timeout).content | ConvertFrom-Json
            }

        }
        $isi_session.timeout = (Get-Date).AddSeconds($isi_session.timeout_inactive)
        $ISIObject
    }
}

Export-ModuleMember -Function New-isiSession
Export-ModuleMember -Function Get-isiSession
Export-ModuleMember -Function Get-isiSessioninfo
Export-ModuleMember -Function Remove-isiSession
Export-ModuleMember -Function Send-isiAPI

function Get-isiSMBSharesSummary{
<#
.SYNOPSIS
    Get Isilon SMB Shares
    
.DESCRIPTION
    Returns Isilon SMB Shares

.PARAMETER sharename
    name of share
        Required?                    false 
        Position?                    0
        Default value                
        Accept pipeline input?       true
        Accept wildcard characters?  false
 
.EXAMPLE
    Get-isiSMBSharesSummary

.EXAMPLE
    Get-isiSMBSharesSummary -Cluster Isilon1

.EXAMPLE
    'Isilon1','Isilon2' | Get-isiSMBSharesSummary


.NOTES

#>

	[CmdletBinding()]
	
    param (
	[Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true,ValueFromPipeline=$true,Position=0)][string]$Cluster=$isi_sessiondefault)

    Begin{
        
    }
    Process{
    
            Send-isiAPI -Cluster $Cluster -Method GET_JSON -Resource "/platform/1/protocols/smb/shares?describe"
                
    }

    End{

    }
	
}

function Get-isiSMBShares{
<#
.SYNOPSIS
    Get Isilon SMB Shares
    
.DESCRIPTION
    Returns Isilon SMB Shares

.EXAMPLE
    Get-ISISMBShares

.EXAMPLE
    Get-ISISMBShares -Cluster Isilon1

.EXAMPLE
    Get-ISISMBShares -name ifs

.EXAMPLE
    'ifs','share1' | Get-ISISMBShares


.NOTES

#>

	[CmdletBinding()]
	
	param (
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true,ValueFromPipeline=$true,Position=0)][string[]]$name,
            [string]$Cluster=$isi_sessiondefault)

    Begin{
        
    }
    Process{
    
        # Check if id parameter passed
        if($name){
            $ISIObject = Send-isiAPI -Cluster $Cluster -Method GET -Resource "/platform/1/protocols/smb/shares/$name"
            $ISIObject.shares

        } else{
            $ISIObject =Send-isiAPI -Cluster $Cluster -Method GET -Resource "/platform/1/protocols/smb/shares"
            $ISIObject.shares
        }

    }
    End{

    }
	
}

function Get-isiSMBSettingsSharesSummary{
<#
.SYNOPSIS
    Get Isilon SMB Shares Settings Summary
    
.DESCRIPTION
    Returns Isilon SMB Shares Settings Summary

.EXAMPLE
    Get-isiSMBSettingsSharesSummary

.EXAMPLE
    Get-isiSMBSettingsSharesSummary -Cluster Isilon1

.EXAMPLE
    ('Isilon1','Isilon2') | Get-isiSMBSettingsSharesSummary


.NOTES

#>

	[CmdletBinding()]
	
    param (
	[Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true,ValueFromPipeline=$true,Position=0)][string]$Cluster=$isi_sessiondefault)

    Begin{
        
    }
    Process{
    
            Send-isiAPI -Cluster $Cluster -Method GET_JSON -Resource "/platform/1/protocols/smb/settings/share?describe"
                
    }

    End{

    }
	
}

function Get-isiSMBSettingsShares{
<#
.SYNOPSIS
    Get Isilon SMB Shares Settings
    
.DESCRIPTION
    Returns Isilon SMB Shares Settings

.EXAMPLE
    Get-isiSMBSettingsShares

.EXAMPLE
    Get-isiSMBSettingsShares -Cluster Isilon1

.NOTES

#>

	[CmdletBinding()]
	
	param (
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true,ValueFromPipeline=$true,Position=0)][string]$Cluster=$isi_sessiondefault)

    Begin{
        
    }
    Process{

        $ISIObject = Send-isiAPI -Cluster $Cluster -Method GET -Resource "/platform/1/protocols/smb/settings/share"
        $ISIObject.settings
    }
    End{

    }
	
}

function Get-isiSMBSettingsGlobalSummary{
<#
.SYNOPSIS
    Get Isilon SMB Shares Global Settings Summary
    
.DESCRIPTION
    Returns Isilon SMB Shares Global Settings Summary

.EXAMPLE
    Get-isiSMBSettingsGlobalSummary

.EXAMPLE
    Get-isiSMBSettingsGlobalSummary -Cluster Isilon1

.EXAMPLE
    ('Isilon1','Isilon2') | Get-isiSMBSettingsGlobalSummary


.NOTES

#>

	[CmdletBinding()]
	
    param (
	[Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true,ValueFromPipeline=$true,Position=0)][string]$Cluster=$isi_sessiondefault)

    Begin{
        
    }
    Process{
    
            Send-isiAPI -Cluster $Cluster -Method GET_JSON -Resource "/platform/1/protocols/smb/settings/global?describe"
                
    }

    End{

    }
	
}

function Get-isiSMBSettingsGlobal{
<#
.SYNOPSIS
    Get Isilon SMB Shares Global Settings
    
.DESCRIPTION
    Returns Isilon SMB Shares Global Settings

.EXAMPLE
    Get-isiSMBSettingsGlobal

.EXAMPLE
    Get-isiSMBSettingsGlobal -Cluster Isilon1

.EXAMPLE
    ('Isilon1','Isilon2') | Get-isiSMBSettingsGlobal


.NOTES

#>

	[CmdletBinding()]
	
	param (
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true,ValueFromPipeline=$true,Position=0)][string]$Cluster=$isi_sessiondefault)

    Begin{
        
    }
    Process{

        $ISIObject = Send-isiAPI -Cluster $Cluster -Method GET -Resource "/platform/1/protocols/smb/settings/global"
        $ISIObject.settings
    }
    End{

    }
	
}

function Get-isiSMBOpenfilesSummary{
<#
.SYNOPSIS
    Get Isilon SMB open files summary
    
.DESCRIPTION
    Returns Isilon SMB open files summary

.EXAMPLE
    Get-isiSMBOpenfilesSummary

.EXAMPLE
    Get-isiSMBOpenfilesSummary -Cluster Isilon1

.EXAMPLE
    ('Isilon1','Isilon2') | Get-isiSMBOpenfilesSummary


.NOTES

#>

	[CmdletBinding()]
	
    param (
	[Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true,ValueFromPipeline=$true,Position=0)][string]$Cluster=$isi_sessiondefault)

    Begin{
        
    }
    Process{
    
            Send-isiAPI -Cluster $Cluster -Method GET_JSON -Resource "/platform/1/protocols/smb/openfiles?describe"
                
    }

    End{

    }
	
}

function Get-isiSMBOpenfiles{
<#
.SYNOPSIS
    Get Isilon SMB open files
    
.DESCRIPTION
    Returns Isilon SMB open files

.EXAMPLE
    Get-isiSMBOpenfiles

.EXAMPLE
    Get-isiSMBOpenfiles -Cluster Isilon1

.EXAMPLE
    ('Isilon1','Isilon2') | Get-isiSMBOpenfiles


.NOTES


.NOTES

#>

	[CmdletBinding()]
	
	param (
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true,ValueFromPipeline=$true,Position=0)][string]$Cluster=$isi_sessiondefault)

    Begin{
        
    }
    Process{

        $ISIObject = Send-isiAPI -Cluster $Cluster -Method GET -Resource "/platform/1/protocols/smb/openfiles"
        $ISIObject.openfiles
    }
    End{

    }
	
}

function New-isiSMBShares{
<#
.SYNOPSIS
    New Isilon SMB Shares
    
.DESCRIPTION
    New Isilon SMB Shares

.EXAMPLE
    New-isiSMBShares -name share1 -path '/ifs/data'

.EXAMPLE
    New-isiSMBShares -name share1 -path '/ifs/data' -Cluster Isilon1

.NOTES

#>
            [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='High')]
	
	param (            
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$access_based_enumeration,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$access_based_enumeration_root_only,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$allow_delete_readonly,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$allow_execute_always,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$allow_variable_expansion,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$auto_create_directory,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$browsable,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][ValidateSet('all','norecurse','none')][string]$change_notify,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][ValidateSet('default acl','inherit mode bits','use create mask and mode')][string]$create_permissions,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][ValidateSet('manual','documents','programs','none')][string]$csc_policy,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][string]$description,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][int]$directory_create_mask,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][int]$directory_create_mode,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][int]$file_create_mask,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][int]$file_create_mode,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$hide_dot_files,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][array]$host_acl,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][ValidateSet('always','bad user','never')][string]$impersonate_guest,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][string]$impersonate_user,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$inheritable_path_acl,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][int]$mangle_byte_start,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][array]$mangle_map,
            [Parameter(Mandatory=$True,ValueFromPipelineByPropertyName=$true,Position=0)][ValidateNotNullOrEmpty()][string]$name,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$ntfs_acl_support,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$oplocks,
            [Parameter(Mandatory=$True,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][string]$path,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][array]$permissions,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][array]$run_as_root,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$strict_flush,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$strict_locking,
            [switch]$Force,
            [string]$Cluster=$isi_sessiondefault)

    Begin{
            
            
            

    }
    Process{

            #create object
            $obj = [pscustomobject]@{}
            if ($PSBoundParameters.ContainsKey('access_based_enumeration')){ Add-Member -InputObject $obj -type NoteProperty -name access_based_enumeration -value $access_based_enumeration }
            if ($PSBoundParameters.ContainsKey('access_based_enumeration_root_only')){ Add-Member -InputObject $obj -type NoteProperty -name access_based_enumeration_root_only -value $access_based_enumeration_root_only }
            if ($PSBoundParameters.ContainsKey('allow_delete_readonly')){ Add-Member -InputObject $obj -type NoteProperty -name allow_delete_readonly -value $allow_delete_readonly }
            if ($PSBoundParameters.ContainsKey('allow_execute_always')){ Add-Member -InputObject $obj -type NoteProperty -name allow_execute_always -value $allow_execute_always }
            if ($PSBoundParameters.ContainsKey('allow_variable_expansion')){ Add-Member -InputObject $obj -type NoteProperty -name allow_variable_expansion -value $allow_variable_expansion }
            if ($PSBoundParameters.ContainsKey('auto_create_directory')){ Add-Member -InputObject $obj -type NoteProperty -name auto_create_directory -value $auto_create_directory }
            if ($PSBoundParameters.ContainsKey('browsable')){ Add-Member -InputObject $obj -type NoteProperty -name browsable -value $browsable }
            if ($PSBoundParameters.ContainsKey('change_notify')){ Add-Member -InputObject $obj -type NoteProperty -name change_notify -value $change_notify }
            if ($PSBoundParameters.ContainsKey('create_permissions')){ Add-Member -InputObject $obj -type NoteProperty -name create_permissions -value $create_permissions }
            if ($PSBoundParameters.ContainsKey('csc_policy')){ Add-Member -InputObject $obj -type NoteProperty -name csc_policy -value $csc_policy }
            if ($PSBoundParameters.ContainsKey('description')){ Add-Member -InputObject $obj -type NoteProperty -name description -value $description }
            if ($PSBoundParameters.ContainsKey('directory_create_mask')){ Add-Member -InputObject $obj -type NoteProperty -name directory_create_mask -value $directory_create_mask }
            if ($PSBoundParameters.ContainsKey('directory_create_mode')){ Add-Member -InputObject $obj -type NoteProperty -name directory_create_mode -value $directory_create_mode }
            if ($PSBoundParameters.ContainsKey('file_create_mask')){ Add-Member -InputObject $obj -type NoteProperty -name file_create_mask -value $file_create_mask }
            if ($PSBoundParameters.ContainsKey('file_create_mask')){ Add-Member -InputObject $obj -type NoteProperty -name file_create_mode -value $file_create_mode }
            if ($PSBoundParameters.ContainsKey('hide_dot_files')){ Add-Member -InputObject $obj -type NoteProperty -name hide_dot_files -value $hide_dot_files }
            if ($PSBoundParameters.ContainsKey('host_acl')){ Add-Member -InputObject $obj -type NoteProperty -name host_acl -value $host_acl }
            if ($PSBoundParameters.ContainsKey('impersonate_guest')){ Add-Member -InputObject $obj -type NoteProperty -name impersonate_guest -value $impersonate_guest }
            if ($PSBoundParameters.ContainsKey('impersonate_user')){ Add-Member -InputObject $obj -type NoteProperty -name impersonate_user -value $impersonate_user }
            if ($PSBoundParameters.ContainsKey('inheritable_path_acl')){ Add-Member -InputObject $obj -type NoteProperty -name inheritable_path_acl -value $inheritable_path_acl }
            if ($PSBoundParameters.ContainsKey('mangle_byte_start')){ Add-Member -InputObject $obj -type NoteProperty -name mangle_byte_start -value $mangle_byte_start }
            if ($PSBoundParameters.ContainsKey('mangle_map')){ Add-Member -InputObject $obj -type NoteProperty -name mangle_map -value $mangle_map }
            Add-Member -InputObject $obj -type NoteProperty -name name -value $name
            if ($PSBoundParameters.ContainsKey('ntfs_acl_support')){ Add-Member -InputObject $obj -type NoteProperty -name ntfs_acl_support -value $ntfs_acl_support }
            if ($PSBoundParameters.ContainsKey('oplocks')){ Add-Member -InputObject $obj -type NoteProperty -name oplocks -value $oplocks }
            Add-Member -InputObject $obj -type NoteProperty -name path -value $path
            if ($PSBoundParameters.ContainsKey('permissions')){ Add-Member -InputObject $obj -type NoteProperty -name permissions -value $permissions }
            if ($PSBoundParameters.ContainsKey('run_as_root')){ Add-Member -InputObject $obj -type NoteProperty -name run_as_root -value $run_as_root }
            if ($PSBoundParameters.ContainsKey('strict_flush')){ Add-Member -InputObject $obj -type NoteProperty -name strict_flush -value $strict_flush }
            if ($PSBoundParameters.ContainsKey('strict_locking')){ Add-Member -InputObject $obj -type NoteProperty -name strict_locking -value $strict_locking }

            if ($Force -or $PSCmdlet.ShouldProcess("$name","New-isiSMBShares")){
                $ISIObject = Send-isiAPI -Cluster $Cluster -Method POST -Resource "/platform/1/protocols/smb/shares" -body (convertto-json -depth 40 $obj)
            }
    }
    End{

    }
	
}

function Set-isiSMBShares{
<#
.SYNOPSIS
    Set Isilon SMB Shares
    
.DESCRIPTION
    Modifies Isilon SMB Shares

.EXAMPLE
    Set-isiSMBShares -name share1 -description 'share for users'

.NOTES

#>
            [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='High')]
	
	param (            
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$access_based_enumeration,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$access_based_enumeration_root_only,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$allow_delete_readonly,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$allow_execute_always,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$allow_variable_expansion,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$auto_create_directory,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$browsable,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][ValidateSet('all','norecurse','none')][string]$change_notify,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][ValidateSet('default acl','inherit mode bits','use create mask and mode')][string]$create_permissions,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][ValidateSet('manual','documents','programs','none')][string]$csc_policy,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][string]$description,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][int]$directory_create_mask,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][int]$directory_create_mode,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][int]$file_create_mask,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][int]$file_create_mode,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$hide_dot_files,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][array]$host_acl,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][ValidateSet('always','bad user','never')][string]$impersonate_guest,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][string]$impersonate_user,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$inheritable_path_acl,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][int]$mangle_byte_start,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][array]$mangle_map,
            [Parameter(Mandatory=$True,ValueFromPipelineByPropertyName=$true,Position=0)][ValidateNotNullOrEmpty()][string]$name,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$ntfs_acl_support,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$oplocks,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][string]$path,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][array]$permissions,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][array]$run_as_root,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$strict_flush,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$strict_locking,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][string]$new_name,
            [switch]$Force,
            [string]$Cluster=$isi_sessiondefault)

    Begin{           
            

    }
    Process{

            #create object
            $obj = [pscustomobject]@{}
            if ($PSBoundParameters.ContainsKey('access_based_enumeration')){ Add-Member -InputObject $obj -type NoteProperty -name access_based_enumeration -value $access_based_enumeration }
            if ($PSBoundParameters.ContainsKey('access_based_enumeration_root_only')){ Add-Member -InputObject $obj -type NoteProperty -name access_based_enumeration_root_only -value $access_based_enumeration_root_only }
            if ($PSBoundParameters.ContainsKey('allow_delete_readonly')){ Add-Member -InputObject $obj -type NoteProperty -name allow_delete_readonly -value $allow_delete_readonly }
            if ($PSBoundParameters.ContainsKey('allow_execute_always')){ Add-Member -InputObject $obj -type NoteProperty -name allow_execute_always -value $allow_execute_always }
            if ($PSBoundParameters.ContainsKey('allow_variable_expansion')){ Add-Member -InputObject $obj -type NoteProperty -name allow_variable_expansion -value $allow_variable_expansion }
            if ($PSBoundParameters.ContainsKey('auto_create_directory')){ Add-Member -InputObject $obj -type NoteProperty -name auto_create_directory -value $auto_create_directory }
            if ($PSBoundParameters.ContainsKey('browsable')){ Add-Member -InputObject $obj -type NoteProperty -name browsable -value $browsable }
            if ($PSBoundParameters.ContainsKey('change_notify')){ Add-Member -InputObject $obj -type NoteProperty -name change_notify -value $change_notify }
            if ($PSBoundParameters.ContainsKey('create_permissions')){ Add-Member -InputObject $obj -type NoteProperty -name create_permissions -value $create_permissions }
            if ($PSBoundParameters.ContainsKey('csc_policy')){ Add-Member -InputObject $obj -type NoteProperty -name csc_policy -value $csc_policy }
            if ($PSBoundParameters.ContainsKey('description')){ Add-Member -InputObject $obj -type NoteProperty -name description -value $description }
            if ($PSBoundParameters.ContainsKey('directory_create_mask')){ Add-Member -InputObject $obj -type NoteProperty -name directory_create_mask -value $directory_create_mask }
            if ($PSBoundParameters.ContainsKey('directory_create_mode')){ Add-Member -InputObject $obj -type NoteProperty -name directory_create_mode -value $directory_create_mode }
            if ($PSBoundParameters.ContainsKey('file_create_mask')){ Add-Member -InputObject $obj -type NoteProperty -name file_create_mask -value $file_create_mask }
            if ($PSBoundParameters.ContainsKey('file_create_mask')){ Add-Member -InputObject $obj -type NoteProperty -name file_create_mode -value $file_create_mode }
            if ($PSBoundParameters.ContainsKey('hide_dot_files')){ Add-Member -InputObject $obj -type NoteProperty -name hide_dot_files -value $hide_dot_files }
            if ($PSBoundParameters.ContainsKey('host_acl')){ Add-Member -InputObject $obj -type NoteProperty -name host_acl -value $host_acl }
            if ($PSBoundParameters.ContainsKey('impersonate_guest')){ Add-Member -InputObject $obj -type NoteProperty -name impersonate_guest -value $impersonate_guest }
            if ($PSBoundParameters.ContainsKey('impersonate_user')){ Add-Member -InputObject $obj -type NoteProperty -name impersonate_user -value $impersonate_user }
            if ($PSBoundParameters.ContainsKey('inheritable_path_acl')){ Add-Member -InputObject $obj -type NoteProperty -name inheritable_path_acl -value $inheritable_path_acl }
            if ($PSBoundParameters.ContainsKey('mangle_byte_start')){ Add-Member -InputObject $obj -type NoteProperty -name mangle_byte_start -value $mangle_byte_start }
            if ($PSBoundParameters.ContainsKey('mangle_map')){ Add-Member -InputObject $obj -type NoteProperty -name mangle_map -value $mangle_map }
            if ($PSBoundParameters.ContainsKey('new_name')){Add-Member -InputObject $obj -type NoteProperty -name name -value $new_name}
            if ($PSBoundParameters.ContainsKey('ntfs_acl_support')){ Add-Member -InputObject $obj -type NoteProperty -name ntfs_acl_support -value $ntfs_acl_support }
            if ($PSBoundParameters.ContainsKey('oplocks')){ Add-Member -InputObject $obj -type NoteProperty -name oplocks -value $oplocks }
            if ($PSBoundParameters.ContainsKey('path')){Add-Member -InputObject $obj -type NoteProperty -name path -value $path}
            if ($PSBoundParameters.ContainsKey('permissions')){ Add-Member -InputObject $obj -type NoteProperty -name permissions -value $permissions }
            if ($PSBoundParameters.ContainsKey('run_as_root')){ Add-Member -InputObject $obj -type NoteProperty -name run_as_root -value $run_as_root }
            if ($PSBoundParameters.ContainsKey('strict_flush')){ Add-Member -InputObject $obj -type NoteProperty -name strict_flush -value $strict_flush }
            if ($PSBoundParameters.ContainsKey('strict_locking')){ Add-Member -InputObject $obj -type NoteProperty -name strict_locking -value $strict_locking }

            if ($Force -or $PSCmdlet.ShouldProcess("$name","New-isiSMBShares")){
                $ISIObject = Send-isiAPI -Cluster $Cluster -Method PUT -Resource "/platform/1/protocols/smb/shares/$name" -body (convertto-json -depth 40 $obj)
                $ISIObject
            }
    }
    End{

    }
	
}

function Remove-isiSMBShares{
<#
.SYNOPSIS
    Remove Isilon SMB Shares
    
.DESCRIPTION
    Removes Isilon SMB Shares

.EXAMPLE
    Remove-isiSMBShares -name share1

.EXAMPLE
    'share1','share2' | Remove-isiSMBShares


.NOTES

#>

	[CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='High')]
	
	param (
            [Parameter(Mandatory=$True,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,Position=0)][string[]]$name,
            [switch]$Force,
            [string]$Cluster=$isi_sessiondefault)

    Begin{ 

    }
    Process{      
        #execute
        if ($Force -or $PSCmdlet.ShouldProcess("$name","Remove-isiSMBShares")){
            $ISIObject = Send-isiAPI -Cluster $Cluster -Method DELETE -Resource "/platform/1/protocols/smb/shares/$name"
        }
    }

    End{

    }
	
}

Export-ModuleMember -Function Get-isiSMBSharesSummary
Export-ModuleMember -Function Get-isiSMBShares
Export-ModuleMember -Function New-isiSMBShares
Export-ModuleMember -Function Set-isiSMBShares
Export-ModuleMember -Function Remove-isiSMBShares
Export-ModuleMember -Function Get-isiSMBSettingsSharesSummary
Export-ModuleMember -Function Get-isiSMBSettingsShares
Export-ModuleMember -Function Get-isiSMBSettingsGlobalSummary
Export-ModuleMember -Function Get-isiSMBSettingsGlobal
Export-ModuleMember -Function Get-isiSMBOpenfilesSummary
Export-ModuleMember -Function Get-isiSMBOpenfiles


function Get-isiZonesSummary{
<#
.SYNOPSIS
    Get Isilon Zones Summary
    
.DESCRIPTION
    Returns Isilon Zones Summary


.EXAMPLE
    Get-isiZonesSummary

.EXAMPLE
    Get-isiZonesSummary -Cluster Isilon1

.NOTES

#>

	[CmdletBinding()]
	
	param ([string]$Cluster=$isi_sessiondefault)

    Begin{
        
    }
    Process{
    
            Send-isiAPI -Cluster $Cluster -Method GET_JSON -Resource "/platform/1/zones?describe"
                
    }

    End{

    }
	
}

function Get-isiZones{

<#
.SYNOPSIS
    Get Isilon Zones
    
.DESCRIPTION
    Returns Isilon Zones


.EXAMPLE
    Get-isiZones

.EXAMPLE
    Get-isiZones -Cluster Isilon1

.EXAMPLE
    ('Isilon1','Isilon2') | Get-isiZones

.NOTES
    

#>

	[CmdletBinding()]
	
	param ([Parameter(Mandatory=$False,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,Position=0)][string]$name,
            [string]$Cluster=$isi_sessiondefault)

    Begin{

    }
    Process{
        # Check if id parameter passed
        if($name){
            #execute
            $ISIObject = Send-isiAPI -Cluster $Cluster -Method GET -Resource "/platform/1/zones/$name"
            $ISIObject.zones

        } else{
            $ISIObject = Send-isiAPI -Cluster $Cluster -Method GET -Resource "/platform/1/zones"
            $ISIObject.zones
        }
    }
    End{

    }
	
}

function Set-isiZones {
<#
.SYNOPSIS
    Set Isilon Zone
    
.DESCRIPTION
    Modifies Isilon Zone

.EXAMPLE
    Set-isiZones -name ZoneA -new_name ZoneA2

.NOTES

#>

	
    [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='High')]
	
	param (            
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$all_auth_providers,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$all_smb_shares,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][string]$alternate_system_provider,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][array]$auth_providers,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][int]$cache_size,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][int]$home_directory_umask,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][array]$ifs_restricted,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$local_provider,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][string]$map_untrusted,
            [Parameter(Mandatory=$True,ValueFromPipelineByPropertyName=$true,Position=0)][ValidateNotNullOrEmpty()][string]$name,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][string]$netbios_name,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][string]$skeleton_directory,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][array]$smb_shares,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][string]$system_provider,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][array]$user_mapping_rules,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][string]$new_name,
            [switch]$Force,
            [string]$Cluster=$isi_sessiondefault)

    Begin{
    }
    Process{

            #create object
            $obj = [pscustomobject]@{}
            if ($PSBoundParameters.ContainsKey('all_auth_providers')){ Add-Member -InputObject $obj -type NoteProperty -name all_auth_providers -value $all_auth_providers }
            if ($PSBoundParameters.ContainsKey('all_smb_shares')){ Add-Member -InputObject $obj -type NoteProperty -name all_smb_shares -value $all_smb_shares }
            if ($PSBoundParameters.ContainsKey('alternate_system_provider')){ Add-Member -InputObject $obj -type NoteProperty -name alternate_system_provider -value $alternate_system_provider }
            if ($PSBoundParameters.ContainsKey('auth_providers')){ Add-Member -InputObject $obj -type NoteProperty -name auth_providers -value $auth_providers }
            if ($PSBoundParameters.ContainsKey('cache_size')){ Add-Member -InputObject $obj -type NoteProperty -name cache_size -value $cache_size }
            if ($PSBoundParameters.ContainsKey('home_directory_umask')){ Add-Member -InputObject $obj -type NoteProperty -name home_directory_umask -value $home_directory_umask }
            if ($PSBoundParameters.ContainsKey('ifs_restricted')){ Add-Member -InputObject $obj -type NoteProperty -name ifs_restricted -value $ifs_restricted }
            if ($PSBoundParameters.ContainsKey('local_provider')){ Add-Member -InputObject $obj -type NoteProperty -name local_provider -value $local_provider }
            if ($PSBoundParameters.ContainsKey('map_untrusted')){ Add-Member -InputObject $obj -type NoteProperty -name map_untrusted -value $map_untrusted }
            if ($PSBoundParameters.ContainsKey('new_name')){Add-Member -InputObject $obj -type NoteProperty -name name -value $new_name}
            if ($PSBoundParameters.ContainsKey('netbios_name')){ Add-Member -InputObject $obj -type NoteProperty -name netbios_name -value $netbios_name }
            if ($PSBoundParameters.ContainsKey('skeleton_directory')){ Add-Member -InputObject $obj -type NoteProperty -name skeleton_directory -value $skeleton_directory }
            if ($PSBoundParameters.ContainsKey('smb_shares')){ Add-Member -InputObject $obj -type NoteProperty -name smb_shares -value $smb_shares }
            if ($PSBoundParameters.ContainsKey('system_provider')){ Add-Member -InputObject $obj -type NoteProperty -name system_provider -value $system_provider }
            if ($PSBoundParameters.ContainsKey('user_mapping_rules')){ Add-Member -InputObject $obj -type NoteProperty -name user_mapping_rules -value $user_mapping_rules }

            if ($Force -or $PSCmdlet.ShouldProcess("$name","Set-isiZones")){
                $ISIObject = Send-isiAPI -Cluster $Cluster -Method PUT -Resource "/platform/1/zones/$name" -body (convertto-json -depth 40 $obj)
            }
    }
    End{

    }
	
}

function New-isiZones{
<#
.SYNOPSIS
    New Isilon SMB Zone
    
.DESCRIPTION
    New Isilon SMB Zone

.EXAMPLE
    New-isiZones -name Zone1

.EXAMPLE
    New-isiZones -Cluster ision1 -name Zone1

.NOTES

#>
            [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='High')]
	
	param (            
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$all_auth_providers,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$all_smb_shares,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][string]$alternate_system_provider,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][array]$auth_providers,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][int]$cache_size,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][int]$home_directory_umask,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][array]$ifs_restricted,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$local_provider,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][string]$map_untrusted,
            [Parameter(Mandatory=$True,ValueFromPipelineByPropertyName=$true,Position=0)][ValidateNotNullOrEmpty()][string]$name,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][string]$netbios_name,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][string]$skeleton_directory,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][array]$smb_shares,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][string]$system_provider,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][array]$user_mapping_rules,
            [switch]$Force,
            [string]$Cluster=$isi_sessiondefault)

    Begin{
    }
    Process{

            #create object
            $obj = [pscustomobject]@{}
            if ($PSBoundParameters.ContainsKey('all_auth_providers')){ Add-Member -InputObject $obj -type NoteProperty -name all_auth_providers -value $all_auth_providers }
            if ($PSBoundParameters.ContainsKey('all_smb_shares')){ Add-Member -InputObject $obj -type NoteProperty -name all_smb_shares -value $all_smb_shares }
            if ($PSBoundParameters.ContainsKey('alternate_system_provider')){ Add-Member -InputObject $obj -type NoteProperty -name alternate_system_provider -value $alternate_system_provider }
            if ($PSBoundParameters.ContainsKey('auth_providers')){ Add-Member -InputObject $obj -type NoteProperty -name auth_providers -value $auth_providers }
            if ($PSBoundParameters.ContainsKey('cache_size')){ Add-Member -InputObject $obj -type NoteProperty -name cache_size -value $cache_size }
            if ($PSBoundParameters.ContainsKey('home_directory_umask')){ Add-Member -InputObject $obj -type NoteProperty -name home_directory_umask -value $home_directory_umask }
            if ($PSBoundParameters.ContainsKey('ifs_restricted')){ Add-Member -InputObject $obj -type NoteProperty -name ifs_restricted -value $ifs_restricted }
            if ($PSBoundParameters.ContainsKey('local_provider')){ Add-Member -InputObject $obj -type NoteProperty -name local_provider -value $local_provider }
            if ($PSBoundParameters.ContainsKey('map_untrusted')){ Add-Member -InputObject $obj -type NoteProperty -name map_untrusted -value $map_untrusted }
            Add-Member -InputObject $obj -type NoteProperty -name name -value $name
            if ($PSBoundParameters.ContainsKey('netbios_name')){ Add-Member -InputObject $obj -type NoteProperty -name netbios_name -value $netbios_name }
            if ($PSBoundParameters.ContainsKey('skeleton_directory')){ Add-Member -InputObject $obj -type NoteProperty -name skeleton_directory -value $skeleton_directory }
            if ($PSBoundParameters.ContainsKey('smb_shares')){ Add-Member -InputObject $obj -type NoteProperty -name smb_shares -value $smb_shares }
            if ($PSBoundParameters.ContainsKey('system_provider')){ Add-Member -InputObject $obj -type NoteProperty -name system_provider -value $system_provider }
            if ($PSBoundParameters.ContainsKey('user_mapping_rules')){ Add-Member -InputObject $obj -type NoteProperty -name user_mapping_rules -value $user_mapping_rules }

            if ($Force -or $PSCmdlet.ShouldProcess("$name","New-isiZones")){
                $ISIObject = Send-isiAPI -Cluster $Cluster -Method POST -Resource "/platform/1/zones" -body (convertto-json -depth 40 $obj)
            }
    }
    End{

    }
	
}

function Remove-isiZones{
<#
.SYNOPSIS
    Remove Isilon Zone
    
.DESCRIPTION
    Removes Isilon Zone

.EXAMPLE
    Remove-isiZones -name zone1

.EXAMPLE
    'zone1' | Remove-isiZones


.NOTES

#>

	[CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='High')]
	
	param (
            [Parameter(Mandatory=$True,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,Position=0)][string[]]$name,
            [switch]$Force,
            [string]$Cluster=$isi_sessiondefault)

    Begin{ 

    }
    Process{      
        #execute
        if ($Force -or $PSCmdlet.ShouldProcess("$name","Remove-isiZones")){
            $ISIObject = Send-isiAPI -Cluster $Cluster -Method DELETE -Resource "/platform/1/zones/$name"
        }
    }

    End{

    }
	
}

Export-ModuleMember -Function Get-isiZones
Export-ModuleMember -Function Get-isiZonesSummary
Export-ModuleMember -Function New-isiZones
Export-ModuleMember -Function Set-isiZones
Export-ModuleMember -Function Remove-isiZones

function Get-isiQuotasSummary{
<#
.SYNOPSIS
    Get Isilon Quotas Summary
    
.DESCRIPTION
    Returns Isilon Quotas Summar

.EXAMPLE
    Get-isiQuotasSummary

.NOTES

#>

	[CmdletBinding()]
	
	param ([string]$Cluster=$isi_sessiondefault)

    Begin{
        
    }
    Process{
    
            Send-isiAPI -Cluster $Cluster -Method GET_JSON -Resource "/platform/1/quota/quotas?describe"
                
    }

    End{

    }
	
}

function Get-isiQuotas{

<#
.SYNOPSIS
    Get Isilon Quotas
    
.DESCRIPTION
    Returns Isilon Quotas

.EXAMPLE
    Get-isiQuotas

.EXAMPLE
    Get-isiQuotas -id AAAlAAEAAAAAAAAAAAAAwAEAAAAAAAAA 


.NOTES
    

#>

	[CmdletBinding()]
	
	param (
            [Parameter(Mandatory=$False,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,Position=0)][string[]]$id,
            [string]$Cluster=$isi_sessiondefault)

    Begin{

    }
    Process{
        # Check if id parameter passed
        if($id){
            #execute
            $ISIObject = Send-isiAPI -Cluster $Cluster -Method GET -Resource "/platform/1/quota/quotas/$id"
            $ISIObject.quotas

        } else{
            $ISIObject = Send-isiAPI -Cluster $Cluster -Method GET -Resource "/platform/1/quota/quotas"
            $ISIObject.quotas
        }
    }
    End{

    }
	
}

function Set-isiQuotas {
<#
.SYNOPSIS
    Set Isilon Quota
    
.DESCRIPTION
    Set Isilon Quota

.EXAMPLE
    Set-isiZones -id AAAlAAEAAAAAAAAAAAAAwAEAAAAAAAAA -thresholds_include_overhead $false

.NOTES

#>

	
    [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='High')]
	
	param (            
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$container,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$enforced,
            [Parameter(Mandatory=$True,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][string]$id,
            #[Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$force,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$include_snapshots,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][string]$path,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)]$persona,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)]$thresholds,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$thresholds_include_overhead,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][ValidateSet('directory', 'user', 'group', 'default-user', 'default-group')][string]$type,
            [switch]$Force,
            [string]$Cluster=$isi_sessiondefault)

    Begin{
    }
    Process{

            #create object
            $obj = [pscustomobject]@{}
            if ($PSBoundParameters.ContainsKey('container')){ Add-Member -InputObject $obj -type NoteProperty -name container -value $container }
            if ($PSBoundParameters.ContainsKey('enforced')){ Add-Member -InputObject $obj -type NoteProperty -name enforced -value $enforced }
            if ($PSBoundParameters.ContainsKey('include_snapshots')){ Add-Member -InputObject $obj -type NoteProperty -name include_snapshots -value $include_snapshots }
            if ($PSBoundParameters.ContainsKey('path')){ Add-Member -InputObject $obj -type NoteProperty -name path -value $path }
            if ($PSBoundParameters.ContainsKey('persona')){ Add-Member -InputObject $obj -type NoteProperty -name persona -value $persona }
            if ($PSBoundParameters.ContainsKey('thresholds')){ Add-Member -InputObject $obj -type NoteProperty -name thresholds -value $thresholds }
            if ($PSBoundParameters.ContainsKey('thresholds_include_overhead')){ Add-Member -InputObject $obj -type NoteProperty -name thresholds_include_overhead -value $thresholds_include_overhead }
            if ($PSBoundParameters.ContainsKey('type')){ Add-Member -InputObject $obj -type NoteProperty -name type -value $type }

            if ($Force -or $PSCmdlet.ShouldProcess("$id","Set-isiZones")){
                $ISIObject = Send-isiAPI -Cluster $Cluster -Method PUT -Resource "/platform/1/quota/quotas/$id" -body (convertto-json -depth 40 $obj)
                $ISIObject.id
            }
    }
    End{

    }
	
}

function New-isiQuotas{
<#
.SYNOPSIS
    New Isilon Quota
    
.DESCRIPTION
    Create Isilon Quota

.EXAMPLE
    New-isiQuotas -enforced $false -include_snapshots $true -thresholds_include_overhead $true -type directory -path '/ifs/data/zone2'

.NOTES

#>
            [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='High')]
	
	param (            
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$container,
            [Parameter(Mandatory=$True,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$enforced,
            [Parameter(Mandatory=$True,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$include_snapshots,
            [Parameter(Mandatory=$True,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][string]$path,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)]$persona,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)]$thresholds,
            [Parameter(Mandatory=$True,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$thresholds_include_overhead,
            [Parameter(Mandatory=$True,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][ValidateSet('directory', 'user', 'group', 'default-user', 'default-group')][string]$type,
            [switch]$Force,
            [string]$Cluster=$isi_sessiondefault)

    Begin{
    }
    Process{

            #create object
            $obj = [pscustomobject]@{}
            if ($PSBoundParameters.ContainsKey('container')){ Add-Member -InputObject $obj -type NoteProperty -name container -value $container }
            Add-Member -InputObject $obj -type NoteProperty -name enforced -value $enforced
            Add-Member -InputObject $obj -type NoteProperty -name include_snapshots -value $include_snapshots
            Add-Member -InputObject $obj -type NoteProperty -name path -value $path
            if ($PSBoundParameters.ContainsKey('persona')){ Add-Member -InputObject $obj -type NoteProperty -name persona -value $persona }
            if ($PSBoundParameters.ContainsKey('thresholds')){ Add-Member -InputObject $obj -type NoteProperty -name thresholds -value $thresholds }
            Add-Member -InputObject $obj -type NoteProperty -name thresholds_include_overhead -value $thresholds_include_overhead
            Add-Member -InputObject $obj -type NoteProperty -name type -value $type

            if ($Force -or $PSCmdlet.ShouldProcess("$name","New-isiZones")){
                $ISIObject = Send-isiAPI -Cluster $Cluster -Method POST -Resource "/platform/1/quota/quotas" -body (convertto-json -depth 40 $obj)
                $ISIObject.id
            }
    }
    End{

    }
	
}

function Remove-isiQuotas{
<#
.SYNOPSIS
    Remove Isilon Quota
    
.DESCRIPTION
    Removes Isilon Quota


.EXAMPLE
    Remove-isiQuotas -id DAAhAAEAAAAAAAAAAAAAwAIAAAAAAAAA

.EXAMPLE
    Get-isiQuotas | Where-Object{ $_.path -eq '/ifs/data/zone1'} | Remove-isiSMBShares


.NOTES

#>

	[CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='High')]
	
	param (
            [Parameter(Mandatory=$True,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,Position=0)][string[]]$id,
            [switch]$Force,
            [string]$Cluster=$isi_sessiondefault)

    Begin{ 

    }
    Process{      
        #execute
        if ($Force -or $PSCmdlet.ShouldProcess("$name","Remove-isiZones")){
            $ISIObject = Send-isiAPI -Cluster $Cluster -Method DELETE -Resource "/platform/1/quota/quotas/$id"
        }
    }

    End{

    }
	
}

Export-ModuleMember -Function Get-isiQuotas
Export-ModuleMember -Function Get-isiQuotasSummary
Export-ModuleMember -Function New-isiQuotas
Export-ModuleMember -Function Set-isiQuotas
Export-ModuleMember -Function Remove-isiQuotas


function Get-isiSyncJobsSummary{
<#
.SYNOPSIS
    Get Isilon SyncIQ Jobs Summary
    
.DESCRIPTION
    Returns Isilon SyncIQ Jobs Summary


 
.EXAMPLE
    Get-isiSyncJobsSummary

.EXAMPLE
    Get-isiSyncJobsSummary -Cluster Isilon1

.NOTES

#>

	[CmdletBinding()]
	
	param ([string]$Cluster=$isi_sessiondefault)

    Begin{
        
    }
    Process{
    
            Send-isiAPI -Cluster $Cluster -Method GET_JSON -Resource "/platform/1/sync/jobs?describe"
                
    }

    End{

    }
	
}

function Get-isiSyncJobs{

<#
.SYNOPSIS
    Get Isilon SyncIQ Jobs
    
.DESCRIPTION
    Returns Isilon SyncIQ Jobs

.EXAMPLE
    Get-isiSyncJobs

.EXAMPLE
    Get-isiSyncJobs -name sync1

.NOTES

#>

	[CmdletBinding()]
	
	param (
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true,ValueFromPipeline=$true,Position=0)][string[]]$name,
            [string]$Cluster=$isi_sessiondefault)

    Begin{
        
    }
    Process{
    
        # Check if id parameter passed
        if($name){
            $ISIObject = Send-isiAPI -Cluster $Cluster -Method GET -Resource "/platform/1/sync/jobs/$name"
            $ISIObject.jobs

        } else{
            $ISIObject =Send-isiAPI -Cluster $Cluster -Method GET -Resource "/platform/1/sync/jobs"
            $ISIObject.jobs
        }

    }
    End{

    }
	
}

function Get-isiSyncPoliciesSummary{
<#
.SYNOPSIS
    Get Isilon SyncIQ Summary
    
.DESCRIPTION
    Returns Isilon SyncIQ Summary

.EXAMPLE
    Get-isiSyncPoliciesSummary

.EXAMPLE
    Get-isiSyncPoliciesSummary -Cluster Isilon1

.NOTES

#>

	[CmdletBinding()]
	
	param ([string]$Cluster=$isi_sessiondefault)

    Begin{
        
    }
    Process{
    
            Send-isiAPI -Cluster $Cluster -Method GET_JSON -Resource "/platform/1/sync/policies?describe"
                
    }

    End{

    }
	
}

function Get-isiSyncPolicies{

<#
.SYNOPSIS
    Get Isilon SyncIQ Policies
    
.DESCRIPTION
    Returns Isilon SyncIQ Policies

.EXAMPLE
    Get-isiSyncPolicies

.EXAMPLE
    Get-isiSyncPolicies -name syn1

.NOTES

#>

	[CmdletBinding()]
	
	param (
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true,ValueFromPipeline=$true,Position=0)][string[]]$name,
            [string]$Cluster=$isi_sessiondefault)

    Begin{
        
    }
    Process{
    
        # Check if id parameter passed
        if($name){
            $ISIObject = Send-isiAPI -Cluster $Cluster -Method GET -Resource "/platform/1/sync/policies/$name"
            $ISIObject.policies

        } else{
            $ISIObject =Send-isiAPI -Cluster $Cluster -Method GET -Resource "/platform/1/sync/policies"
            $ISIObject.policies
        }

    }
    End{

    }
	
}

function Set-isiSyncPolicies {
<#
.SYNOPSIS
    Set Isilon SyncIQ Policies
    
.DESCRIPTION
    Set Isilon SyncIQ Policies

.EXAMPLE
    Set-isiSyncPolicies -name sync1 -description 'sync for home shares'

.NOTES

#>

	
    [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='High')]
	
	param (            
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][ValidateSet('copy', 'sync')][string]$action,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$burst_mode,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$check_integrity,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][string]$description,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$enabled,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][ValidateSet('fatal', 'error', 'notice', 'info', 'copy', 'debug', 'trace')][string]$log_level,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$log_removed_files,
            [Parameter(Mandatory=$True,ValueFromPipelineByPropertyName=$true,Position=0)][ValidateNotNullOrEmpty()][string]$name,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][string]$new_name,            
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][string]$password,  
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][int]$report_max_age,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][int]$report_max_count,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$restrict_target_network,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][string]$schedule,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][array]$source_exclude_directories,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][array]$source_include_directories,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][string]$source_network,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][string]$source_root_path,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$source_snapshot_archive,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][int]$source_snapshot_expiration,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][string]$source_snapshot_pattern,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$target_compare_initial_sync,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$target_detect_modifications,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][string]$target_host,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][string]$target_path,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][string]$target_snapshot_alias,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][bool]$target_snapshot_archive,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][int]$target_snapshot_expiration,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][string]$target_snapshot_pattern,
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][int]$workers_per_node,
            [switch]$Force,
            [string]$Cluster=$isi_sessiondefault)

    Begin{
    }
    Process{

            #create object
            $obj = [pscustomobject]@{}
            if ($PSBoundParameters.ContainsKey('action')){ Add-Member -InputObject $obj -type NoteProperty -name action -value $action }
            if ($PSBoundParameters.ContainsKey('burst_mode')){ Add-Member -InputObject $obj -type NoteProperty -name burst_mode -value $burst_mode }
            if ($PSBoundParameters.ContainsKey('check_integrity')){ Add-Member -InputObject $obj -type NoteProperty -name check_integrity -value $check_integrity }
            if ($PSBoundParameters.ContainsKey('description')){ Add-Member -InputObject $obj -type NoteProperty -name description -value $description }
            if ($PSBoundParameters.ContainsKey('enabled')){ Add-Member -InputObject $obj -type NoteProperty -name enabled -value $enabled }
            if ($PSBoundParameters.ContainsKey('log_level')){ Add-Member -InputObject $obj -type NoteProperty -name log_level -value $log_level }
            if ($PSBoundParameters.ContainsKey('log_removed_files')){ Add-Member -InputObject $obj -type NoteProperty -name log_removed_files -value $log_removed_files }
            if ($PSBoundParameters.ContainsKey('new_name')){Add-Member -InputObject $obj -type NoteProperty -name name -value $new_name}
            if ($PSBoundParameters.ContainsKey('password')){ Add-Member -InputObject $obj -type NoteProperty -name password -value $password }
            if ($PSBoundParameters.ContainsKey('report_max_age')){ Add-Member -InputObject $obj -type NoteProperty -name report_max_age -value $report_max_age }
            if ($PSBoundParameters.ContainsKey('report_max_count')){Add-Member -InputObject $obj -type NoteProperty -name report_max_count -value $report_max_count}
            if ($PSBoundParameters.ContainsKey('restrict_target_network')){ Add-Member -InputObject $obj -type NoteProperty -name restrict_target_network -value $restrict_target_network }
            if ($PSBoundParameters.ContainsKey('schedule')){ Add-Member -InputObject $obj -type NoteProperty -name schedule -value $schedule }
            if ($PSBoundParameters.ContainsKey('source_exclude_directories')){ Add-Member -InputObject $obj -type NoteProperty -name source_exclude_directories -value $source_exclude_directories }
            if ($PSBoundParameters.ContainsKey('source_include_directories')){ Add-Member -InputObject $obj -type NoteProperty -name source_include_directories -value $source_include_directories }
            if ($PSBoundParameters.ContainsKey('source_root_path')){ Add-Member -InputObject $obj -type NoteProperty -name source_root_path -value $source_root_path }
            if ($PSBoundParameters.ContainsKey('source_snapshot_archive')){ Add-Member -InputObject $obj -type NoteProperty -name source_snapshot_archive -value $source_snapshot_archive }
            if ($PSBoundParameters.ContainsKey('source_snapshot_expiration')){ Add-Member -InputObject $obj -type NoteProperty -name source_snapshot_expiration -value $source_snapshot_expiration }
            if ($PSBoundParameters.ContainsKey('target_compare_initial_sync')){ Add-Member -InputObject $obj -type NoteProperty -name target_compare_initial_sync -value $target_compare_initial_sync }
            if ($PSBoundParameters.ContainsKey('target_detect_modifications')){ Add-Member -InputObject $obj -type NoteProperty -name target_detect_modifications -value $target_detect_modifications }
            if ($PSBoundParameters.ContainsKey('target_host')){ Add-Member -InputObject $obj -type NoteProperty -name target_host -value $target_host }
            if ($PSBoundParameters.ContainsKey('target_path')){ Add-Member -InputObject $obj -type NoteProperty -name target_path -value $target_path }
            if ($PSBoundParameters.ContainsKey('target_snapshot_alias')){ Add-Member -InputObject $obj -type NoteProperty -name target_snapshot_alias -value $target_snapshot_alias }
            if ($PSBoundParameters.ContainsKey('target_snapshot_archive')){ Add-Member -InputObject $obj -type NoteProperty -name target_snapshot_archive -value $target_snapshot_archive }
            if ($PSBoundParameters.ContainsKey('target_snapshot_expiration')){ Add-Member -InputObject $obj -type NoteProperty -name target_snapshot_expiration -value $target_snapshot_expiration }
            if ($PSBoundParameters.ContainsKey('target_snapshot_pattern')){ Add-Member -InputObject $obj -type NoteProperty -name target_snapshot_pattern -value $target_snapshot_pattern }
            if ($PSBoundParameters.ContainsKey('workers_per_node')){ Add-Member -InputObject $obj -type NoteProperty -name workers_per_node -value $workers_per_node }


            if ($Force -or $PSCmdlet.ShouldProcess("$name","Set-isiSyncPolicies")){
                $ISIObject = Send-isiAPI -Cluster $Cluster -Method PUT -Resource "/platform/1/sync/policies/$name" -body (convertto-json -depth 40 $obj)
            }
    }
    End{

    }
	
}

function Remove-isiSyncPolicies{
<#
.SYNOPSIS
    Remove Isilon SyncIQ Policy
    
.DESCRIPTION
    Removes Isilon SyncIQ Policy

.EXAMPLE
    Remove-isiSyncPolicies -name sync1

.EXAMPLE
    'sync1','sync2' | Remove-isiSyncPolicies


.NOTES

#>

	[CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='High')]
	
	param (
            [Parameter(Mandatory=$True,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,Position=0)][string[]]$name,
            [switch]$Force,
            [string]$Cluster=$isi_sessiondefault)

    Begin{ 

    }
    Process{      
        #execute
        if ($Force -or $PSCmdlet.ShouldProcess("$name","Remove-isiSyncPolicies")){
            $ISIObject = Send-isiAPI -Cluster $Cluster -Method DELETE -Resource "/platform/1/sync/policies/$name"
        }
    }

    End{

    }
}

function Start-isiSyncJobs {
<#
.SYNOPSIS
    Start Isilon SyncIQ Job
    
.DESCRIPTION
    Start Isilon SyncIQ Job

.EXAMPLE
    Start-isiSyncJobs -policy sync1


.NOTES

#>

	
    [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact='High')]
	
	param (            
            [Parameter(Mandatory=$True,ValueFromPipelineByPropertyName=$true)][ValidateNotNullOrEmpty()][string]$policy,
            [switch]$Force,
            [string]$Cluster=$isi_sessiondefault)

    Begin{
    }
    Process{

            #create object
            $obj = [pscustomobject]@{}
            Add-Member -InputObject $obj -type NoteProperty -name id -value $policy


            if ($Force -or $PSCmdlet.ShouldProcess("$id","Start-isiSyncJobs")){
                $ISIObject = Send-isiAPI -Cluster $Cluster -Method POST -Resource "/platform/1/sync/jobs" -body (convertto-json -depth 40 $obj)
            }
    }
    End{

    }
	
}

function Get-isiSyncTargetPoliciesSummary{
<#
.SYNOPSIS
    Get Isilon SyncIQ Target Policies Summary
    
.DESCRIPTION
    Returns Isilon SyncIQ Target Policies Summary

.EXAMPLE
    Get-isiSyncTargetPoliciesSummary

.EXAMPLE
    Get-isiSyncTargetPoliciesSummary -Cluster Isilon1

.EXAMPLE
    ('Isilon1','Isilon2') | Get-isiSyncTargetPoliciesSummary


.NOTES

#>

	[CmdletBinding()]
	
	param ([string]$Cluster=$isi_sessiondefault)

    Begin{
        
    }
    Process{
    
            Send-isiAPI -Cluster $Cluster -Method GET_JSON -Resource "/platform/1/sync/target/policies?describe"
                
    }

    End{

    }
	
}

function Get-isiSyncTargetPolicies{

<#
.SYNOPSIS
    Get Isilon SyncIQ Target Policies 
    
.DESCRIPTION
    Returns Isilon SyncIQ Target Policies 

.EXAMPLE
    Get-isiSyncTargetPolicies

.EXAMPLE
    Get-isiSyncTargetPolicies -name sync1


.NOTES

#>

	[CmdletBinding()]
	
	param (
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true,ValueFromPipeline=$true,Position=0)][string[]]$name,
            [string]$Cluster=$isi_sessiondefault)

    Begin{
        
    }
    Process{
    
        # Check if id parameter passed
        if($name){
            $ISIObject = Send-isiAPI -Cluster $Cluster -Method GET -Resource "/platform/1/sync/target/policies/$name"
            $ISIObject.policies

        } else{
            $ISIObject =Send-isiAPI -Cluster $Cluster -Method GET -Resource "/platform/1/sync/target/policies"
            $ISIObject.policies
        }

    }
    End{

    }
	
}

function Get-isiSyncReportsSummary{
<#
.SYNOPSIS
    Get Isilon SyncIQ Reports Summary
    
.DESCRIPTION
    Returns Isilon SyncIQ Reports Summary

.EXAMPLE
    Get-isiSyncReportsSummary

.EXAMPLE
    Get-isiSyncReportsSummary -Cluster Isilon1

.EXAMPLE
    ('Isilon1','Isilon2') | Get-isiSyncReportsSummary


.NOTES

#>

	[CmdletBinding()]
	
	param ([string]$Cluster=$isi_sessiondefault)

    Begin{
        
    }
    Process{
    
            Send-isiAPI -Cluster $Cluster -Method GET_JSON -Resource "/platform/1/sync/reports?describe"
                
    }

    End{

    }
	
}

function Get-isiSyncReports{

<#
.SYNOPSIS
    Get Isilon SyncIQ Reports
    
.DESCRIPTION
    Returns Isilon SyncIQ Reports

.EXAMPLE
    Get-isiSyncReports

.EXAMPLE
    Get-isiSyncReports -id 993-sync1

.NOTES

#>

	[CmdletBinding()]
	
	param (
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true,ValueFromPipeline=$true,Position=0)][string[]]$id,
            [string]$Cluster=$isi_sessiondefault)

    Begin{
        
    }
    Process{
    
        # Check if id parameter passed
        if($id){
            $ISIObject = Send-isiAPI -Cluster $Cluster -Method GET -Resource "/platform/1/sync/reports/$id"
            $ISIObject.reports

        } else{
            $ISIObject =Send-isiAPI -Cluster $Cluster -Method GET -Resource "/platform/1/sync/reports"
            $ISIObject.reports
        }

    }
    End{

    }
	
}


Export-ModuleMember -Function Get-isiSyncJobsSummary
Export-ModuleMember -Function Get-isiSyncJobs
Export-ModuleMember -Function Get-isiSyncPoliciesSummary
Export-ModuleMember -Function Get-isiSyncPolicies
Export-ModuleMember -Function Set-isiSyncPolicies
Export-ModuleMember -Function Start-isiSyncJobs
Export-ModuleMember -Function Remove-isiSyncPolicies
Export-ModuleMember -Function Get-isiSyncTargetPoliciesSummary
Export-ModuleMember -Function Get-isiSyncTargetPolicies
Export-ModuleMember -Function Get-isiSyncReportsSummary
Export-ModuleMember -Function Get-isiSyncReports

function Get-isiNFSExports{
<#
.SYNOPSIS
    Get Isilon SMB Shares
    
.DESCRIPTION
    Returns Isilon SMB Shares

.EXAMPLE
    Get-ISISMBShares

.EXAMPLE
    Get-ISISMBShares -Cluster Isilon1

.EXAMPLE
    Get-ISISMBShares -name ifs

.EXAMPLE
    'ifs','share1' | Get-ISISMBShares


.NOTES

#>

	[CmdletBinding()]
	
	param (
            [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$true,ValueFromPipeline=$true,Position=0)][int[]]$id,
            [string]$Cluster=$isi_sessiondefault)

    Begin{
        
    }
    Process{
    
        # Check if id parameter passed
        if($name){
            $ISIObject = Send-isiAPI -Cluster $Cluster -Method GET -Resource "/platform/1/protocols/nfs/exports/$id"
            $ISIObject.exports

        } else{
            $ISIObject =Send-isiAPI -Cluster $Cluster -Method GET -Resource "/platform/1/protocols/nfs/exports"
            $ISIObject.exports
        }

    }
    End{

    }
	
}

Export-ModuleMember -Function Get-isiNFSExports