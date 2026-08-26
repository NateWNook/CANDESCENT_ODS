-- A) (re)create the clean file, output visible
EXEC xp_cmdshell 'powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Csv ''\\pd100hubspt01.fcfcu.local\d$\Ancillary_Data_files\Candescent\Candescent-UserData.csv'' -Encoding UTF8 | ConvertTo-Csv -NoTypeInformation -Delimiter ''|'' | ForEach-Object { $_ -replace ([char]34),'''' } | Set-Content ''\\pd100hubspt01.fcfcu.local\d$\Ancillary_Data_files\Candescent\Candescent-clean.psv'' -Encoding UTF8"';

-- B) file size
EXEC xp_cmdshell 'dir "\\pd100hubspt01.fcfcu.local\d$\Ancillary_Data_files\Candescent\Candescent-clean.psv"';

-- C) first 3 lines (should be a header line, then pipe-delimited data)
EXEC xp_cmdshell 'powershell -NoProfile -Command "Get-Content ''\\pd100hubspt01.fcfcu.local\d$\Ancillary_Data_files\Candescent\Candescent-clean.psv'' -TotalCount 3"';

-- D) how many lines does the clean file have?
EXEC xp_cmdshell 'powershell -NoProfile -Command "(Get-Content ''\\pd100hubspt01.fcfcu.local\d$\Ancillary_Data_files\Candescent\Candescent-clean.psv'').Count"';