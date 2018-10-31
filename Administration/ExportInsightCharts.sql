/*

Export Tool for Insight Charts

Revision: 0.1
Revised: 31-Oct-2018
By: E. Middleton


Stored procedures that export charts by generating a SQL script to recreate them

	Unsupported.ChartExport			Export a single chart based on its "ChartKey"
	
									exec Unsupported.ChartExport @ChartKey=42

	Unsupported.ChartExportAll		Export all the charts
	
									exec Unsupported.ChartExportAll

To use, execute one of the above stored procedures and then copy/paste or save the output to a file.
Then, execute the output on the target computer with SQL Server Management Studio.

Tested with Historian 2017 Update 2 (17.2)
									
*/

USE Runtime


DECLARE @CreateSchema VARCHAR(MAX)
SET @CreateSchema = 'CREATE SCHEMA Unsupported AUTHORIZATION dbo'
IF NOT EXISTS(SELECT * FROM sys.schemas WHERE name='Unsupported')
	EXEC(@CreateSchema)
GO

/*
	Stored procedure to export a single chart as a SQL script
*/

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[Unsupported].[ChartExport]') AND type in (N'P', N'PC'))
DROP PROCEDURE Unsupported.ChartExport
GO

create procedure Unsupported.ChartExport (
	@ChartKey int,
	@NoHeader bit = 0
	)
as
begin
	print 'set nocount on'

	declare @ChartUrl nvarchar(max)
	declare @UserName nvarchar(128)
	declare @ChartName nvarchar(128)
	select top 1 @UserName=u.UserName, @ChartUrl=ChartConfigurationUrl, @ChartName=ChartConfigurationName from dbo.ChartConfiguration c left outer join UserDetail u on u.UserKey=c.ChartConfigurationOwnerKey where ChartConfigurationKey=@ChartKey

	print '/* ----------------------------------------------------'
	print '   Export '''+@ChartName+''' for '''+@UserName+''''
	print '   ---------------------------------------------------- */'

	declare @rows nvarchar(max)

	print ''
	print '--Declare common variables used for the entire export'
	print 'declare @keywords dbo.ChartConfigurationKeywordType'
	print 'declare @tags dbo.ChartConfigurationTagType'
	print 'declare @properties dbo.ChartConfigurationPropertyType'
	print 'declare @dashboard dbo.DashboardConfigurationDetailType'

	print ''
	set @rows = 'insert into @keywords values'
	select @rows = @rows + '(N'''+Keyword+'''),' 
		from ChartConfigurationKeyword where ChartConfigurationKey=@ChartKey
	set @rows = left(@rows,len(@rows)-1)
	print @rows

	set @rows = 'insert into @tags values'
	select @rows = @rows + '(N'''+FQN
		+''',N'''+case Selected when 1 then 'True' else 'False' end
		+''',N'''+Color
		+''',N'''+case ActiveGroupTag when 1 then 'True' else 'False' end
		+''',N'''+convert(nvarchar(10),LayoutIndex)
		+''','+isnull('N'''+convert(nvarchar(10),SelectedOrder)+'''','NULL')+'),'
		from ChartConfigurationTag where ChartConfigurationKey=@ChartKey
	set @rows = left(@rows,len(@rows)-1)
	print @rows
 
	set @rows = 'insert into @properties values'
	select @rows = @rows + '(N'''+ChartConfigurationPropertyKey
		+''',N'''+ChartConfigurationPropertyValue+'''),'
		from ChartConfigurationProperty where ChartConfigurationKey=@ChartKey
	set @rows = left(@rows,len(@rows)-1)
	print @rows

	if (select count(*) from DashboardConfiguration where DashboardConfigurationKey=@ChartKey)>0 
		begin
			set @rows = 'insert into @dashboard values'
			select @rows = @rows + '(N'''+c.ChartConfigurationUrl
				+''',N'''+convert(nvarchar(10),d.Position)+'''),'
				from DashboardConfiguration d
				join Chartconfiguration c on c.ChartConfigurationKey=d.ChartConfigurationKey
				where DashboardConfigurationKey=@ChartKey
			set @rows = left(@rows,len(@rows)-1)
			print @rows
		end
	--exec aaSaveChartConfiguration @ChartConfigurationName=N'Test1',@ChartConfigurationUrl=N'aNWrq8pule2rH3Y5A',@ChartConfigurationType=1,@ChartConfigurationShareMode=1,@LastSharedDateTimeUtc=NULL,@TimeAggregate=1,@TimePreset=N'1',@ChartType=N'Composite Chart',@MobileShareMode=1,@EmbedShareMode=1,@LastAccessDateTimeUtc='2018-10-31 14:45:19.3950000',@ChartConfigurationKeyword=@p12,@ChartConfigurationTag=@p13,@ChartConfigurationProperty=@p14,@DashboardConfigurationDetail=@p15
	--print 'insert ChartConfiguration (ChartConfigurationKey,ChartConfigurationName,ChartConfigurationUrl,ChartConfigurationType,ChartConfigurationShareMode,LastSharedDateTimeUtc,CreationDateTimeUtc,TimePreset,TimeAggregate,ChartType,MobileShareMode,EmbedShareMode,ChartConfigurationOwnerKey) values'
	select @rows='exec aaSaveChartConfiguration '
		+'@ChartConfigurationName=N'''+ChartConfigurationName
		+''',@ChartConfigurationUrl=N'''+ChartConfigurationUrl
		+''',@ChartConfigurationType='+convert(nvarchar(10),ChartConfigurationType)
		+',@ChartConfigurationShareMode='+convert(nvarchar(10),ChartConfigurationShareMode)
		+',@LastSharedDateTimeUtc=null'
		+',@TimeAggregate='+convert(nvarchar(10),TimeAggregate)
		+',@TimePreset=N'''+convert(nvarchar(10),TimePreset)
		+''',@ChartType=N'''+ChartType
		+''',@MobileShareMode='+convert(nvarchar(10),MobileShareMode)
		+',@EmbedShareMode='+convert(nvarchar(10),EmbedShareMode)
		+',@LastAccessDateTimeUtc=null'
		+',@ChartConfigurationKeyword=@keywords,@ChartConfigurationTag=@tags,@ChartConfigurationProperty=@properties,@DashboardConfigurationDetail=@dashboard'
	from dbo.ChartConfiguration c where ChartConfigurationKey=@ChartKey
	print @rows

	-- Fix up the owner
	print ''
	print '-- Correct the owner, using the current user as the default if a matching name is not found'
	print 'declare @UserKey int'
	print 'set @UserKey=(select UserKey from UserDetail where UserName='''+@UserName+''')'
	print 'if @UserKey is not null update ChartConfiguration set ChartConfigurationOwnerKey=@UserKey where ChartConfigurationUrl=N'''+@ChartUrl+''''
	print 'go'
end
go

/*
	Stored procedure to export all charts as a SQL script
*/

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[Unsupported].[ChartExport]') AND type in (N'P', N'PC'))
DROP PROCEDURE Unsupported.ChartExportAll
GO

create procedure Unsupported.ChartExportAll (
	@NoHeader bit = 0
	)
as
begin
	print '/* ==================================================='
	print '   Exported'
	print '   At:   '+convert(nvarchar(30),getdate())
	print '   From: '''+CONVERT(nvarchar(100),SERVERPROPERTY('MachineName'))+''''
	print '   By:   '''+SYSTEM_USER+''' ('+USER_NAME()+')'
	print '   =================================================== */'

	declare @ChartKey int
	declare chart_cursor cursor fast_forward for
		select ChartConfigurationKey 
		from dbo.ChartConfiguration
		order by ChartConfigurationType, ChartConfigurationKey

	open chart_cursor

	fetch next from chart_cursor
	into @ChartKey

	print 'use Runtime'
	print ''
	while @@FETCH_STATUS = 0
		begin
			exec Unsupported.ChartExport @ChartKey
			
			fetch next from chart_cursor
			into @ChartKey
		end
	close chart_cursor
	deallocate chart_cursor
end
go

/*

select * from ChartConfiguration
exec Unsupported.ChartExport 1
exec Unsupported.ChartExportAll

*/
