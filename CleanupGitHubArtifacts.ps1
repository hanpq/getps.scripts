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
    "GUID": "07c328ba-6eb4-4234-96e3-e3796ea01ad9",
    "FILENAME": "CleanupGitHubArtifacts.ps1",
    "AUTHOR": "Hannes Palmquist",
    "AUTHOREMAIL": "hannes.palmquist@outlook.com",
    "CREATEDDATE": "2022-11-27",
    "COMPANYNAME": "GetPS.dev",
    "COPYRIGHT": "© 2022, Hannes Palmquist, All Rights Reserved"
}
PSScriptInfo#>

<#
    .SYNOPSIS
        Cleanup artifacts from GitHub repo
    .DESCRIPTION
        This script will remove all artifacts for a single repos or all repos for a given user
    .PARAMETER GitHubSecret
        Defines the GitHubSecret (API Key) to use
    .PARAMETER GitHubOrg
        Defines the GitHub owner user name
    .PARAMETER Repo
        Optionally specify a repo to only remove artifacts for that specific repo
    .PARAMETER PageSize
        Optionally specify the PageSize when retreiving repos and artifacts. Valid values are in range of 1..100. Default is 30.
    .LINK
        Specify a URI to a help page, this will show when Get-Help -Online is used.
    .EXAMPLE
        .\CleanupGitHubArtifacts.ps1 -GitHubSecret "ABC" -GitHubOrg "user"

        Running the script without specifying a repo will cleanup all artifacts for all repos
    .EXAMPLE
        .\CleanupGitHubArtifacts.ps1 -GitHubSecret "ABC" -GitHubOrg "user" -Repo "RepoName"

        Running the script with a specified repo will cleanup all artifacts for that repo
#>
param(
    [parameter(Mandatory)]
    [string]
    $GitHubSecret,

    [parameter(Mandatory)]
    [string]
    $GitHubOrg,

    [parameter()]
    [string]
    $Repo,

    [parameter()]
    [ValidateRange(1, 100)]
    [int]
    $PageSize = 30
)

$PSDefaultParameterValues = @{
    'Invoke-RestMethod:Headers' = @{Accept = 'application/vnd.github+json'; Authorization = "Bearer $GitHubSecret" }
}

# Find repos
if ($Repo)
{
    $Repos = Invoke-RestMethod -Method get -Uri "https://api.github.com/repos/$GitHubOrg/$Repo"
}
else
{
    $Repos = [System.Collections.Generic.List[Object]]::New()
    $PageID = 1
    do
    {
        $Result = Invoke-RestMethod -Method get -Uri "https://api.github.com/user/repos?per_page=$PageSize&page=$PageID"
        if ($Result)
        {
            $Repos.AddRange([array]$Result)
        }
        $PageID++
    } until ($Result.Count -lt $PageSize)
}

foreach ($Repo in $Repos)
{

    # Define result object
    $ObjectHash = [ordered]@{
        Repo              = $Repo.Name
        Artifacts_Found   = 0
        Artifacts_Removed = 0
        Artifacts_SizeMB  = 0
        Artifacts         = [System.Collections.Generic.List[Object]]::New()
    }

    # Find artifacts
    $Artifacts = [System.Collections.Generic.List[Object]]::New()
    $PageID = 1
    do
    {
        $Result = Invoke-RestMethod -Method get -Uri "https://api.github.com/repos/$GitHubOrg/$($Repo.Name)/actions/artifacts?per_page=$PageSize&page=$PageID" | Select-Object -ExpandProperty artifacts
        if ($Result)
        {
            $Artifacts.AddRange([array]$Result)
        }
        $PageID++
    } until ($Result.Count -lt $PageSize)

    # Remove artifacts
    if ($artifacts)
    {
        $ObjectHash.Artifacts_Found = $Artifacts.Count
        $ObjectHash.Artifacts_SizeMB = (($Artifacts | Measure-Object -Sum -Property size_in_bytes).Sum / 1MB)
        foreach ($artifact in $artifacts)
        {
            $Result = Invoke-RestMethod -Method DELETE -Uri "https://api.github.com/repos/$GitHubOrg/$($Repo.Name)/actions/artifacts/$($artifact.id)"
            $ObjectHash.Artifact_Removed++
        }
    }

    # Return resultobject
    [pscustomobject]$ObjectHash
}
