#
#   Report Time Zone Details
#
# Modified: 18-Feb-2022
# By:       E Middleton


# Print info from a .NET DateTime in a standard form
[bool]$ConsistentOffset = $true
Function ShowDateInfo
{ 
 Param([string]$label, [DateTime]$date, [int]$std, [bool]$ConsistentOffset) 

 $local = $date.ToLocalTime()
 $utc = $date.ToUniversalTime()
 [int]$offset = $local.Subtract( $utc ).TotalMinutes
 
 Write-Host -NoNewline $label "`t "
 Write-Host -NoNewline -ForegroundColor Cyan $local.ToString("yyyy-MM-dd HH:mm") 
 Write-Host -NoNewline -ForegroundColor Yellow $utc.ToString("`t`tyyyy-MM-dd HH:mm")
 if ($offset -eq $std) 
 {
     Write-Host  -ForegroundColor Green "`t`t" $offset
 } else {
     Write-Host  -ForegroundColor Magenta "`t`t" $offset
     $ConsistentOffset = $false
 }
 return $ConsistentOffset
} #end DateInfo


# Read current time zone information from the system
$SystemIsUTC = ( (Get-ItemProperty -Path Registry::HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation).RealTimeIsUniversal -eq 1)         # System Clock setting (default is "false")
$Adjust4DST = ( (Get-ItemProperty -Path Registry::HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation).DynamicDaylightTimeDisabled -eq 0)  # Current setting of "Automatically adjust for DST"
$DSTStart = ([TimeZone]::CurrentTimeZone.GetDaylightChanges( [DateTime]::Now.Year ).Start)                                                       # Setting at the time the .NET framework initialized
$StdOffset = [TimeZoneInfo]::Local.BaseUtcOffset.TotalMinutes
$DSTObserved = ([TimeZoneInfo]::Local.SupportsDaylightSavingTime)

Write-Host ""
Write-Host "Current Time Zone`t`t" ([TimeZone]::CurrentTimeZone.StandardName)
Write-Host "Standard time offset`t" $StdOffset
Write-Host "Time Zone Observes DST`t" $DSTObserved
Write-Host "Current Adjust DST`t`t" $Adjust4DST
Write-Host "Startup Adjust DST`t`t" ($DSTStart.Year -ne 1)
Write-Host "DST Begins`t`t`t`t" ($DSTStart.ToString("yyyy-MM-dd"))
Write-Host "System Clock Is UTC`t`t" ($SystemIsUTC)

Write-Host  -NoNewLine -ForegroundColor Cyan "`n`t`t`t`t`t`t Local Time"
Write-Host  -NoNewLine -ForegroundColor Yellow "`t`t`t`tUTC"
Write-Host  -ForegroundColor Green "`t`t`t`t`t`t Offset"

# .NET 'DateTime' has a 'kind' (UTC or Local or Unspecified) which leads to ambiguity in the 'Unspecified' case
# The complexity of "SpecifyKind" below eliminates that ambiguity

$RefDate = 43831.5
$ConsistentOffset = ShowDateInfo "A. Current from UTC`t" ([DateTime]::UtcNow) $StdOffset $ConsistentOffset
$ConsistentOffset = ShowDateInfo "B. Current from Local" ([DateTime]::Now) $StdOffset $ConsistentOffset
$ConsistentOffset = ShowDateInfo "C. Start from UTC`t" ([DateTime]::SpecifyKind([DateTime]::FromOADate( $RefDate ),[DateTimeKind]::Utc)) $StdOffset $ConsistentOffset
$ConsistentOffset = ShowDateInfo "D. Start from Local" ([DateTime]::SpecifyKind([DateTime]::FromOADate($RefDate + $StdOffset/1440.0),[DateTimeKind]::Local)) $StdOffset $ConsistentOffset
$ConsistentOffset = ShowDateInfo "E. Midyear from UTC`t" ([DateTime]::SpecifyKind([DateTime]::FromOADate($RefDate + 182),[DateTimeKind]::Utc)) $StdOffset $ConsistentOffset
$ConsistentOffset = ShowDateInfo "F. Midyear from Local" ([DateTime]::SpecifyKind([DateTime]::FromOADate($RefDate + 182 + $StdOffset/1440.0),[DateTimeKind]::Local)) $StdOffset $ConsistentOffset

Write-Host ""
if ($ConsistentOffset -and $DSTObserved) 
 {
     Write-Host  -ForegroundColor Red "Inconsistent time zone and UTC conversions"
 } else {
     Write-Host "Time zone and UTC conversions are consistent"
 }
