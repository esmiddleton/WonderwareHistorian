/*
Characterize Historian Resource Usage
=====================================
This query gives a high-level view of the loading of a Historian server over the last 24-hours using System Tags.
The results can be helpful as a first step in assessing the overall load on a system and to identify
resource constraints. 
Revised: 14-Dec-2021
By: E. Middleton
*/
use Runtime

declare @minutes int
declare @start datetime
declare @end datetime

set @minutes = 60*24 -- Duration to analyze
set @end = getdate()
set @start = dateadd(minute,-@minutes,@end)

select StartDateTime, TagName, Average, Minimum, Maximum, StdDev, Range=Maximum-Minimum,PercentGood=round(PercentGood,0)
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
'SysPerfSQLServerCPU',
'SysPerfStoragePageFaults',
'SysHistoryCacheFaults',
'SysPerfIndexingPageFaults',
'SysPerfRetrievalPageFaults',
'SysPerfSQLServerPageFaults',
'SysStatusTopicsRxData',
'SysStatusRxTotalItems')
and wwRetrievalMode='cyclic'
and wwResolution=@minutes*60000 -- Convert minutes to milliseconds
and StartDateTime >= @start
and EndDateTime <= @end
union
select StartDateTime, TagName+' (0)', StateTimeAvgContained, StateTimeMinContained, StateTimeMaxContained, StateCount, Null, StateTimePercent
from StateSummaryHistory
where TagName in (
'SysStatusSFDataPending')
and wwRetrievalMode='cyclic'
and wwResolution=@minutes*60000 -- Convert minutes to milliseconds
and StartDateTime >= @start
and EndDateTime <= @end
and value=0

select Start=DateTime, [End]=dateadd(millisecond,wwResolution,DateTime), TagName, Value, wwResolution from History 
where TagName in ('SysPerfCPUTotal','SysPerfDiskTime')
--and wwRetrievalMode='delta'
and wwEdgeDetection='leading'
and Value >95
union
select Start=DateTime, [End]=dateadd(millisecond,wwResolution,DateTime), TagName, Value, wwResolution from History 
where TagName in ('SysPerfAvailableBytes')
--and wwRetrievalMode='delta'
and wwEdgeDetection='leading'
and Value < 20000000
order by TagName, DateTime
