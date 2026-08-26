-- Run THIS proc's pre-clean, output visible:
EXEC xp_cmdshell 'powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Csv ''\\pd100hubspt01.fcfcu.local\d$\Ancillary_Data_files\Candescent\Candescent-UserData.csv'' -Encoding UTF8 | ConvertTo-Csv -NoTypeInformation -Delimiter ''|'' | ForEach-Object { $_ -replace ''"'','''' } | Set-Content ''\\pd100hubspt01.fcfcu.local\d$\Ancillary_Data_files\Candescent\Candescent-clean.psv'' -Encoding UTF8"';

-- Did the clean file get created?
EXEC xp_cmdshell 'dir "\\pd100hubspt01.fcfcu.local\d$\Ancillary_Data_files\Candescent"';