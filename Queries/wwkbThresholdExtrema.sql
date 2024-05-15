/*
Get Summary Statistics For The Periods When Limits Are Violated
===============================================================

!!! This script makes UNSUPPORTED modifications to your Runtime database !!!
!!!                       USE AT YOUR OWN RISK                           !!!

This SQL script extends the Historian "Runtime" database adding one user-defined function

The standard "AnalogSummmaryHistory" table makes it really simple to calculate statistics based on a
regular interval (e.g. "hourly"). In many applications it is more important to instead get the same statistics,
but based on irregular period associated with when limits are violated. This "wwkbThresholdExtrema" function
addresses this need. 

Example:

	select * from dbo.wwkbThresholdExtrema('2024-04-20 0:00:05','2024-04-20 1:00','SysPerfCPUTotal', 15.0, 50.0)

Modified:   15-May-2024
By:         E. Middleton

*/

USE [Runtime]
go

create function dbo.wwkbThresholdExtrema(@StartTime datetime2, @EndTime datetime2, @Tag LongTagNameType, @Min float, @Max float)
returns @ExtremaResults table
(
		StartDate datetime2,
		EndDate datetime2,
		TagName LongTagNameType,
		Edge nvarchar(20), 
		Minimum float,
		MinDateTime datetime2,
		Maximum float,
		MaxDateTime datetime2,
		Duration int,
		Value float
)
as
  begin
	declare @Exceptions table(DateTime datetime2, Edge nvarchar(20), wwResolution int, Quality int, Value float)
	insert @Exceptions(DateTime, Edge, wwResolution, Quality, Value)
		select DateTime, 
			case 
				when Value <= @Min then 'Min'
				else 'Trailing' end,
			wwResolution, Quality, Value
		from History
		where DateTime = @StartTime 
		and TagName = @Tag
		and wwRetrievalMode='startbound'

	insert @Exceptions(DateTime, Edge, wwResolution, Quality, Value)
		select DateTime, 
			case 
				when Value <= @Min then 'Min'
				else 'Trailing' end,
			wwResolution, Quality, Value
		from History
		where DateTime >= @StartTime and DateTime < @EndTime
		and TagName = @Tag
		and wwRetrievalMode='delta'
		and wwEdgeDetection='both'
		and Value <= @Min

	insert @Exceptions(DateTime, Edge, wwResolution, Quality, Value)
		select DateTime, 
			case 
				when Value >= @Max then 'Max'
				else 'Trailing' end,
			wwResolution, Quality, Value
		from History
		where DateTime >= @StartTime and DateTime < @EndTime
		and TagName = @Tag
		and wwRetrievalMode='delta'
		and wwEdgeDetection='both'
		and Value >= @Max

	declare exception_periods
	cursor local fast_forward for
		select * from @Exceptions order by DateTime

	declare @ExceptionStartTime as datetime2
	declare @ExceptionEndTime as datetime2
	declare @Edge as nvarchar(20)
	declare @LastEdge as nvarchar(20)
	declare @Duration as int
	declare @Quality as int
	declare @Value as float
	declare @LastValue as float

	declare @Minimum as float
	declare @Maximum as float

	open exception_periods

	fetch next from exception_periods
	into @ExceptionEndTime, @Edge, @Duration, @Quality, @Value

	set @ExceptionStartTime = @StartTime
	set @LastEdge = ''

	-- For each exception, get summary data
	while @@fetch_status = 0
	  begin
		if @Edge <> 'Trailing' 
			begin
				set @ExceptionStartTime = @ExceptionEndTime
				set @LastEdge = @Edge
				set @LastValue = @Value
			end
		else
			begin
				if @LastValue is NULL
					begin
						set @LastValue = @Value
						set @LastEdge = case 
							when @Value >= @Max then 'Max'
							when @Value <= @Min then 'Min'
							else 'Trailing' end
					end
				insert @ExtremaResults (StartDate, EndDate, TagName, Edge, Minimum, MinDateTime, Maximum, MaxDateTime, Duration, Value)
				select @ExceptionStartTime, @ExceptionEndTime, TagName, @LastEdge, Minimum, MinDateTime, Maximum, MaxDateTime, datediff(millisecond,@ExceptionStartTime,@ExceptionEndTime), @LastValue
					from AnalogSummaryHistory
					where StartDateTime >= @ExceptionStartTime
					and EndDateTime <= @ExceptionEndTime
					and TagName = @Tag
					and wwRetrievalMode='cyclic'
					and wwCycleCount=1
		end
			
		fetch next from exception_periods
		into @ExceptionEndTime, @Edge, @Duration, @Quality, @Value
	   end

	close exception_periods
	deallocate exception_periods

	return
  end

go
