$DiskType = Get-Disk | Where-Object {$_.PartitionStyle}

###########PART 1 : Disk partition table check and conversion to GPT ###########
If($DiskType.PartitionStyle -eq "GPT")
{ 
    #Disk type recuperation
    Get-Disk | Where-Object {$_.PartitionStyle | Out-File C:\Temp\partition.txt}   
}
else
{
    ########### MBR to GPT convertion part ###########
    # Define the partition size required for GPT (in Bytes), 10000000 bytes = 10 MB
    $Shrink = "10000000"
    #System maximum partition size
    $Size = Get-PartitionSupportedSize -DriveLetter $env:SystemDrive
    #Calculate size of C: partition remaining after resizing
    $NewVolume = $Size.SizeMax - $Shrink

    #Resizing the system partition
    Resize-Partition -DriveLetter $env:SystemDrive -Size $NewVolume
    #10 seconds break
    Start-Sleep -s 10

    #Converting Disk to GPT Using MBR2GPT.exe
    MBR2GPT.EXE /convert /allowFullOS
    #20 seconds break
    Start-Sleep -s 10
    #Disk type recuperation
    Get-Disk | Where-Object {$_.PartitionStyle | Out-File C:\Temp\partition.txt}
}
