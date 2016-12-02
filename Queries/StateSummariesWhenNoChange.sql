/*

The standard "StateSummmaryHistory" table makes it really simple to calculate time-in-state statistics
for discreate (Boolean), integer and string tags. One limitation, though, is it only returns rows for
states that actually occurred during the period queried. In many reporting applications, it is important
to still include a row for a state that didn't occur (e.g. report the running hours for a pump was "0"
when it was off for the entire period).

This query returns:

	SysTimeHour   0     0
	SysPulse      15    900000

In this case, the values for SysTimeHour would be NULL without the ISNULL function. Without the extra OUTER JOIN, 
it would return:

	SysPulse      15    900000

The INNER REMOTE JOIN hint is required to force SQL Server to send the tag list to the Historian's OLE DB 
provider--without it, newer releases of SQL Server will "optimize" the query by trying to apply the criteria 
itself, rather than giving Historian the tag list (which Historian requires).

*/

SET NOCOUNT ON
DECLARE @StartDate DateTime
DECLARE @EndDate DateTime
SET @StartDate = DateAdd(Day,datediff(day,1,GetDate()),0)
SET @EndDate = DateAdd(minute,30, @StartDate)
SET NOCOUNT OFF

DECLARE @Tags TABLE(TagName nvarchar(128))
INSERT @Tags (TagName) VALUES
	('SysTimeHour'),
	('SysPulse')

SELECT t2.TagName, StateCount=ISNULL(StateCount,0), StateTimeTotal=ISNULL(StateTimeTotal,0)
FROM @Tags t2
LEFT OUTER JOIN (
	SELECT h.TagName, StateCount, StateTimeTotal, Value
		FROM @Tags t1
		INNER REMOTE JOIN StateSummaryHistory h
		ON h.TagName=t1.TagName
		WHERE h.wwVersion = 'Latest'
		AND h.wwRetrievalMode = 'Cyclic'
		AND h.wwCycleCount = 1
		AND h.StartDateTime >= @StartDate
		AND h.EndDateTime <= @EndDate
		AND h.Value=1
) d ON d.TagName=t2.TagName
