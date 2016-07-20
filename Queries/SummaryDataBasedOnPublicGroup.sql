/*
Select Tags Based On Public Namespace & Query Them
==================================================

This script creates a "path" from the Historian's Public Namespace folders
which can be used to filter tags and then applied to query historical data

While this specific script may be useful, it is primarily an example of:

1. How to leverage the Public Namespace to create a list of tags
2. How to use a list of tags with an extension table (e.g. "History", "Live", etc.)

*/

-- Calculate midnight for this morning/yesterday morning
declare @YesterdayStart datetime
declare @YesterdayEnd datetime
set @YesterdayEnd = dateadd(day, datediff(day, 0, getdate()),0) -- Midnight this morning
set @YesterdayStart = dateadd(day, -1, @YesterdayEnd) -- One day before

-- Create a temporary list of the tags to query
declare @TagList table (TagName nvarchar(256), GroupName nvarchar(1000))

-- Use a CTE to recursively expand the Public Group hierarchy
; with DescendentTags( ChildKey, GroupName, GroupType ) as (
		select NameKey as ChildKey, cast('\'+Name as nvarchar(max)) as GroupName, [Type] as GroupType
		from PublicNameSpace
		where NameKey=1 
		union all
					
		select child.NameKey as ChildKey, parent.GroupName+'\'+ Name as GroupName, child.[Type] as GroupType
		from DescendentTags parent
		join PublicNameSpace child on child.ParentKey = parent.ChildKey
		where child.[Type] <> 1000000 -- Filter out the built-in "All" groups. 
		-- NOTE: In a default install, there will ONLY be the "All" groups, so this will return NO groups
	)

-- Use the CTE above to make a list of all the tags in the Public Groups and add it to the @TagList
insert @TagList (TagName, GroupName)
select t.TagName, GroupName
	from DescendentTags d
	join PublicGroupTag g on g.NameKey=d.ChildKey
	join TagRef r on g.wwDomainTagKey=r.wwDomainTagKey
	join Tag t on t.TagName = r.TagName
	where GroupName like '\Public Groups\Frankfurt\Main\Site2%' -- This is an application-specific filter

-- Query hourly statistics for the tags in the @TagList
select StartDateTime, l.GroupName, h.TagName, h.Average, h.Integral, h.Minimum, h.Maximum, h.ValueCount, h.PercentGood
from @TagList l
inner remote join AnalogSummaryHistory h -- This "inner remote join" syntax is required to prevent the T-SQL query optimizer from stripping out the tagname criteria
on h.TagName = l.TagName
where StartDateTime >= @YesterdayStart
and EndDateTime < @YesterdayEnd
and wwRetrievalMode = 'cyclic'
and wwCycleCount=24
