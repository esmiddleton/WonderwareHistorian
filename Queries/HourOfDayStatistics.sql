/*
Hour Of Day Statistics For The Last Month
=========================================

In applications where there is a regular pattern based on the time of day (building automation, utilities, etc.)
it is often helpful to compare current signals with how those signals have varied in the past for the same hour. 
This example includes two variations on theme. Both group the statistics by hour of the day--one has the end time 
at midnight tonight (in the future) and the other ends with the current hour.

These examples were inspired by an application created by:

	Eric Conder 
	Lance Dofflemyer
	Robert Touchton
	MR Systems, Inc.
	https://www.mrsystems.com/

Modified:   20-Sep-2018
By:         E. Middleton

*/

declare @midnight datetime2
set @midnight = dateadd(day, datediff(day, 0, getdate())+1, 0)

declare @start datetime2
set @start = dateadd(day, -30, @midnight)

-- Rolling 24 hours ending at "now"
select TagName, HourOfDay, DateTime=max(StartDateTime), Minimum=min(Minimum), Maximum=max(Maximum), Average=avg(Average), StdDev=stdevp(Average), PercentGood=avg(PercentGood), Count=Count(*)
from (
	select StartDateTime, TagName, Minimum, Maximum, Average, OPCQuality, PercentGood,
	HourOfDay=datepart(hour,StartDateTime)
	from AnalogSummaryHistory
	where StartDateTime >= @start
	and EndDateTime <= getdate()
	and TagName='SysTagHoursQueried'
	and wwResolution=60*60*1000
) A
group by TagName, HourOfDay
order by TagName, DateTime

-- Fixed 24 hours ending at midnight tonight
select TagName, HourOfDay, DateTime=dateadd(hour, HourOfDay-24, @midnight), Minimum=min(Minimum), Maximum=max(Maximum), Average=avg(Average), StdDev=stdevp(Average), PercentGood=avg(PercentGood), Count=Count(*)
from (
	select StartDateTime, TagName, Minimum, Maximum, Average, OPCQuality, PercentGood,
	HourOfDay=datepart(hour,StartDateTime)
	from AnalogSummaryHistory
	where StartDateTime >= @start
	and EndDateTime <= getdate()
	and TagName='SysTagHoursQueried'
	and wwResolution=60*60*1000
) A
group by TagName, HourOfDay
order by TagName, HourOfDay
