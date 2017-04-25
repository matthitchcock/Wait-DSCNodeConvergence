function Wait-DSCNodeConvergence
{
	[CmdletBinding()]
	[OutputType([array])]
	param
	(
		[string[]]$ComputerName,
		[PScredential]$Credential,
		[datetime]$DateTime = (Get-Date),
		[Int]$StatusWaitIntervalSeconds = '5'
	)
	
	# Prepare a New-PSSession parameters object
	$NewSessionparam = @{
		ComputerName = ""
	}
	
	if ($Credential)
	{
		$NewSessionparam.Add("Credential", $Credential)
	}
	
	# Build our computer objects to monitor
	
	[System.Array]$Output = @()
	foreach ($Computer in $ComputerName)
	{
		$DSCNode = New-Object -TypeName PSCustomObject -Property @{
			ComputerName = $Computer
			ConvergeAfterTime = $DateTime
			StartTime = (Get-Date)
			CapturedEndTime = ""
			Status = ""
			DurationMinutes = ""
			SessionInfo = ""
		}
		
		$Output += $DSCNode
	}
	
	# Make sure every node has an open session so the release is coordinated
	do
	{
		foreach ($DSCNode in $Output)
		{
			if ($DSCNode.SessionInfo.State -ne "Opened")
			{
				$NewSessionparam.ComputerName = $DSCNode.ComputerName
				
				$DSCNode.SessionInfo = (New-PSSession @NewSessionparam -ErrorAction SilentlyContinue)
			}
		}
	}
	until (($Output.Where{
				$PSitem.SessionInfo.State -eq "Opened"
			}.Count) -eq $Output.Count)
	
	do
	{
		# Here is where we run the Invoke-Command to DSCConfigurationStatus and update the object
		Write-Verbose -Message "Waiting for for Status Updates ..."
		
		Start-Sleep -Seconds $StatusWaitIntervalSeconds
		
		foreach ($DSCNode in $Output)
		{
			if (($DSCNode.Status -ne "Success") -and ($DSCNode.StartDate -lt $DateTime))
			{
				if ($DSCNode.SessionInfo.State -eq "Opened")
				{
					
					$StatusData = Invoke-Command -Session $DSCNode.SessionInfo -ScriptBlock {
						Get-DscConfigurationStatus
					} -ErrorAction SilentlyContinue # CONSIDER ERROR VARIABLE SO IF SERVER REBOOTED NEED TO REBUILD SESSION
					
					if ($StatusData)
					{
						# Update $DSCNode with $StatusData attributes
						# Compare the time to the ConvergedAfterTime, if later then update the data, if not then "Waiting"
						if ($StatusData.StartDate -lt $DateTime)
						{
							$DSCNode.Status = "Waiting"
						}
						else
						{
							$DSCNode.Status = $StatusData.Status
						}
						
						if ($DSCNode.Status -eq "Success")
						{
							# Set the End time and average time, etc.
							$DSCNode.CapturedEndTime = Get-Date
							$DSCNode.DurationMinutes = ($DSCNode.CapturedEndTime - $DateTime).Minutes
						}
					}
				}
				else
				{
					$DSCNode.Status = "Not Reachable"
					
					do
					{
						$NewSessionparam.ComputerName = $DSCNode.ComputerName
						
						$RebuiltSession = New-PSSession @NewSessionparam -ErrorAction SilentlyContinue
					}
					until ($RebuiltSession)
					
					$DSCNode.SessionInfo = $RebuiltSession	
				}
			}
		}
		
		# Rudimentary output for experimentation
		Write-Output ""
		Write-Output ""
		Write-Output $Output | Format-Table -AutoSize
		Write-Output ""
		Write-Output ""
	}
	
	until (($Output.Where{
				$PSitem.Status -eq "Success"
			}.Count) -eq $Output.Count)
	
	# Close all sessions
	foreach ($DSCNode in $Output)
	{
		Remove-PSSession -Session $DSCNode.SessionInfo
	}
	
	Write-Verbose -Message "Convergence is complete"
	
	return $output
}
