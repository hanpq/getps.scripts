# iMessageExporter

This is a short script that makes the process of extracting photos, videos and files from iMessage a lot easier. Instead of paying for arbritrary services this can be done free.

## How to use

1. Connect your phone to a PC/MAC and create a backup using iTunes. (Make sure that you select when prompted that it should not be an encrypted backup)
2. You can now access the backup on the computer, on windows it is stored under C:\Users\<username>\Apple\MobileSync\Backup.
3. Start the script by providing the path to the backup and a folder where you would like to store all files.

```powershell
.\iMessageExporter -iTunesBackupDirectory 'C:\Users\John\Apple\MobileSync\Backup\12345678-1234567890ABCDEF' -ExportDirectory 'C:\Export'

FullName                                                                                 Length FileType LastWriteTime
--------                                                                                 ------ -------- -------------
C:\Export\12345678-1234567890ABCDEF\f0\f0aa154cfbef55d8a325a985c546999b99e490fc 2219013 JPG      2023-02-05 23:09:44
C:\Export\12345678-1234567890ABCDEF\5f\5f8aeec075e4542ff4811931cdcd4ef275863d8c  950773 HEIC     2023-02-05 23:09:19
C:\Export\12345678-1234567890ABCDEF\be\bee710d1c42b15891e6836f125fc30940afd28c8  972784 HEIC     2023-02-05 23:09:24
C:\Export\12345678-1234567890ABCDEF\bb\bbf5e3937a19fc982756acd4d8ca3ba6c082fb9a 1057496 HEIC     2023-02-05 23:09:41

```

## Dependencies

The script depend on the powershell module PSSQLite. Make sure that this module is installed and can be imported. Use the following command to install the module.

```powershell
Install-Module PSSQLite -Scope CurrentUSer
```

## Credits

This script is based on the work of [basnijholt](https://github.com/basnijholt) who have made a [pearl script](https://github.com/basnijholt/iOSMessageExport) that does a full message export to a HTML page. I was only interested in the files and not very well versed in pearl so based on the logic in his script I converted it to a powershell script. I hope someone finds it useful.
