#	This PowerShell script changes the name of a Historian server stored in Excel files.
#
#	Usage:
#
#		RenameHistorianServer <pathToSearchForXLSFiles> <OldServerName> <NewServerName>
#
#	The optional "path" parameter will accept a specific aaTrend file name, or will search a path recursively for all .XLS/XLSX files.
#
#	This script is UNSUPPORTED and is released "as is" without warranty of any kind.
#
#	11-Nov-2020
#	E. Middleton

param (
	[string]$o = "",
	[string]$n = "",
	[string]$path = "."
)
Write-Host("Rename Historian server used in Historian Client Workbook (Excel add-in) files")


Function RenameInRange
{ 
    Param($range, $old, $new) 

    Write-Host "   " $range.Worksheet.Name

    $range.Replace( $old, $new, [Microsoft.Office.Interop.Excel.XlLookAt]::xlPart, [Microsoft.Office.Interop.Excel.XlSearchOrder]::xlByColumns, $false)
} # RenameInRange

		

# ==============================================
#		Main Function
# ==============================================

function RenameHistorianServer($path,$oldServer,$newServer) {

	Write-Host("Launching Excel...")
    $Excel = New-Object -Com Excel.Application
    $Excel.Visible = $True

	Write-Host("Finding all Excel files in '" + $path + "'")
	$serversNotReachble = @()
	
	# Loop through all aaTrend files in the specified path
	Get-ChildItem $path -Include "*.xlsx", "*.xls" -Recurse | % {
		Write-Host("Loading '"+$_.FullName+"'...")
        $Workbook = $Excel.Workbooks.Open($_.FullName, 0, $false) 

		$isDirty = $false
        $hidden = $Workbook.Worksheets | where-object {$_.Name -eq 'WData'}
        #$hidden = $Workbook.Worksheets("WData")
        if ($hidden) 
        {
            $isDirty = (RenameInRange ($hidden.Columns("F")) $oldServer $newServer) -Or $isDirty

            foreach( $sheet in $Workbook.Worksheets | where-object {$_.Visible -eq -1} ) {
                $isDirty = (RenameInRange $sheet.Cells $OldServer $NewServer) -Or $isDirty
            }

            if ($isDirty) {
			Write-Host "   Saving file..."
            $Workbook.Save()
            } else {
    			Write-Host "   No changes made...closing"
            }
            $Excel.ActiveWorkbook.Close()
        } else {
			Write-Host "   Does not use the Historian add-in...closing without changes"
            $Excel.ActiveWorkbook.Close()
        }
	}

    $Excel.Quit()
    $result = [System.Runtime.Interopservices.Marshal]::ReleaseComObject($Excel)
    Stop-Process -n Excel
}

RenameHistorianServer $path  $o $n
