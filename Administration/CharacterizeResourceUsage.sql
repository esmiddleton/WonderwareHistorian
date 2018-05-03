/*

Characterize Historian Resource Usage
=====================================

This query gives a high-level view of the loading of a Historian server over the last 24-hours using System Tags.
The results can be helpful as a first step in assessing the overall load on a system and to identify
resource constraints. 

Revised: 3-May-2018
By: E. Middleton

*/
use Runtime

declare @minutes int
declare @start datetime
declare @end datetime

set @minutes = 60*24 -- Duration to analyze
set @end = getdate()
set @start = dateadd(minute,-@minutes,@end)

select StartDateTime, TagName, Average, Minimum, Maximum, StdDev, PercentGood
from AnalogSummaryHistory
where TagName in (
'SysPerfAvailableMBytes',
'SysPerfCPUTotal',
'SysPerfCPUMax',
'SysPerfDiskTime',
'SysDataAcqOverallItemsPerSec',
'SysStatusRxEventsPerSec',
'SysStatusTopicsRxData',
'SysTagHoursQueried',
'SysHistoryClients',
'SysPerfStoragePrivateMBytes',
'SysPerfRetrievalPrivateMBytes',
'SysPerfSQLServerPrivateMBytes',
'SysPerfStorageCPU',
'SysPerfRetrievalCPU',
'SysPerfSQLServerCPU')
and wwRetrievalMode='cyclic'
and wwResolution=@minutes*60000 -- Convert minutes to milliseconds
and StartDateTime >= @start
and EndDateTime <= @end
union
select StartDateTime, TagName+' (0)', StateTimeAvgContained, StateTimeMinContained, StateTimeMaxContained, StateCount, StateTimePercent
from StateSummaryHistory
where TagName in (
'SysStatusSFDataPending')
and wwRetrievalMode='cyclic'
and wwResolution=@minutes*60000 -- Convert minutes to milliseconds
and StartDateTime >= @start
and EndDateTime <= @end
and value=0
