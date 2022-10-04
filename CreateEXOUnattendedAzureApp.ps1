<#PSLicenseInfo
Copyright © 2022 Hannes Palmquist

Permission is hereby granted, free of charge, to any person obtaining a copy of this
software and associated documentation files (the "Software"), to deal in the Software
without restriction, including without limitation the rights to use, copy, modify,
merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be included in all copies
or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
USE OR OTHER DEALINGS IN THE SOFTWARE.

PSLicenseInfo#>
<#PSScriptInfo
{
    "VERSION": "1.0.0.0",
    "GUID": "7fef8b41-e91d-4cb0-b656-1201c3820eb8",
    "FILENAME": "CreateEXOUnattendedAzureApp.ps1",
    "AUTHOR": "Hannes Palmquist",
    "AUTHOREMAIL": "hannes.palmquist@outlook.com",
    "CREATEDDATE": "2022-10-04",
    "COMPANYNAME": "N/A",
    "COPYRIGHT": "© 2019, Hannes Palmquist, All Rights Reserved"
}
PSScriptInfo#>

param (
    [Parameter(Mandatory)][string]$Organization,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [Parameter()][string]$AppName = 'ExchangeScriptAccess',
    [Parameter][switch]$PassThru
)

$VerbosePreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

Import-Module Microsoft.Graph.Applications, Microsoft.Graph.Authentication, Microsoft.Graph.DeviceManagement.Enrolment -Verbose:$false
$VerbosePreference = 'Continue'

function Get-RandomPassword
{
    param (
        [int]$length = 16
    )
    $Chars = [char[]]([char]33..[char]95) + ([char[]]([char]97..[char]126)) + 0..9
    $Scramble = $Chars | Sort-Object { Get-Random }
    return ($Scramble[0..$length] -join '')
}

$ResultObjectHash = [ordered]@{
    Organization        = $Organization
    OutputDirectory     = $OutputDirectory
    AppName             = $AppName
    Certificate         = $null
    CertificatePassword = Get-RandomPassword
    CertificatePFXPath  = (Join-Path -Path $OutputDirectory -ChildPath "$Organization.pfx")
    CertificateCERPath  = (Join-Path -Path $OutputDirectory -ChildPath "$Organization.cer")
}

$null = Connect-Graph -Scopes 'Application.ReadWrite.All', 'RoleManagement.ReadWrite.Directory'

$ResultObjectHash.Certificate = New-SelfSignedCertificate -DnsName $ResultObjectHash.Organization -CertStoreLocation 'cert:\CurrentUser\My' -NotAfter (Get-Date).AddYears(1) -KeySpec KeyExchange
Write-Verbose "Created self-signed certificate with thumbprint: $($ResultObjectHash.Certificate.Thumbprint)"

$null = $ResultObjectHash.Certificate | Export-PfxCertificate -FilePath $ResultObjectHash.CertificatePFXPath -Password (ConvertTo-SecureString -String $ResultObjectHash.CertificatePassword -AsPlainText -Force)
Write-Verbose "Exported certificate with private key (pfx) to: $($ResultObjectHash.CertificatePFXPath)"

$null = $ResultObjectHash.Certificate | Export-Certificate -FilePath $ResultObjectHash.CertificateCERPath
Write-Verbose "Exported certificate with public key (cer) to: $($ResultObjectHash.CertificateCERPath)"


$Web = [Microsoft.Graph.PowerShell.Models.MicrosoftGraphWebApplication]::New()
$Web.RedirectUris = 'https://localhost'
Write-Verbose 'Initialized MicrosoftGraphWebApplication'

$ResourceAccess = [Microsoft.Graph.PowerShell.Models.MicrosoftGraphResourceAccess]::New()
$ResourceAccess.Id = 'dc50a0fb-09a3-484d-be87-e023b12c6440'
$ResourceAccess.Type = 'Role'
Write-Verbose 'Initialized MicrosoftGraphResourceAccess'

$RequiredResourceAccess = [Microsoft.Graph.PowerShell.Models.MicrosoftGraphRequiredResourceAccess]::New()
$RequiredResourceAccess.ResourceAccess = $ResourceAccess
$RequiredResourceAccess.ResourceAppId = '00000002-0000-0ff1-ce00-000000000000'
Write-Verbose 'Initialized MicrosoftGraphRequiredResourceAccess'

$KeyCred = [Microsoft.Graph.PowerShell.Models.MicrosoftGraphKeyCredential]::New()
$keycred.DisplayName = $ResultObjectHash.Organization
$KeyCred.Key = $ResultObjectHash.Certificate.RawData
$KeyCred.KeyId = $ResultObjectHash.Certificate.SerialNumber
$KeyCred.StartDateTime = $ResultObjectHash.Certificate.NotBefore
$KeyCred.EndDateTime = $ResultObjectHash.Certificate.NotAfter
$KeyCred.Usage = 'Verify'
$KeyCred.Type = 'AsymmetricX509Cert'
Write-Verbose 'Initialized MicrosoftGraphKeyCredential'

$ResultObjectHash.AzureAppRegistration = New-MgApplication  `
    -DisplayName $ResultObjectHash.AppName `
    -Description 'Used by automations that need access to exchange online' `
    -SignInAudience AzureADMyOrg `
    -Web $Web `
    -RequiredResourceAccess $RequiredResourceAccess `
    -KeyCredentials $KeyCred
Write-Verbose "Created Azure App: $($ResultObjectHash.AppName)"

$ResultObjectHash.ServicePrincipal = New-MgServicePrincipal -AppId $ResultObjectHash.AzureAppRegistration.AppId

Write-Verbose 'Waiting 60 seconds for Azure app to be provisioned...'
Start-Sleep -Seconds 60
Start-Process "https://login.microsoftonline.com/$($ResultObjectHash.Organization)/adminconsent?client_id=$($ResultObjectHash.AzureAppRegistration.Appid)"
$null = Read-Host '   Press enter once consent has been given'

$null = New-MgRoleManagementDirectoryRoleAssignment -PrincipalId $ResultObjectHash.ServicePrincipal.id -RoleDefinitionId '29232cdf-9323-42fd-ade2-1d097af3e4de' -DirectoryScopeId /
Write-Verbose 'Added role assignment'

if ($PassThru)
{
    Write-Output ([pscustomobject]$ResultObjectHash)
}
else
{
    Write-Host ''
    Write-Host '   Use the following command to connect Exchange Online:'
    Write-Host ''
    Write-Host -ForegroundColor Cyan "Connect-ExchangeOnline -CertificateThumbprint `"$($ResultObjectHash.Certificate.Thumbprint)`" -AppId `"$($ResultObjectHash.AzureAppRegistration.AppId)`" -Organization `"$($ResultObjectHash.Organization)`""
    Write-Host ''
    Write-Host '   NOTE: Restart powershell before connecting to Exchange Online' -ForegroundColor Yellow
    Write-Host '   NOTE: It could take some time before the added roles are effective. If you get an error regarding missing permissions, please wait a minute and try again.' -ForegroundColor Yellow
    Write-Host ''
}

Remove-Variable ResultObjectHash -ErrorAction SilentlyContinue


