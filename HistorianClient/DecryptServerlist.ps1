#	This PowerShell script changes the name of a Historian server stored in "aaTrend" files.
#
#	It must be run from the 32-bit PowerShell command line:
#
#	Usage:
#
#		powershell -sta RenameTrendServer.ps1 [-path <pathToSearchForCRVFiles>] -o <OldServerName> -n <NewServerName> [-d]
#
#	The optional "path" parameter will accept a specific aaTrend file name, or will search a path recursively for all aaTrend files.
#
# 	The optional "d" parameter will decrypt an older format "aaTrend" file into the plain text XML used by Historian Client 10.1 and later
#
#	This script is UNSUPPORTED and is released "as is" without warranty of any kind.
#
#	21-Mar-2023
#	E. Middleton


if (!([System.Threading.Thread]::CurrentThread.GetApartmentState() -eq "STA")) {
	Write-Host "*** This must run as a single-threaded script. Run this from within PowerShell with:"
	Write-Host "       powershell -STA <script>"
} else {
	if ([System.IntPtr]::size -eq 8) {
		Write-Host "*** This must run as a 32-bit script. Restart from the x86 PowerShell application"
	} else {
		if (!( ([System.Reflection.Assembly]::LoadFrom("C:\Program Files (x86)\Common Files\ArchestrA\aaHistClientUtil.dll")) -or
			([System.Reflection.Assembly]::LoadFrom("C:\Program Files\Common Files\ArchestrA\aaHistClientUtil.dll")) )) {
			Write-Host "*** Unable to load the Historian Client assembly 'aaHistClientUtil.dll'"
		} else {
            $serversFile = $Env:localappdata + '\Wonderware\ActiveFactory\servers.xml'

	        # Load the server list as an XML document
	        [System.Xml.XmlDocument]$doc = New-Object System.Xml.XmlDocument
            $doc.Load($serversFile)

			# Use an internal class to read encrypted elements of an aaTrend file (Historian Client 10.1 and earlier)
			[System.Xml.XmlElement]$unwrapped = [ArchestrA.HistClient.Util.aaXmlTools]::UnwrapElement( $doc, $doc.DocumentElement, $doc.root.serverLists  )
			Write-Host "   Saving file..."
			$doc.Save($serversFile)
		}
	}
}
