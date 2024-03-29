﻿param (
    $iTunesBackupDirectory,
    $ExportDirectory
)

try
{
    Import-Module PSSQLite -ErrorAction Stop
}
catch
{
    throw 'Failed to import PSSQLite powershell module. Make sure it is installed and can be imported. (Install-module PSSQLite -scope currentuser)'
}

function Get-StringHash
{
    <#
        .DESCRIPTION
            Generates a hash of an string object
        .PARAMETER Strings
            Defines the array of strings to generate hashes of
        .PARAMETER Algorithm
            Defines which hashing algorithm to use, valid values are MD5, SHA256, SHA384 and SHA512. Defaults to SHA512
        .PARAMETER Salt
            Defines a specific salt to use, this is useful when recalculating a string hash with a known salt for comparison. A new random salt
            is generated by default for every string that is processed.
        .PARAMETER Iterations
            Defines the number of rehashing operations that is performed.
        .PARAMETER RandomSalt
            Defines that a random salt should be used
        .EXAMPLE
            Get-StringHash -Strings 'ThisIsAComplicatedPassword123#' -Algorithm SHA512
            Hashes the string specified
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'False positive')]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)][String[]]$Strings,
        [ValidateSet('MD5', 'SHA256', 'SHA384', 'SHA512', 'SHA1')][string]$Algorithm = 'SHA256',
        [string]$Salt = '',
        [switch]$RandomSalt,
        [int]$Iterations = 10
    )
    BEGIN
    {
        if ($Iterations -eq 0)
        {
            $Iterations = 1
        }
    }
    PROCESS
    {
        $Strings | ForEach-Object {
            # if no salt is specified, generate a new salt to use.
            if ($RandomSalt)
            {
                $Salt = [guid]::NewGuid().Guid
            }
            $String = $_
            $StringBytes = [Text.Encoding]::UTF8.GetBytes($String)
            if ($Salt -ne '')
            {
                $SaltBytes = [Text.Encoding]::UTF8.GetBytes($salt)
            }
            $Hasher = [Security.Cryptography.HashAlgorithm]::Create($Algorithm)
            $StringBuilder = New-Object -TypeName System.Text.StringBuilder

            $Measure = Measure-Command -Expression {
                # Compute first hash
                if ($Salt -ne '')
                {
                    $HashBytes = $Hasher.ComputeHash($StringBytes + $SaltBytes)
                }
                else
                {
                    $HashBytes = $Hasher.ComputeHash($StringBytes)
                }

                # Iterate rehashing
                if ($Iterations -ge 2)
                {
                    2..$Iterations | ForEach-Object {
                        if ($Salt -ne '')
                        {
                            $HashBytes = $Hasher.ComputeHash($HashBytes + $StringBytes + $SaltBytes)
                        }
                        else
                        {
                            $HashBytes = $Hasher.ComputeHash($HashBytes + $StringBytes)
                        }
                    }
                }
            }

            # Convert final hash to a string
            $HashBytes | ForEach-Object {
                $null = $StringBuilder.Append($_.ToString('x2'))
            }

            # Return object
            [pscustomobject]@{
                Hash           = $StringBuilder.ToString()
                OriginalString = $String
                Algorithm      = $algorithm
                Iterations     = $Iterations
                Salt           = $salt
                Compute        = [math]::Round($Measure.TotalMilliseconds)
            }

        }
    }
}

# SQL database has static guid
$PathToDB = "$iTunesBackupDirectory\3d\3d0d7e5fb2ce288813306e4d4636395e047a3d28"

$Connection = New-SQLiteConnection -DataSource $PathToDB

# Collect all messages
$Messages = Invoke-SqliteQuery -Connection $Connection -Query @'
        SELECT
            m.rowid as RowID,
            h.id AS UniqueID,
            CASE is_from_me
                WHEN 0 THEN "received"
                WHEN 1 THEN "sent"
                ELSE "Unknown"
            END as Type,
            CASE
                WHEN date > 0 then TIME(date / 1000000000 + 978307200, 'unixepoch', 'localtime')
                ELSE NULL
            END as Time,
            CASE
                WHEN date > 0 THEN strftime('%Y%m%d', date / 1000000000 + 978307200, 'unixepoch', 'localtime')
                ELSE NULL
            END as Date,
            CASE
                WHEN date > 0 THEN date / 1000000000 + 978307200
                ELSE NULL
            END as Epoch,
            text as Text,
            maj.attachment_id AS AttachmentID
        FROM message m
        LEFT JOIN handle h ON h.rowid = m.handle_id
        LEFT JOIN message_attachment_join maj
        ON maj.message_id = m.rowid
        ORDER BY UniqueID, Date, Time
'@

:message foreach ($Message in $Messages)
{

    # Exclude messages without attachments
    if (-not $Message.AttachmentID)
    {
        continue message
    }

    # Collect attachment info
    $AttachmentRow = Invoke-SqliteQuery -SQLiteConnection $Connection -Query "SELECT * FROM attachment WHERE ROWID = $($Message.AttachmentID)"

    # Adjust the full name name so that the SHA1 hash match the actual name of the file in backup
    $FilePath = $AttachmentRow.FileName -replace '^~/', 'MediaDomain-'

    # Calculate SHA1 hash to locate the file
    $FileNameSHA1 = Get-StringHash -Strings $FilePath -Algorithm SHA1 -Iterations 1 | Select-Object -expand hash

    # Determine relative path to actual file
    $BackupFilePath = "$($FileNameSha1.SubString(0,2))\$($FileNameSha1)"

    # Determine full path to actual file
    $FullBackupFilePath = $iTunesBackupDirectory + '\' + $BackupFilePath

    # Before copying file, make sure we can find it
    if (Test-Path $FullBackupFilePath)
    {
        $DestinationPath = "$ExportDirectory\$($AttachmentRow.transfer_name)"

        # PNG files are stored with a pluginpayloadattachment file extension among other attachments. These needs additional processing.
        if ($AttachmentRow.transfer_name -like '*pluginpayload*')
        {
            # Check if the start of the file contains "PNG", if so, replace the pluginPayloadAttachment extension with PNG
            if ((Get-Content -Path $FullBackupFilePath | Select-Object -First 1) -like '*png*')
            {
                $DestinationPath = $DestinationPath -Replace 'pluginPayloadAttachment', 'PNG'
            }
            # We now do not know what kind of attachment it is, this part can be expanded with further analasys and rules.
            else
            {
                # By process of elemination we can safely ignore some attachment items as non-attachment so that we can log if we actually find something new.

                # We exclude attachments that are generated by iOS as smart link-objects.
                if ($message.text -like '*http*://*')
                {
                    Write-Verbose -Message "$FullBackupFilePath skipped because it is a smart link-object"
                }
                elseif ($AttachmentRow.hide_attachment -eq 1)
                {
                    Write-Verbose -Message "$FullBackupFilePath skipped because it is hidden"
                }
                else
                {
                    Write-Warning "$FullBackupFilePath contains an attachment we have not seen yet. Please inspect manually."
                    Write-Warning ($message | ConvertTo-Json -Compress)
                    Write-Warning ($AttachmentRow | ConvertTo-Json -Compress)
                }
                continue message
            }
        }

        $CopiedItem = Copy-Item -Path $FullBackupFilePath -Destination $DestinationPath -Force -ErrorAction Continue -PassThru
        [pscustomobject]@{
            FullName      = $FullBackupFilePath
            Length        = $CopiedItem.Length
            FileType      = $CopiedItem.Extension.Replace('.', '')
            LastWriteTime = $CopiedItem.LastWriteTime
        }
    }
    else
    {
        Write-Warning "Failed to locate file $FullBackupFilePath, this might be because the attachment has been removed from the messages app manually."
    }
}
