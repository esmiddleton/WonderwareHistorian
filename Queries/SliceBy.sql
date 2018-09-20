/*
Get Summary Statistics For One Tag Based On When Another Tag Value Changes
==========================================================================

!!! This script makes UNSUPPORTED modifications to your Runtime database !!!
!!!                       USE AT YOUR OWN RISK                           !!!

This SQL script extends the Historian "Runtime" database adding one user-defined function

The standard "AnalogSummmaryHistory" table makes it really simple to calculate statistics based on a
regular interval (e.g. "hourly"). In many applications it is more important to insterad get the same statistics,
but based on irregular period associated with a batch, phase, or some other state. This "wwkbSliceBy" function
address this need. 

This function will become OBSOLETE in Historian 2017 UPDATE 3, which will include native support for similar
queries in the "AnalogSummaryHistory" table.

Example:

	select * from dbo.wwkbSliceBy('2018-09-20 0:00','2018-09-21 0:00','SysPerfCPUTotal','SysPerfDiskTime')

Issues: Have observed unexplained "Cannot execute the query" errors running the query on some systems.

Has worked on:

	Historian 2014 R2/SQL Server 2012
	Historian 2017 Update 2/SQL Server 2016


Modified:   20-Sep-2018
By:         E. Middleton

*/

USE [Runtime]
go

create function dbo.wwkbSliceBy(@StartTime datetime2, @EndTime datetime2, @SliceByTag nvarchar(128), @SummaryTags nvarchar(max))
returns @SliceResults table
(
		StartDate datetime2,
		EndDate datetime2,
		SliceBy sql_variant,
		TagName nvarchar(128),
		Average float,
		Duration int
)
as
  begin
	declare @Slices table(DateTime datetime2, vValue sql_variant, wwResolution int, Quality int)
	insert @Slices(DateTime, vValue, wwResolution, Quality)
		select DateTime, vValue, wwResolution, Quality
		from History
		where DateTime > @StartTime and DateTime < @EndTime
		and TagName = @SliceByTag
		and wwRetrievalMode='delta'

	declare sliceby_periods
	cursor local fast_forward for
		select * from @Slices

	declare @SliceStartTime as datetime2
	declare @SliceEndTime as datetime2
	declare @SliceValue as sql_variant
	declare @SliceDuration as int
	declare @SliceQuality as int

	declare @Average as float

	open sliceby_periods

	fetch next from sliceby_periods
	into @SliceStartTime, @SliceValue, @SliceDuration, @SliceQuality

	-- For each slice, get summary data
	while @@fetch_status = 0
	  begin
		set @SliceEndTime = dateadd(millisecond,@SliceDuration,@SliceStartTime)
		insert @SliceResults (StartDate, EndDate, SliceBy, TagName, Average, Duration)
		select @SliceStartTime, @SliceEndTime, @SliceValue, TagName, Average, @SliceDuration
			from AnalogSummaryHistory
			where StartDateTime >= @SliceStartTime
			and EndDateTime < @SliceEndTime
			and TagName = @SummaryTags
			and wwRetrievalMode='full'
			and wwCycleCount=1
			
		fetch next from sliceby_periods
		into @SliceStartTime, @SliceValue, @SliceDuration, @SliceQuality
	   end

	close sliceby_periods
	deallocate sliceby_periods

	return
  end

go


