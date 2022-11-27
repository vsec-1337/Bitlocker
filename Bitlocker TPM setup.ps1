# ###############################################################################################################################
# #    Creator    :  C_MO                                                                                                       #
# #    Licence    :  SGS                                                                                                        #
# #    Comment    :  Activate Bitlocker, send Bitlocker informations (Status and Recovery Key) into AAD + KASEYA and change     #
# #                  MBR partition table to GPT                                                                                 #
# ###############################################################################################################################

### Bitlocker preriquisities ###
$TPMNotEnabled = Get-WmiObject win32_tpm -Namespace root\cimv2\security\microsofttpm | where {$_.IsEnabled_InitialValue -eq $false} -ErrorAction SilentlyContinue
$TPMEnabled = Get-WmiObject win32_tpm -Namespace root\cimv2\security\microsofttpm | where {$_.IsEnabled_InitialValue -eq $true} -ErrorAction SilentlyContinue


###VARIABLES### 
$File = "C:\temp\BitlockerVolume.txt"
$BLVS = Get-BitLockerVolume | Where-Object {$_.KeyProtector | Where-Object {$_.KeyProtectorType -eq 'RecoveryPassword'}}
$DiskType = Get-Disk | Where-Object {$_.PartitionStyle}

###########PART 1 : Disk partition table check and conversion to GPT ###########
If($DiskType.PartitionStyle -eq "GPT")
{    
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
    MBR2GPT.EXE /convert /allowFullOs
    #20 seconds break
    Start-Sleep -s 20
}
#Disk type recuperation for Kaseya
Get-Disk | Where-Object {$_.PartitionStyle | Out-File C:\Temp\partition.txt}

If(!$TPMNotEnabled)
{
    Initialize-Tpm -AllowClear -AllowPhysicalPresence -ErrorAction SilentlyContinue 
}
else
{
}

###########PART 2 : Disk status verification and encryption ###########
If(!$BLVS)
{
    #Added TPM protection to the disk.
    Add-BitLockerKeyProtector -MountPoint $env:SystemDrive -TpmProtector

    #Encryption of disk, Aes256 encryption method, Activation of a recovery password, Desactivation of the Hardware test.
    Enable-BitLocker -MountPoint $env:SystemDrive -EncryptionMethod Aes256 -RecoveryPasswordProtector -SkipHardwareTest -UsedSpaceOnly
    
    #We wait 10 seconds for disk encryption#
    Start-Sleep -s 10

    ###########PART 3 : Keys recuperation and share to AzureAD ###########
    $BLVS = Get-BitLockerVolume | Where-Object {$_.KeyProtector | Where-Object {$_.KeyProtectorType -eq 'RecoveryPassword'}}
    foreach($BLV in $BLVS)
    {
        $Key = $BLV | Select-Object -ExpandProperty KeyProtector | Where-Object {$_.KeyProtectorType -eq 'RecoveryPassword'}
    
        foreach($password in $Key)
        {
            BackupToAAD-BitLockerKeyProtector -MountPoint $BLV.MountPoint -KeyProtectorID $password.KeyProtectorId
        }
    }
}
else
{
###########PART 3 : Keys recuperation and export to AzureAD ###########
$BLVS = Get-BitLockerVolume | Where-Object {$_.KeyProtector | Where-Object {$_.KeyProtectorType -eq 'RecoveryPassword'}} 
    foreach($BLV in $BLVS)
    {
        $Key = $BLV | Select-Object -ExpandProperty KeyProtector | Where-Object {$_.KeyProtectorType -eq 'RecoveryPassword'}
    
        foreach($password in $Key)
        {
            BackupToAAD-BitLockerKeyProtector -MountPoint $BLV.MountPoint -KeyProtectorID $password.KeyProtectorId
        }
    }
}

########### PART 4 : Status Update###########
$BitlockerVolume = Get-BitLockerVolume -MountPoint $env:SystemDrive

#Creation of the file where is store the status of the disk
New-Item -Path "c:\temp" -Name "BitlockerVolume.txt"

#Remove space characters
$entry = $BitlockerVolume.VolumeStatus
$entry =  $entry -replace '(^\s+|\s+$)','' -replace '\s+',' '

#Bitlocker status export in C:\temp\BitlockerVolume.txt
If($entry -eq "FullyEncrypted" -or $entry -eq "EncryptionInProgress")
{
    Set-Content -Path $File -Value "Chiffre"   
}
else
{
    Set-Content -Path $File -Value "NOK"
}

########### PART 5 : Key Export to Kaseya ###########
#List of all BitlockerVolumes (BLVS)
$BLVS = Get-BitLockerVolume | Where-Object {$_.KeyProtector | Where-Object {$_.RecoveryPassword }}
#Selection of the protector where the recovery key is store
$Volume = $BLVS | Select-Object -ExpandProperty KeyProtector | Where-Object {$_.RecoveryPassword }
#Recovery Key recuperation
$Volume.RecoveryPassword | Out-File -FilePath C:\temp\BitlockerRecoveryKey.txt
if(!(Get-Content C:\temp\BitlockerRecoveryKey.txt))
{
    Set-Content -Path C:\temp\BitlockerRecoveryKey.txt -Value "No Key" 
}