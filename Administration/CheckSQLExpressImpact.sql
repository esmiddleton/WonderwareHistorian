/*
Identify SQL Express Resource Constraints
=========================================
This query specifically targets identifying when resource constraints imposed by SQL Server Express have 
impacted client retrieval performance. It reports high-level statistics on key resources over the last 24-hours 
using System Tags. It produces three result sets:

1.  SQL Server version and edition
2.  Summarizes key memory and CPU usage metrics
3.  Lists occassions in the last 24-hours where the Express limitations likely throttled performance

The results can be helpful to identiufy when an upgrade to SQL Server Standard is warranted.

NOTE: Be sure to replace the "XX" in line 22

Revised: 4-Apr-2025
By: E. Middleton
*/
use Runtime

declare @TotalCores int
set @TotalCores=XX   -- You must explicitly set this based on your knowledge of the target system--can't be automatic. Getting this wrong will make finding CPU limits unreliable

declare @minutes int
declare @start datetime
declare @end datetime

-- By default, use data from the last 24-hours, but change that here
set @minutes = 60*24 -- Duration to analyze
set @end = getdate()
set @start = dateadd(minute,-@minutes,@end)

declare @UsableCores int
declare @UsableSockets int
declare @CoresPerSocket int

-- Find the currently detected core and how they are limited 
SELECT 
	@UsableCores = cpu_count, -- In SQL Express, this will be limited to the lesser of 1 CPU socket or 4 cores
	@CoresPerSocket = cores_per_socket,
	@UsableSockets = socket_count
	FROM sys.dm_os_sys_info;

-- Output system and SQL version information
SELECT 
    SERVERPROPERTY('Edition') AS Edition,
    SERVERPROPERTY('ProductVersion') AS Version,
	@UsableCores AS UsableCores, 
	@CoresPerSocket AS CoresPerSocket,
	@UsableSockets AS UsableSockets, 
	@TotalCores AS TotalCores,
	physical_memory_kb / 1000 AS PhysicalMBytes, 
	virtual_machine_type_desc AS VirtualMachineType, 
	container_type_desc AS ContainerType 
	FROM sys.dm_os_sys_info;

-- Assess resource usage based on Historian system tags, focusing on the ones impacted by SQL Express limitations
select StartDateTime, TagName, Average, Minimum, Maximum, StdDev, Range=Maximum-Minimum,PercentGood=round(PercentGood,0)
from AnalogSummaryHistory
where TagName in (
'SysPerfCPUTotal',
'SysPerfCPUMax',
'SysPerfSQLServerVirtualMBytes',
'SysPerfSQLServerCPU')
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

-- Find incidents when the resource limits likely impacted performance
select Start=DateTime, [End]=dateadd(millisecond,wwResolution,DateTime), TagName, Value, wwResolution from History 
where TagName in ('SysPerfSQLServerVirtualMBytes')
and wwEdgeDetection='leading'
and Value > 0.95 * 1000 -- 95% of 1,000 MB (e.g. of 1 GB)
and DateTime >= @start
and DateTime <= @end
union
select Start=DateTime, [End]=dateadd(millisecond,wwResolution,DateTime), TagName, Value, wwResolution from History 
where TagName in ('SysPerfSQLServerCPU') -- This tag is a percentage of total CPU, e.g. if limited to a single core on a 4-processor system "25%" would mean that core was at "100%" load
and wwEdgeDetection='leading'
and Value > 95.0 / @TotalCores * @UsableCores -- This is 95% of the processors available to SQL Express
and DateTime >= @start
and DateTime <= @end
order by DateTime, TagName
