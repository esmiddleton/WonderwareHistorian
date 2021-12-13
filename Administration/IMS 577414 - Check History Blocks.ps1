#
#    Check AVEVA Historian for Damaged History Blocks
#    ------------------------------------------------
#
#    AVEVA Historian 2020 systems with Hotfix IMS 577414 may not correctly create
#    new history blocks in some edge cases.
#
#    The incomplete blocks will be missing the "blockstatus.dat" file. When this is missing, 
#    for "daily" history blocks an overlapping block with a name ending with "_002" (instead of the usual "_001") 
#    may also be created (or, for "hourly" history blocks, there may be a "_025"). This script will help users quickly 
#    find history blocks with these potential problems.
#
#    Run this script locally on the Historian server.
#
#    Updated: 13-Dec-2021

# Get the current list of storage locations from the local "Runtime" database
Write-Host -ForegroundColor Gray 'Reading storage locations...'
$StorageLocations = New-Object System.Data.DataTable
    
$Connection = New-Object System.Data.SQLClient.SQLConnection
$Connection.ConnectionString = "server='localhost';database='Runtime';trusted_connection=true;connection timeout=2"
$Connection.Open()
$Command = New-Object System.Data.SQLClient.SQLCommand
$Command.Connection = $Connection
$Command.CommandText = "select Path, MaxCount=case TimeUnitId when 1 then 24 / BlockDuration when 2 then 1 end from StorageLocation l join StorageShard s on l.ShardId = s.ShardId where left(Path,3) <> 'rr:' and StorageType < 5"
$Reader = $Command.ExecuteReader()
$StorageLocations.Load($Reader)
$Connection.Close()

$Problems = 0
# Loop through each Storage Location
$StorageLocations | ForEach-Object {

    $Blocks = Get-ChildItem -Path $_.Path  -ErrorAction stop
    $MaxCount = $_.MaxCount
    Write-Host -ForegroundColor Gray 'Checking' ($Blocks.Length) 'blocks from' $_.Path
    $Blocks | ForEach-Object {

        $BlockParts = $_.BaseName -split '_'
        $BlockNumber = [int]$BlockParts[1]

        $StatusFile = $_.FullName + '\blockstatus.dat'
        if ( -Not( Test-Path $StatusFile -PathType Leaf) ) {
            $Problems = $Problems + 1
            Write-Host -ForegroundColor Yellow '  ' $_.FullName 'missing "blockstatus.dat"'

            $NextBlock = $_.Parent.FullName + '\' + $BlockParts[0] + '_' + ([string]($BlockNumber + 1)).PadLeft(3,'0')

            if ( Test-Path $NextBlock ) {
                $Problems = $Problems + 1
                Write-Host -ForegroundColor Yellow '  ' $NextBlock 'possible overlapped block'
            }
        }

        if ( $BlockNumber -gt $MaxCount ) {
            $Problems = $Problems + 1
            Write-Host -ForegroundColor Yellow '  ' $_.FullName 'exceeded expected block count for the day'
        }
    }
}

Write-Host 'Done. Found' $Problems 'potential problems'

