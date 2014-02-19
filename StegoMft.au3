#RequireAdmin
#Region ;**** Directives created by AutoIt3Wrapper_GUI ****
#AutoIt3Wrapper_Change2CUI=y
#AutoIt3Wrapper_Res_Comment=StegoMft
#AutoIt3Wrapper_Res_Description=StegoMft
#AutoIt3Wrapper_Res_Fileversion=1.0.0.2
#AutoIt3Wrapper_Res_LegalCopyright=Joakim Schicht
#AutoIt3Wrapper_Res_requestedExecutionLevel=asInvoker
#EndRegion ;**** Directives created by AutoIt3Wrapper_GUI ****

#Include <WinAPIEx.au3>
#include <Array.au3>
#Include <String.au3>
#Include <APIConstants.au3>
;
; http://code.google.com/p/mft2csv/
;
Global $NeedLock=0, $TargetDrive, $IsFirstRun=1, $rBuffer, $ref = -1, $StartRef, $EndRef, $StartByte,$MinimumBytes=10, $RecordBaseFree, $TestA=1
Global $TargetFileName, $DATA_Name, $FN_FileName, $NameQ[5], $ImageOffset, $ADS_Name, $hDisk
Global $OutPutPath=@ScriptDir, $InitState = False, $DATA_Clusters, $AttributeOutFileName, $DATA_InitSize, $IndexNumber, $NonResidentFlag, $DATA_RealSize, $DataRun, $DATA_LengthOfAttribute
Global $TargetDrive = "", $ALInnerCouner, $MFTSize, $TargetOffset, $SectorsPerCluster,$MFT_Record_Size,$BytesPerCluster,$BytesPerSector,$MFT_Offset,$IsDirectory
Global $RUN_VCN[1],$RUN_Clusters[1],$MFT_RUN_Clusters[1],$MFT_RUN_VCN[1],$DataQ[1],$sBuffer,$AttrQ[1]
Global Const $RecordSignature = '46494C45' ; FILE signature
Global Const $RecordSignatureBad = '44414142' ; BAAD signature
Global Const $STANDARD_INFORMATION = '10000000'
Global Const $ATTRIBUTE_LIST = '20000000'
Global Const $FILE_NAME = '30000000'
Global Const $OBJECT_ID = '40000000'
Global Const $SECURITY_DESCRIPTOR = '50000000'
Global Const $VOLUME_NAME = '60000000'
Global Const $VOLUME_INFORMATION = '70000000'
Global Const $DATA = '80000000'
Global Const $INDEX_ROOT = '90000000'
Global Const $INDEX_ALLOCATION = 'A0000000'
Global Const $BITMAP = 'B0000000'
Global Const $REPARSE_POINT = 'C0000000'
Global Const $EA_INFORMATION = 'D0000000'
Global Const $EA = 'E0000000'
Global Const $PROPERTY_SET = 'F0000000'
Global Const $LOGGED_UTILITY_STREAM = '00010000'
Global Const $ATTRIBUTE_END_MARKER = 'FFFFFFFF'
Global $MftSlack_Signature, $MftSlack_ChunkNumber=1, $MftSlack_ChunkSize=0, $MftSlack_DataTotalSize, $MftSlack_ChunkNumberPrevious, $TotalSlackInMft=0
Global $DoHide=0,$DoExtract=0,$DoClean=0,$DoCheck=0,$DoDump=0

ConsoleWrite("Starting StegoMft by Joakim Schicht" & @CRLF)
ConsoleWrite("Version 1.0.0.2" & @CRLF & @CRLF)
_validate_parameters()
Global $Timerstart = TimerInit()

_ReadBootSector($TargetDrive)
$BytesPerCluster = $SectorsPerCluster*$BytesPerSector
$MFTEntry = _FindMFT(0)
_DecodeMFTRecord($MFTEntry,0)
_DecodeDataQEntry($DataQ[1])
$MFTSize = $DATA_RealSize
ConsoleWrite("Total records in $MFT: " & $MFTSize/1024 & @CRLF)

Select
	Case $DoHide
		$Payload = $cmdline[2]
		$PayloadSize=FileGetSize($Payload)
		$hPayload = FileOpen($Payload,16)
		$TestData = FileRead($hPayload)
		$SizeRemaining = $PayloadSize
		$SizeRemaining*=2
		$MftSlack_DataTotalSize = $PayloadSize
		$MftSlack_DataTotalSize = _SwapEndian(Hex($MftSlack_DataTotalSize,8))
		$IndexNumber = $cmdline[4]
		$MftSlack_Signature = $cmdline[5]
	Case $DoExtract
		$OutputFile = $cmdline[2]
		$SizeRecovered=0
		$IndexNumber = $cmdline[4]
		$MftSlack_Signature = $cmdline[5]
	Case $DoCheck
		$ProcessedCounter = 0
		If StringIsDigit($StartRef) <> 1 Then $StartRef = 0
		If StringIsDigit($EndRef) <> 1 Then $TestA = 0
		If StringIsDigit($EndRef) <> 1 Then $EndRef = $MFTSize/1024
		$IndexNumber = $StartRef
	Case $DoClean
		$ProcessedCounter = 0
		If StringIsDigit($StartRef) <> 1 Then $StartRef = 0
		If StringIsDigit($EndRef) <> 1 Then $TestA = 0
		If StringIsDigit($EndRef) <> 1 Then $EndRef = $MFTSize/1024
		$IndexNumber = $StartRef
	Case $DoDump
		$EndRef = $StartRef
		$IndexNumber = $StartRef
EndSelect

$RecordBaseFree = 2049-28-(Int($StartByte)*2)
$MinimumBytes*=2

If $MFTSize < 1024*$IndexNumber Then
	ConsoleWrite("Error: MFT StartRef too high" & @CRLF)
	Exit
EndIf

If $DoHide Then
	If ($PayloadSize>($MFTSize*0.5)) Or $PayloadSize>(($MFTSize-(1024*$IndexNumber))*0.5) Then
		ConsoleWrite("Warning: $MFT may not be large enough to hide payload" & @CRLF)
		Sleep(3000)
	EndIf
EndIf
Global $RUN_VCN[1], $RUN_Clusters[1]
_ExtractDataRuns()
$MFT_RUN_VCN = $RUN_VCN
$MFT_RUN_Clusters = $RUN_Clusters

$hDisk = _WinAPI_CreateFile("\\.\" & $TargetDrive,2,2,7)
If $hDisk = 0 Then
	ConsoleWrite("CreateFile: " & _WinAPI_GetLastErrorMessage() & @CRLF)
	Exit
EndIf

$IsFirstRun=0
Global $RecordSlackArray[1], $Available, $SizeRemaining
$NeedLock=1

$rBuffer = DllStructCreate("byte[" & $MFT_Record_Size & "]")

$nBytes=0
$hDisk = _WinAPI_CreateFile("\\.\" & $TargetDrive,2,6,7)
If $hDisk = 0 then
	ConsoleWrite("Error: CreateFile returned: " & _WinAPI_GetLastErrorMessage() & " for: " & "\\.\" & $TargetDrive & @crlf)
	Exit
EndIf

If $DoHide Then
	$PayloadSize*=2
	_WinAPI_CloseHandle($hDisk)
	$hDisk = _GetVolumeHandle($TargetDrive)
	For $r = 1 To Ubound($MFT_RUN_VCN)-1
		$Pos = $MFT_RUN_VCN[$r]*$BytesPerCluster
		ConsoleWrite("$MFT run: " & $r & @CRLF)
		_WinAPI_SetFilePointerEx($hDisk, $Pos, $FILE_BEGIN)
		For $i = 0 To $MFT_RUN_Clusters[$r]*$BytesPerCluster-$MFT_Record_Size Step $MFT_Record_Size
			$ref += 1
			_WinAPI_ReadFile($hDisk, DllStructGetPtr($rBuffer), $MFT_Record_Size, $nBytes)
			If $ref < $IndexNumber Then ContinueLoop
			$record = DllStructGetData($rBuffer, 1)
			If StringMid($record,3,8) <> $RecordSignature Then
				_DebugOut($ref & " The record signature is bad", StringMid($record, 1, 34))
				ContinueLoop
			EndIf
			_DecodeMFTRecord($record,1)
			If $RecordBaseFree-$RecordSlackArray[0] < $MinimumBytes Then ;set lower limit at 10 bytes
				ConsoleWrite("Warning: Not enough space record: " & $ref & @CRLF)
				ContinueLoop
			EndIf
			$TmpOffset = DllCall('kernel32.dll', 'int', 'SetFilePointerEx', 'ptr', $hDisk, 'int64', 0, 'int64*', 0, 'dword', 1)
			$SizeRemaining -= _SetMftPayload($hDisk,$TmpOffset[3]-1024,$record,$PayloadSize-$SizeRemaining)
			$MftSlack_ChunkNumber+=1
			If $SizeRemaining<=0 Or $IndexNumber >= $MFTSize/1024 Then
				ConsoleWrite(@CRLF & $PayloadSize/2 & " bytes hidden in " & $MftSlack_ChunkNumber-1 & " records" & @CRLF)
				_End($Timerstart)
				Exit
			EndIf
		Next
		ConsoleWrite("Processed records: " & $ref & @CRLF)
	Next
	ConsoleWrite("Error: Could not inject all payload. Remaining bytes = " & $SizeRemaining/2 & @CRLF)
ElseIf $DoExtract Then
	$SizeRecovered=0
	FileDelete($OutputFile)
	$hOutputFile = _WinAPI_CreateFile("\\.\" & $OutputFile,1,6,7)
	If $hOutputFile = 0 then
		ConsoleWrite("Error: CreateFile returned: " & _WinAPI_GetLastErrorMessage() & " for: " & "\\.\" & $OutputFile & @crlf)
		Exit
	EndIf
	For $r = 1 To Ubound($MFT_RUN_VCN)-1
		$Pos = $MFT_RUN_VCN[$r]*$BytesPerCluster
		ConsoleWrite("$MFT run: " & $r & @CRLF)
		_WinAPI_SetFilePointerEx($hDisk, $Pos, $FILE_BEGIN)
		For $i = 0 To $MFT_RUN_Clusters[$r]*$BytesPerCluster-$MFT_Record_Size Step $MFT_Record_Size
			$ref += 1
			_WinAPI_ReadFile($hDisk, DllStructGetPtr($rBuffer), $MFT_Record_Size, $nBytes)
			If $ref < $IndexNumber Then ContinueLoop
			$record = DllStructGetData($rBuffer, 1)
			If StringMid($record,3,8) <> $RecordSignature Then
				_DebugOut($ref & " The record signature is bad", StringMid($record, 1, 34))
				ContinueLoop
			EndIf
			_DecodeMFTRecord($record,1)
			If $RecordBaseFree-$RecordSlackArray[0] < $MinimumBytes Then ;set lower limit at 10 bytes
				ConsoleWrite("Warning: Not enough space record: " & $ref & @CRLF)
				ContinueLoop
			EndIf
			$TmpOffset = DllCall('kernel32.dll', 'int', 'SetFilePointerEx', 'ptr', $hDisk, 'int64', 0, 'int64*', 0, 'dword', 1)
			$SizeRecovered += _GetMftPayload($hDisk,$hOutputFile,$TmpOffset[3]-1024,$record,$SizeRecovered)
			If $ref >= $MFTSize/1024 Or ($SizeRecovered>0 And $SizeRecovered = $MftSlack_DataTotalSize) Then
				If Not $SizeRecovered > 0 Then
					ConsoleWrite("Error: Nothing extracted" & @CRLF)
				Else
					ConsoleWrite(@CRLF & "Extracted " & $SizeRecovered & " bytes from " & $MftSlack_ChunkNumber & " records" & @CRLF)
					_End($Timerstart)
					Exit
				EndIf
			EndIf
		Next
		ConsoleWrite("Processed records: " & $ref & @CRLF)
	Next
	ConsoleWrite("Error: Could not extract all data. Extracted bytes = " & $SizeRecovered & ". Remaining bytes = " & $MftSlack_DataTotalSize-$SizeRecovered & @CRLF)
ElseIf $DoCheck Then
	For $r = 1 To Ubound($MFT_RUN_VCN)-1
		$Pos = $MFT_RUN_VCN[$r]*$BytesPerCluster
		ConsoleWrite("$MFT run: " & $r & @CRLF)
		_WinAPI_SetFilePointerEx($hDisk, $Pos, $FILE_BEGIN)
		For $i = 0 To $MFT_RUN_Clusters[$r]*$BytesPerCluster-$MFT_Record_Size Step $MFT_Record_Size
			$ref += 1
			_WinAPI_ReadFile($hDisk, DllStructGetPtr($rBuffer), $MFT_Record_Size, $nBytes)
			If $ref < $StartRef Then ContinueLoop
			If $ref > $EndRef Then ExitLoop
			$record = DllStructGetData($rBuffer, 1)
			If StringMid($record,3,8) <> $RecordSignature Then
				_DebugOut($ref & " The record signature is bad", StringMid($record, 1, 34))
				ContinueLoop
			EndIf
			_DecodeMFTRecord($record,1)
			$ProcessedCounter+=1
			$RecordSlack = $RecordBaseFree-$RecordSlackArray[0]
			If $RecordSlack > 0 Then
				$TotalSlackInMft += $RecordSlack
			EndIf
		Next
		If $ref > $EndRef Then ExitLoop
		ConsoleWrite("Processed records: " & $ProcessedCounter & @CRLF)
	Next
	ConsoleWrite(@CRLF & "Computed MFT Slack over " & $ProcessedCounter & " records: " & @CRLF)
	ConsoleWrite("MB: " & Round($TotalSlackInMft/2/1024/1024,2) & @CRLF)
	ConsoleWrite("Bytes: " & $TotalSlackInMft/2 & @CRLF)
ElseIf $DoClean Then
	_WinAPI_CloseHandle($hDisk)
	$hDisk = _GetVolumeHandle($TargetDrive)
	For $r = 1 To Ubound($MFT_RUN_VCN)-1
		$Pos = $MFT_RUN_VCN[$r]*$BytesPerCluster
		ConsoleWrite("$MFT run: " & $r & @CRLF)
		_WinAPI_SetFilePointerEx($hDisk, $Pos, $FILE_BEGIN)
		For $i = 0 To $MFT_RUN_Clusters[$r]*$BytesPerCluster-$MFT_Record_Size Step $MFT_Record_Size
			$ref += 1
			_WinAPI_ReadFile($hDisk, DllStructGetPtr($rBuffer), $MFT_Record_Size, $nBytes)
			If $ref < $StartRef Then ContinueLoop
			If $ref > $EndRef Then ExitLoop
			$record = DllStructGetData($rBuffer, 1)
			If StringMid($record,3,8) <> $RecordSignature Then
				_DebugOut($ref & " The record signature is bad", StringMid($record, 1, 34))
				ContinueLoop
			EndIf
			_DecodeMFTRecord($record,1)
			$TmpOffset = DllCall('kernel32.dll', 'int', 'SetFilePointerEx', 'ptr', $hDisk, 'int64', 0, 'int64*', 0, 'dword', 1)
			_CleanMftSlack($hDisk,$TmpOffset[3]-1024,$record)
			$ProcessedCounter+=1
		Next
		If $ref > $EndRef Then ExitLoop
		ConsoleWrite("Cleaned records: " & $ProcessedCounter & @CRLF)
	Next
ElseIf $DoDump Then
	For $r = 1 To Ubound($MFT_RUN_VCN)-1
		$Pos = $MFT_RUN_VCN[$r]*$BytesPerCluster
		_WinAPI_SetFilePointerEx($hDisk, $Pos, $FILE_BEGIN)
		For $i = 0 To $MFT_RUN_Clusters[$r]*$BytesPerCluster-$MFT_Record_Size Step $MFT_Record_Size
			$ref += 1
			_WinAPI_ReadFile($hDisk, DllStructGetPtr($rBuffer), $MFT_Record_Size, $nBytes)
			If $ref < $StartRef Then ContinueLoop
			If $ref > $EndRef Then ExitLoop
			$record = DllStructGetData($rBuffer, 1)
			ConsoleWrite("Original record: " & @CRLF)
			ConsoleWrite(_HexEncode($record) & @crlf)
			If StringMid($record,3,8) <> $RecordSignature Then
				_DebugOut($ref & " The record signature is bad", StringMid($record, 1, 34))
				ContinueLoop
			EndIf
			_DecodeMFTRecord($record,1)
			$UpdSeqArrOffset = StringMid($record,11,4)
			$UpdSeqArrOffset = Dec(StringMid($UpdSeqArrOffset,3,2) & StringMid($UpdSeqArrOffset,1,2))
			$UpdSeqArrSize = StringMid($record,15,4)
			$UpdSeqArrSize = Dec(StringMid($UpdSeqArrSize,3,2) & StringMid($UpdSeqArrSize,1,2))
			$UpdSeqArr = StringMid($record,3+($UpdSeqArrOffset*2),$UpdSeqArrSize*2*2)
			$UpdSeqArrPart0 = StringMid($UpdSeqArr,1,4)
			$UpdSeqArrPart1 = StringMid($UpdSeqArr,5,4)
			$UpdSeqArrPart2 = StringMid($UpdSeqArr,9,4)
			$RecordEnd1 = StringMid($record,1023,4)
			$RecordEnd2 = StringMid($record,2047,4)
			If $RecordEnd1 <> $RecordEnd2 OR $UpdSeqArrPart0 <> $RecordEnd1 Then
				ConsoleWrite("Error: the $MFT record is corrupt" & @CRLF)
				Exit
			EndIf
			$record = StringMid($record,1,1022) & $UpdSeqArrPart1 & StringMid($record,1027,1020) & $UpdSeqArrPart2
			ConsoleWrite("Slack data of record after fixups are applied: " & @CRLF)
			ConsoleWrite(_HexEncode('0x'&StringMid($record,$RecordSlackArray[0]+2)) & @crlf)
		Next
	Next
EndIf

_WinAPI_CloseHandle($hDisk)
_End($Timerstart)
Exit

Func _GetVolumeHandle($TargetDrive)
	Local $hFile
	If @OSBuild >= 6000 And $NeedLock Then
		If StringLeft(@AutoItExe,2) = $TargetDrive Then
			ConsoleWrite("Error: You can't lock the volume that SetMace is run from" & @crlf)
			Exit
		EndIf
		$hFile = _WinAPI_LockVolume($TargetDrive)
		If @error Then
			$hFile = _WinAPI_DismountVolumeMod($TargetDrive)
			If $hFile = 0 Then
				ConsoleWrite("Error: Could not dismount " & $TargetDrive & @CRLF)
				Exit
			EndIf
			$IsDismounted = 1
		Else
			$IsLocked = 1
		EndIf
	Else
		Local $hFile = _WinAPI_CreateFile("\\.\" & $TargetDrive,2,6,7)
		If $hFile = 0 then
			ConsoleWrite("Error: " & _WinAPI_GetLastErrorMessage() & " in CreateFile for: " & "\\.\" & $TargetDrive & @crlf)
			Exit
		EndIf
	EndIf
	Return $hFile
EndFunc

Func _SetMftPayload($hVol,$DiskOffset,$MFTRecordDump,$WrittenSoFar)
	Local $nBytes,$number,$StartByteLocal
;	ConsoleWrite("Dump of original record " & @crlf)
;	ConsoleWrite(_HexEncode($MFTRecordDump) & @crlf)
	$UpdSeqArrOffset = StringMid($MFTRecordDump,11,4)
	$UpdSeqArrOffset = Dec(StringMid($UpdSeqArrOffset,3,2) & StringMid($UpdSeqArrOffset,1,2))
	$UpdSeqArrSize = StringMid($MFTRecordDump,15,4)
	$UpdSeqArrSize = Dec(StringMid($UpdSeqArrSize,3,2) & StringMid($UpdSeqArrSize,1,2))
	$UpdSeqArr = StringMid($MFTRecordDump,3+($UpdSeqArrOffset*2),$UpdSeqArrSize*2*2)
	$UpdSeqArrPart0 = StringMid($UpdSeqArr,1,4)
	$UpdSeqArrPart1 = StringMid($UpdSeqArr,5,4)
	$UpdSeqArrPart2 = StringMid($UpdSeqArr,9,4)
	$RecordEnd1 = StringMid($MFTRecordDump,1023,4)
	$RecordEnd2 = StringMid($MFTRecordDump,2047,4)
	If $RecordEnd1 <> $RecordEnd2 OR $UpdSeqArrPart0 <> $RecordEnd1 Then
		ConsoleWrite("Error: the $MFT record is corrupt" & @CRLF)
		Return 0
	EndIf
	$MFTRecordDump = StringMid($MFTRecordDump,1,1022) & $UpdSeqArrPart1 & StringMid($MFTRecordDump,1027,1020) & $UpdSeqArrPart2 ; fixup
	If $SizeRemaining > $RecordBaseFree-$RecordSlackArray[0] Then
		$AvailableInThisRecord = $RecordBaseFree-$RecordSlackArray[0]
	Else
		$AvailableInThisRecord = $SizeRemaining
	EndIf
	$StartByteLocal = $StartByte*2
	$MftSlack_ChunkNumberHex = _SwapEndian(Hex($MftSlack_ChunkNumber,8))
	$MftSlack_ChunkSize = _SwapEndian(Hex(Int($AvailableInThisRecord/2),4))
	$MFTRecordDump = StringMid($MFTRecordDump,1,$RecordSlackArray[0]+1+$StartByteLocal) & $MftSlack_Signature & $MftSlack_ChunkNumberHex & $MftSlack_ChunkSize & $MftSlack_DataTotalSize & StringMid($TestData,3+$WrittenSoFar,$AvailableInThisRecord) & StringMid($MFTRecordDump,$RecordSlackArray[0]+$AvailableInThisRecord+2)
;	ConsoleWrite("Dump of modified record " & @crlf)
;	ConsoleWrite(_HexEncode($MFTRecordDump) & @crlf)
; fixup
	$someoff = 3+($UpdSeqArrOffset*2)
	$a0 = StringMid($MFTRecordDump,1,$someoff+3)
	$a7 = StringMid($MFTRecordDump,$someoff+12,4)
	$a3 = StringMid($MFTRecordDump,$someoff+16,1023-($someoff+16))
	$a4 = StringMid($MFTRecordDump,1023,4)
	$a5 = StringMid($MFTRecordDump,1027,1020)
	$a6 = StringMid($MFTRecordDump,2047,4)
	$MFTRecordDump = $a0 & $a4 & $a6 & $a7 & $a3 & $UpdSeqArrPart0 & $a5 & $UpdSeqArrPart0
;	ConsoleWrite("Dump of modified record " & @crlf)
;	ConsoleWrite(_HexEncode($MFTRecordDump) & @crlf)
;Put modified MFT entry into new buffer
	Local $tBuffer2 = DllStructCreate("byte[" & 1024 & "]")
	DllStructSetData($tBuffer2,1,$MFTRecordDump)
	_WinAPI_SetFilePointerEx($hVol, $DiskOffset)
	_WinAPI_WriteFile($hVol, DllStructGetPtr($tBuffer2), 1024, $nBytes)
	If _WinAPI_GetLastError() <> 0 Then
		ConsoleWrite("Error: WriteFile returned: " & _WinAPI_GetLastErrorMessage() & @crlf)
		Exit
	Else
		ConsoleWrite("Success writing " & $AvailableInThisRecord/2 & " bytes to record: " & $ref & @crlf)
	EndIf
	$tBuffer2=0
	Return $AvailableInThisRecord
EndFunc

Func _GetMftPayload($hVol,$hOutFile,$DiskOffset,$MFTRecordDump,$FileOffset)
	Local $nBytes,$number,$NewOffset
	$UpdSeqArrOffset = StringMid($MFTRecordDump,11,4)
	$UpdSeqArrOffset = Dec(StringMid($UpdSeqArrOffset,3,2) & StringMid($UpdSeqArrOffset,1,2))
	$UpdSeqArrSize = StringMid($MFTRecordDump,15,4)
	$UpdSeqArrSize = Dec(StringMid($UpdSeqArrSize,3,2) & StringMid($UpdSeqArrSize,1,2))
	$UpdSeqArr = StringMid($MFTRecordDump,3+($UpdSeqArrOffset*2),$UpdSeqArrSize*2*2)
	$UpdSeqArrPart0 = StringMid($UpdSeqArr,1,4)
	$UpdSeqArrPart1 = StringMid($UpdSeqArr,5,4)
	$UpdSeqArrPart2 = StringMid($UpdSeqArr,9,4)
	$RecordEnd1 = StringMid($MFTRecordDump,1023,4)
	$RecordEnd2 = StringMid($MFTRecordDump,2047,4)
	If $RecordEnd1 <> $RecordEnd2 OR $UpdSeqArrPart0 <> $RecordEnd1 Then
		ConsoleWrite("Error: the $MFT record is corrupt" & @CRLF)
		Return 0
	EndIf
	$MFTRecordDump = StringMid($MFTRecordDump,1,1022) & $UpdSeqArrPart1 & StringMid($MFTRecordDump,1027,1020) & $UpdSeqArrPart2 ; fixup
	$SizeRemaining*=2
	$NewOffset = $RecordSlackArray[0]+($StartByte*2)
	If $SizeRemaining > $RecordBaseFree-$RecordSlackArray[0] Then
		$AvailableInThisRecord = $RecordBaseFree-$RecordSlackArray[0]
	Else
		$AvailableInThisRecord = $SizeRemaining
	EndIf
	$MftSlack_SignatureLocal = StringMid($MFTRecordDump,$NewOffset+2,8)
	$MftSlack_ChunkNumber = Dec(_SwapEndian(StringMid($MFTRecordDump,$NewOffset+10,8)))
	$MftSlack_ChunkSize = Dec(_SwapEndian(StringMid($MFTRecordDump,$NewOffset+18,4)))
	If $MftSlack_Signature <> $MftSlack_SignatureLocal Then
;		ConsoleWrite("Error: Wrong signature: " & $MftSlack_SignatureLocal & @crlf)
		Return 0
	EndIf
	If $MftSlack_ChunkNumberPrevious+1 <> $MftSlack_ChunkNumber Then
		ConsoleWrite("Error: Reassembly of fragments out of order (maybe something has been overwritten). " & @crlf)
		Exit
	EndIf
	$MftSlack_ChunkNumberPrevious = $MftSlack_ChunkNumber
	$MftSlack_DataTotalSize = Dec(_SwapEndian(StringMid($MFTRecordDump,$NewOffset+22,8)))
	$MftSlack_RecoveredData = StringMid($MFTRecordDump,$NewOffset+30,$MftSlack_ChunkSize*2)
;	ConsoleWrite("Dump of recovered data " & @crlf)
;	ConsoleWrite(_HexEncode('0x'&$MftSlack_RecoveredData) & @crlf)
;Put modified MFT entry into new buffer
	Local $tBuffer2 = DllStructCreate("byte[" & $MftSlack_ChunkSize & "]")
	DllStructSetData($tBuffer2,1,'0x'&$MftSlack_RecoveredData)
	_WinAPI_WriteFile($hOutFile, DllStructGetPtr($tBuffer2), $MftSlack_ChunkSize, $nBytes)
	If _WinAPI_GetLastError() <> 0 Then
		ConsoleWrite("Error: WriteFile returned: " & _WinAPI_GetLastErrorMessage() & @crlf)
		Exit
	Else
		ConsoleWrite("Success extracting: " & $MftSlack_ChunkSize & " bytes from chunk number: " & $MftSlack_ChunkNumber & " in record: " & $ref & @crlf)
	EndIf
	Return $MftSlack_ChunkSize
EndFunc

Func _CleanMftSlack($hVol,$DiskOffset,$MFTRecordDump)
	Local $nBytes,$number
;	ConsoleWrite("Dump of original record " & @crlf)
;	ConsoleWrite(_HexEncode($MFTRecordDump) & @crlf)
	$UpdSeqArrOffset = StringMid($MFTRecordDump,11,4)
	$UpdSeqArrOffset = Dec(StringMid($UpdSeqArrOffset,3,2) & StringMid($UpdSeqArrOffset,1,2))
	$UpdSeqArrSize = StringMid($MFTRecordDump,15,4)
	$UpdSeqArrSize = Dec(StringMid($UpdSeqArrSize,3,2) & StringMid($UpdSeqArrSize,1,2))
	$UpdSeqArr = StringMid($MFTRecordDump,3+($UpdSeqArrOffset*2),$UpdSeqArrSize*2*2)
	$UpdSeqArrPart0 = StringMid($UpdSeqArr,1,4)
	$UpdSeqArrPart1 = StringMid($UpdSeqArr,5,4)
	$UpdSeqArrPart2 = StringMid($UpdSeqArr,9,4)
	$RecordEnd1 = StringMid($MFTRecordDump,1023,4)
	$RecordEnd2 = StringMid($MFTRecordDump,2047,4)
	If $RecordEnd1 <> $RecordEnd2 OR $UpdSeqArrPart0 <> $RecordEnd1 Then
		ConsoleWrite("Error: the $MFT record is corrupt" & @CRLF)
		Return 0
	EndIf
	$MFTRecordDump = StringMid($MFTRecordDump,1,1022) & $UpdSeqArrPart1 & StringMid($MFTRecordDump,1027,1020) & $UpdSeqArrPart2 ; fixup
	$AvailableInThisRecord = 2049-$RecordSlackArray[0]-$StartByte
	$MftSlack_ChunkNumberHex = _SwapEndian(Hex($MftSlack_ChunkNumber,8))
	$MftSlack_ChunkSize = _SwapEndian(Hex(Int($AvailableInThisRecord/2),4))

	Local $emptybuff = DllStructCreate("byte[" & $AvailableInThisRecord/2 & "]")
	$emptydata = DllStructGetData($emptybuff,1)
	$MFTRecordDump = StringMid($MFTRecordDump,1,$RecordSlackArray[0]+1) & StringMid($emptydata,3)
;	ConsoleWrite("Dump of modified record " & @crlf)
;	ConsoleWrite(_HexEncode($MFTRecordDump) & @crlf)
; fixup
	$someoff = 3+($UpdSeqArrOffset*2)
	$a0 = StringMid($MFTRecordDump,1,$someoff+3)
	$a7 = StringMid($MFTRecordDump,$someoff+12,4)
	$a3 = StringMid($MFTRecordDump,$someoff+16,1023-($someoff+16))
	$a4 = StringMid($MFTRecordDump,1023,4)
	$a5 = StringMid($MFTRecordDump,1027,1020)
	$a6 = StringMid($MFTRecordDump,2047,4)
	$MFTRecordDump = $a0 & $a4 & $a6 & $a7 & $a3 & $UpdSeqArrPart0 & $a5 & $UpdSeqArrPart0
;	ConsoleWrite("Dump of modified record " & @crlf)
;	ConsoleWrite(_HexEncode($MFTRecordDump) & @crlf)
;Put modified MFT entry into new buffer
	Local $tBuffer2 = DllStructCreate("byte[" & 1024 & "]")
	DllStructSetData($tBuffer2,1,$MFTRecordDump)
	_WinAPI_SetFilePointerEx($hVol, $DiskOffset)
	_WinAPI_WriteFile($hVol, DllStructGetPtr($tBuffer2), 1024, $nBytes)
	If _WinAPI_GetLastError() <> 0 Then
		ConsoleWrite("Error: WriteFile returned: " & _WinAPI_GetLastErrorMessage() & @crlf)
		Exit
	Else
;		ConsoleWrite("Success cleaning " & $AvailableInThisRecord/2 & " slack bytes in record: " & $ref & @crlf)
	EndIf
	$tBuffer2=0
EndFunc

Func _DecodeDataQEntry($attr)		;processes data attribute
   $NonResidentFlag = StringMid($attr,17,2)
   $NameLength = Dec(StringMid($attr,19,2))
   $NameOffset = Dec(_SwapEndian(StringMid($attr,21,4)))
   If $NameLength > 0 Then		;must be ADS
	  $ADS_Name = _UnicodeHexToStr(StringMid($attr,$NameOffset*2 + 1,$NameLength*4))
	  $ADS_Name = $FN_FileName & "[ADS_" & $ADS_Name & "]"
   Else
	  $ADS_Name = $FN_FileName		;need to preserve $FN_FileName
   EndIf
   $Flags = StringMid($attr,25,4)
   If BitAND($Flags,"0100") Then $IsCompressed = 1
   If BitAND($Flags,"0080") Then $IsSparse = 1
   If $NonResidentFlag = '01' Then
	  $DATA_Clusters = Dec(_SwapEndian(StringMid($attr,49,16)),2) - Dec(_SwapEndian(StringMid($attr,33,16)),2) + 1
	  $DATA_RealSize = Dec(_SwapEndian(StringMid($attr,97,16)),2)
	  $DATA_InitSize = Dec(_SwapEndian(StringMid($attr,113,16)),2)
	  $Offset = Dec(_SwapEndian(StringMid($attr,65,4)))
	  $DataRun = StringMid($attr,$Offset*2+1,(StringLen($attr)-$Offset)*2)
   ElseIf $NonResidentFlag = '00' Then
	  $DATA_LengthOfAttribute = Dec(_SwapEndian(StringMid($attr,33,8)),2)
	  $Offset = Dec(_SwapEndian(StringMid($attr,41,4)))
	  $DataRun = StringMid($attr,$Offset*2+1,$DATA_LengthOfAttribute*2)
   EndIf
EndFunc

Func _DecodeMFTRecord($MFTEntry,$MFTMode)
Local $DATA_Number
Global $RecordSlackArray[1]
If $IsFirstRun Then Global $DataQ[1]
$UpdSeqArrOffset = Dec(_SwapEndian(StringMid($MFTEntry,11,4)))
$UpdSeqArrSize = Dec(_SwapEndian(StringMid($MFTEntry,15,4)))
$UpdSeqArr = StringMid($MFTEntry,3+($UpdSeqArrOffset*2),$UpdSeqArrSize*2*2)
$UpdSeqArrPart0 = StringMid($UpdSeqArr,1,4)
$UpdSeqArrPart1 = StringMid($UpdSeqArr,5,4)
$UpdSeqArrPart2 = StringMid($UpdSeqArr,9,4)
$RecordEnd1 = StringMid($MFTEntry,1023,4)
$RecordEnd2 = StringMid($MFTEntry,2047,4)
If $UpdSeqArrPart0 <> $RecordEnd1 OR $UpdSeqArrPart0 <> $RecordEnd2 Then
	ConsoleWrite("Error: the $MFT record is corrupt" & @CRLF)
	Return SetError(1,0,0)
 Else
	$MFTEntry = StringMid($MFTEntry,1,1022) & $UpdSeqArrPart1 & StringMid($MFTEntry,1027,1020) & $UpdSeqArrPart2
EndIf

$AttributeOffset = (Dec(StringMid($MFTEntry,43,2))*2)+3

While 1
	$AttributeType = StringMid($MFTEntry,$AttributeOffset,8)
	$AttributeSize = StringMid($MFTEntry,$AttributeOffset+8,8)
	$AttributeSize = Dec(_SwapEndian($AttributeSize),2)
	Select
		Case $AttributeType = $STANDARD_INFORMATION
			$AttributeOffset += $AttributeSize*2
			ContinueLoop
		Case $AttributeType = $ATTRIBUTE_LIST
			$AttributeOffset += $AttributeSize*2
			ContinueLoop
   		Case $AttributeType = $FILE_NAME
			$AttributeOffset += $AttributeSize*2
			ContinueLoop
		Case $AttributeType = $OBJECT_ID
			$AttributeOffset += $AttributeSize*2
			ContinueLoop
		Case $AttributeType = $SECURITY_DESCRIPTOR
			$AttributeOffset += $AttributeSize*2
			ContinueLoop
		Case $AttributeType = $VOLUME_NAME
			$AttributeOffset += $AttributeSize*2
			ContinueLoop
		Case $AttributeType = $VOLUME_INFORMATION
			$AttributeOffset += $AttributeSize*2
			ContinueLoop
		Case $AttributeType = $DATA
			If $IsFirstRun Then
				$DATA_Number += 1
				_ArrayAdd($DataQ, StringMid($MFTEntry,$AttributeOffset,$AttributeSize*2))
			Else
				$AttributeOffset += $AttributeSize*2
				ContinueLoop
			EndIf
		Case $AttributeType = $INDEX_ROOT
			$AttributeOffset += $AttributeSize*2
			ContinueLoop
		Case $AttributeType = $INDEX_ALLOCATION
			$AttributeOffset += $AttributeSize*2
			ContinueLoop
		Case $AttributeType = $BITMAP
			$AttributeOffset += $AttributeSize*2
			ContinueLoop
		Case $AttributeType = $REPARSE_POINT
			$AttributeOffset += $AttributeSize*2
			ContinueLoop
		Case $AttributeType = $EA_INFORMATION
			$AttributeOffset += $AttributeSize*2
			ContinueLoop
		Case $AttributeType = $EA
			$AttributeOffset += $AttributeSize*2
			ContinueLoop
		Case $AttributeType = $PROPERTY_SET
			$AttributeOffset += $AttributeSize*2
			ContinueLoop
		Case $AttributeType = $LOGGED_UTILITY_STREAM
			$AttributeOffset += $AttributeSize*2
			ContinueLoop
		Case $AttributeType = $ATTRIBUTE_END_MARKER
			ExitLoop
	EndSelect
	$AttributeOffset += $AttributeSize*2
WEnd
If Not $IsFirstRun Then
	$AttributeOffset+=6
	$RecordSlackArray[0]=Int($AttributeOffset)
EndIf
EndFunc

Func _ExtractDataRuns()
	$r=UBound($RUN_Clusters)
	$i=1
	$RUN_VCN[0] = 0
	$BaseVCN = $RUN_VCN[0]
	If $DataRun = "" Then $DataRun = "00"
	Do
		$RunListID = StringMid($DataRun,$i,2)
		If $RunListID = "00" Then ExitLoop
		$i += 2
		$RunListClustersLength = Dec(StringMid($RunListID,2,1))
		$RunListVCNLength = Dec(StringMid($RunListID,1,1))
		$RunListClusters = Dec(_SwapEndian(StringMid($DataRun,$i,$RunListClustersLength*2)),2)
		$i += $RunListClustersLength*2
		$RunListVCN = _SwapEndian(StringMid($DataRun, $i, $RunListVCNLength*2))
		;next line handles positive or negative move
		$BaseVCN += Dec($RunListVCN,2)-(($r>1) And (Dec(StringMid($RunListVCN,1,1))>7))*Dec(StringMid("10000000000000000",1,$RunListVCNLength*2+1),2)
		If $RunListVCN <> "" Then
			$RunListVCN = $BaseVCN
		Else
			$RunListVCN = 0			;$RUN_VCN[$r-1]		;0
		EndIf
		If (($RunListVCN=0) And ($RunListClusters>16) And (Mod($RunListClusters,16)>0)) Then
		 ;may be sparse section at end of Compression Signature
			_ArrayAdd($RUN_Clusters,Mod($RunListClusters,16))
			_ArrayAdd($RUN_VCN,$RunListVCN)
			$RunListClusters -= Mod($RunListClusters,16)
			$r += 1
		ElseIf (($RunListClusters>16) And (Mod($RunListClusters,16)>0)) Then
		 ;may be compressed data section at start of Compression Signature
			_ArrayAdd($RUN_Clusters,$RunListClusters-Mod($RunListClusters,16))
			_ArrayAdd($RUN_VCN,$RunListVCN)
			$RunListVCN += $RUN_Clusters[$r]
			$RunListClusters = Mod($RunListClusters,16)
			$r += 1
		EndIf
	  ;just normal or sparse data
		_ArrayAdd($RUN_Clusters,$RunListClusters)
		_ArrayAdd($RUN_VCN,$RunListVCN)
		$r += 1
		$i += $RunListVCNLength*2
	Until $i > StringLen($DataRun)
EndFunc

Func _FindFileMFTRecord($TargetFile)
	Local $nBytes, $TmpOffset, $Counter, $Counter2, $RecordJumper, $TargetFileDec, $RecordsTooMuch, $RetVal[2], $Final, $i=0
	$tBuffer = DllStructCreate("byte[" & $MFT_Record_Size & "]")
	$hFile = _WinAPI_CreateFile("\\.\" & $TargetDrive, 2, 6, 6)
	If $hFile = 0 Then
		ConsoleWrite("Error in function CreateFile: " & _WinAPI_GetLastErrorMessage() & @CRLF)
		_WinAPI_CloseHandle($hFile)
		Return SetError(1,0,0)
	EndIf
	$TargetFile = _DecToLittleEndian($TargetFile)
	$TargetFileDec = Dec(_SwapEndian($TargetFile),2)
	For $i = 1 To UBound($MFT_RUN_Clusters)-1
		$CurrentClusters = $MFT_RUN_Clusters[$i]
		$RecordsInCurrentRun = ($CurrentClusters*$SectorsPerCluster)/2
		$Counter+=$RecordsInCurrentRun
		If $Counter>$TargetFileDec Then
			ExitLoop
		EndIf
	Next
	$TryAt = $Counter-$RecordsInCurrentRun
	$TryAtArrIndex = $i
	$RecordsPerCluster = $SectorsPerCluster/2
	Do
		$RecordJumper+=$RecordsPerCluster
		$Counter2+=1
		$Final = $TryAt+$RecordJumper
	Until $Final>=$TargetFileDec
	$RecordsTooMuch = $Final-$TargetFileDec
	_WinAPI_SetFilePointerEx($hFile, $ImageOffset+$MFT_RUN_VCN[$i]*$BytesPerCluster+($Counter2*$BytesPerCluster)-($RecordsTooMuch*1024), $FILE_BEGIN)
	_WinAPI_ReadFile($hFile, DllStructGetPtr($tBuffer), $MFT_Record_Size, $nBytes)
	$record = DllStructGetData($tBuffer, 1)
	If StringMid($record,91,8) = $TargetFile Then
		$TmpOffset = DllCall('kernel32.dll', 'int', 'SetFilePointerEx', 'ptr', $hFile, 'int64', 0, 'int64*', 0, 'dword', 1)
;		ConsoleWrite("Record number: " & Dec(_SwapEndian($TargetFile),2) & " found at disk offset: 0x" & Hex($TmpOffset[3]-1024) & @CRLF)
		_WinAPI_CloseHandle($hFile)
		$RetVal[0] = $TmpOffset[3]-1024
		$RetVal[1] = $record
		Return $RetVal
	Else
		_WinAPI_CloseHandle($hFile)
		Return ""
	EndIf
EndFunc

Func _FindMFT($TargetFile)
	Local $nBytes;, $MFT_Record_Size=1024
	$tBuffer = DllStructCreate("byte[" & $MFT_Record_Size & "]")
	$hFile = _WinAPI_CreateFile("\\.\" & $TargetDrive, 2, 2, 7)
	If $hFile = 0 Then
		ConsoleWrite("Error in function CreateFile when trying to locate MFT: " & _WinAPI_GetLastErrorMessage() & @CRLF)
		Return SetError(1,0,0)
	EndIf
	_WinAPI_SetFilePointerEx($hFile, $ImageOffset+$MFT_Offset, $FILE_BEGIN)
	_WinAPI_ReadFile($hFile, DllStructGetPtr($tBuffer), $MFT_Record_Size, $nBytes)
	_WinAPI_CloseHandle($hFile)
	$record = DllStructGetData($tBuffer, 1)
	If NOT StringMid($record,1,8) = '46494C45' Then
		ConsoleWrite("MFT record signature not found. "& @crlf)
		Return ""
	EndIf
	If StringMid($record,47,4) = "0100" AND Dec(_SwapEndian(StringMid($record,91,8))) = $TargetFile Then
;		ConsoleWrite("MFT record found" & @CRLF)
		Return $record		;returns record for MFT
	EndIf
	ConsoleWrite("MFT record not found" & @CRLF)
	Return ""
EndFunc

Func _DecToLittleEndian($DecimalInput)
	Return _SwapEndian(Hex($DecimalInput,8))
EndFunc


Func _UnicodeHexToStr($FileName)
	$str = ""
	For $i = 1 To StringLen($FileName) Step 4
		$str &= ChrW(Dec(_SwapEndian(StringMid($FileName, $i, 4))))
	Next
	Return $str
EndFunc

Func _DebugOut($text, $var)
	ConsoleWrite("Debug output for " & $text & @CRLF)
	For $i=1 To StringLen($var) Step 32
		$str=""
		For $n=0 To 15
			$str &= StringMid($var, $i+$n*2, 2) & " "
			if $n=7 then $str &= "- "
		Next
		ConsoleWrite($str & @CRLF)
	Next
EndFunc

Func _ReadBootSector($TargetDrive)
	Local $nbytes
	$tBuffer=DllStructCreate("byte[512]")
	$hFile = _WinAPI_CreateFile("\\.\" & $TargetDrive,2,2,7)
	If $hFile = 0 then
		ConsoleWrite("Error in function CreateFile: " & _WinAPI_GetLastErrorMessage() & " for: " & "\\.\" & $TargetDrive & @crlf)
		Return SetError(1,0,0)
	EndIf
	_WinAPI_SetFilePointerEx($hFile, $ImageOffset, $FILE_BEGIN)
	$read = _WinAPI_ReadFile($hFile, DllStructGetPtr($tBuffer), 512, $nBytes)
	If $read = 0 then
		ConsoleWrite("Error in function ReadFile: " & _WinAPI_GetLastErrorMessage() & " for: " & "\\.\" & $TargetDrive & @crlf)
		Return
	EndIf
	_WinAPI_CloseHandle($hFile)
   ; Good starting point from KaFu & trancexx at the AutoIt forum
	$tBootSectorSections = DllStructCreate("align 1;" & _
								"byte Jump[3];" & _
								"char SystemName[8];" & _
								"ushort BytesPerSector;" & _
								"ubyte SectorsPerCluster;" & _
								"ushort ReservedSectors;" & _
								"ubyte[3];" & _
								"ushort;" & _
								"ubyte MediaDescriptor;" & _
								"ushort;" & _
								"ushort SectorsPerTrack;" & _
								"ushort NumberOfHeads;" & _
								"dword HiddenSectors;" & _
								"dword;" & _
								"dword;" & _
								"int64 TotalSectors;" & _
								"int64 LogicalClusterNumberforthefileMFT;" & _
								"int64 LogicalClusterNumberforthefileMFTMirr;" & _
								"dword ClustersPerFileRecordSegment;" & _
								"dword ClustersPerIndexBlock;" & _
								"int64 NTFSVolumeSerialNumber;" & _
								"dword Checksum", DllStructGetPtr($tBuffer))

	$BytesPerSector = DllStructGetData($tBootSectorSections, "BytesPerSector")
	$SectorsPerCluster = DllStructGetData($tBootSectorSections, "SectorsPerCluster")
	$BytesPerCluster = $BytesPerSector * $SectorsPerCluster
	$ClustersPerFileRecordSegment = DllStructGetData($tBootSectorSections, "ClustersPerFileRecordSegment")
	$LogicalClusterNumberforthefileMFT = DllStructGetData($tBootSectorSections, "LogicalClusterNumberforthefileMFT")
	$MFT_Offset = $BytesPerCluster * $LogicalClusterNumberforthefileMFT
	If $ClustersPerFileRecordSegment > 127 Then
		$MFT_Record_Size = 2 ^ (256 - $ClustersPerFileRecordSegment)
	Else
		$MFT_Record_Size = $BytesPerCluster * $ClustersPerFileRecordSegment
	EndIf
EndFunc

Func _HexEncode($bInput)
    Local $tInput = DllStructCreate("byte[" & BinaryLen($bInput) & "]")
    DllStructSetData($tInput, 1, $bInput)
    Local $a_iCall = DllCall("crypt32.dll", "int", "CryptBinaryToString", _
            "ptr", DllStructGetPtr($tInput), _
            "dword", DllStructGetSize($tInput), _
            "dword", 11, _
            "ptr", 0, _
            "dword*", 0)

    If @error Or Not $a_iCall[0] Then
        Return SetError(1, 0, "")
    EndIf

    Local $iSize = $a_iCall[5]
    Local $tOut = DllStructCreate("char[" & $iSize & "]")

    $a_iCall = DllCall("crypt32.dll", "int", "CryptBinaryToString", _
            "ptr", DllStructGetPtr($tInput), _
            "dword", DllStructGetSize($tInput), _
            "dword", 11, _
            "ptr", DllStructGetPtr($tOut), _
            "dword*", $iSize)

    If @error Or Not $a_iCall[0] Then
        Return SetError(2, 0, "")
    EndIf

    Return SetError(0, 0, DllStructGetData($tOut, 1))

EndFunc  ;==>_HexEncode

Func _End($begin)
	Local $timerdiff = TimerDiff($begin)
	$timerdiff = Round(($timerdiff / 1000), 2)
	ConsoleWrite("Job took " & $timerdiff & " seconds" & @CRLF)
EndFunc

Func NT_SUCCESS($status)
    If 0 <= $status And $status <= 0x7FFFFFFF Then
        Return True
    Else
        Return False
    EndIf
EndFunc

Func _DecodeNameQ($NameQ)
	For $name = 1 To UBound($NameQ) - 1
		$NameString = $NameQ[$name]
		If $NameString = "" Then ContinueLoop
		$FN_AllocSize = Dec(_SwapEndian(StringMid($NameString,129,16)),2)
		$FN_RealSize = Dec(_SwapEndian(StringMid($NameString,145,16)),2)
		$FN_NameLength = Dec(StringMid($NameString,177,2))
		$FN_NameSpace = StringMid($NameString,179,2)
		Select
			Case $FN_NameSpace = '00'
				$FN_NameSpace = 'POSIX'
			Case $FN_NameSpace = '01'
				$FN_NameSpace = 'WIN32'
			Case $FN_NameSpace = '02'
				$FN_NameSpace = 'DOS'
			Case $FN_NameSpace = '03'
				$FN_NameSpace = 'DOS+WIN32'
			Case Else
				$FN_NameSpace = 'UNKNOWN'
		EndSelect
		$FN_FileName = StringMid($NameString,181,$FN_NameLength*4)
		$FN_FileName = _UnicodeHexToStr($FN_FileName)
		If StringLen($FN_FileName) <> $FN_NameLength Then $INVALID_FILENAME = 1
	Next
	Return
EndFunc

Func _WinAPI_LockVolume($iVolume)
	$hFile = _WinAPI_CreateFileEx('\\.\' & $iVolume, 3, BitOR($GENERIC_READ,$GENERIC_WRITE), 0x7)
	If Not $hFile Then
		Return SetError(1, 0, 0)
	EndIf
	_WinAPI_FlushFileBuffers($hFile)
	Local $Ret = DllCall('kernel32.dll', 'int', 'DeviceIoControl', 'ptr', $hFile, 'dword', $FSCTL_LOCK_VOLUME, 'ptr', 0, 'dword', 0, 'ptr', 0, 'dword', 0, 'dword*', 0, 'ptr', 0)
	If (@error) Or (Not $Ret[0]) Then
		$Ret = 0
	EndIf
	If Not IsArray($Ret) Then
		Return SetError(2, 0, 0)
	EndIf
	Return $hFile
EndFunc   ;==>_WinAPI_LockVolume

Func _WinAPI_UnLockVolume($hFile)
	If Not $hFile Then
		ConsoleWrite("Error in _WinAPI_CreateFileEx when unlocking." & @CRLF)
		Return SetError(1, 0, 0)
	EndIf
	Local $Ret = DllCall('kernel32.dll', 'int', 'DeviceIoControl', 'ptr', $hFile, 'dword', $FSCTL_UNLOCK_VOLUME, 'ptr', 0, 'dword', 0, 'ptr', 0, 'dword', 0, 'dword*', 0, 'ptr', 0)
	If (@error) Or (Not $Ret[0]) Then
		$Ret = 0
	EndIf
	If Not IsArray($Ret) Then
		Return SetError(2, 0, 0)
	EndIf
	Return $Ret[0]
EndFunc   ;==>_WinAPI_UnLockVolume

Func _WinAPI_DismountVolume($hFile)
	If Not $hFile Then
		ConsoleWrite("Error in _WinAPI_CreateFileEx when dismounting." & @CRLF)
		Return SetError(1, 0, 0)
	EndIf
	Local $Ret = DllCall('kernel32.dll', 'int', 'DeviceIoControl', 'ptr', $hFile, 'dword', $FSCTL_DISMOUNT_VOLUME, 'ptr', 0, 'dword', 0, 'ptr', 0, 'dword', 0, 'dword*', 0, 'ptr', 0)
	If (@error) Or (Not $Ret[0]) Then
		$Ret = 0
	EndIf
	If Not IsArray($Ret) Then
		Return SetError(2, 0, 0)
	EndIf
	Return $Ret[0]
EndFunc   ;==>_WinAPI_DismountVolume

Func _WinAPI_DismountVolumeMod($iVolume)
	$hFile = _WinAPI_CreateFileEx('\\.\' & $iVolume, 3, BitOR($GENERIC_READ,$GENERIC_WRITE), 0x7)
	If Not $hFile Then
		ConsoleWrite("Error in _WinAPI_CreateFileEx when dismounting." & @CRLF)
		Return SetError(1, 0, 0)
	EndIf
	_WinAPI_FlushFileBuffers($hFile)
	Local $Ret = DllCall('kernel32.dll', 'int', 'DeviceIoControl', 'ptr', $hFile, 'dword', $FSCTL_DISMOUNT_VOLUME, 'ptr', 0, 'dword', 0, 'ptr', 0, 'dword', 0, 'dword*', 0, 'ptr', 0)
	If (@error) Or (Not $Ret[0]) Then
		Return SetError(3, 0, 0)
	EndIf
	If Not IsArray($Ret) Then
		Return SetError(2, 0, 0)
	EndIf
	Return $hFile
EndFunc   ;==>_WinAPI_DismountVolumeMod

Func _ShiftEndian($aa)
	Local $ab, $ac
	$abc = StringLen($aa)
	If NOT IsInt($abc/2) Then
		$aa = '0' & $aa
	EndIf
	For $i = 1 To $abc Step 2
		$ab = StringMid($aa,$abc-$i,2)
		$ac &= $ab
	Next
	Return $ac
EndFunc

Func _validate_parameters()
	Local $FileAttrib
	If $cmdline[0] <> 3 And $cmdline[0] <> 5 And $cmdline[0] <> 6 Then
		ConsoleWrite("Error: Incorrect parameters supplied" & @CRLF & @CRLF)
		_PrintHelp()
		Exit
	EndIf
	If $cmdline[0] = 3 Then
		If $cmdline[1] <> '-dump' Then
			ConsoleWrite("Error: Incorrect parameters supplied" & @CRLF & @CRLF)
			_PrintHelp()
			Exit
		EndIf
		If DriveGetFileSystem($cmdline[2]&"\") <> 'NTFS' Then
			ConsoleWrite("Error: Filesystem not NTFS on: " & $cmdline[2] & @CRLF)
			Exit
		EndIf
		If StringIsDigit($cmdline[3]) <> 1  Then
			ConsoleWrite("Error: Ref was not valid: " & $cmdline[3] & @CRLF)
			Exit
		EndIf
		$DoDump = 1
		$TargetDrive = $cmdline[2]
		$StartRef = $cmdline[3]
	EndIf
	If $cmdline[0] = 5 Then
		If $cmdline[1] <> '-clean' And $cmdline[1] <> '-check' Then
			ConsoleWrite("Error: Incorrect parameters supplied" & @CRLF & @CRLF)
			_PrintHelp()
			Exit
		EndIf
		If DriveGetFileSystem($cmdline[2]&"\") <> 'NTFS' Then
			ConsoleWrite("Error: Filesystem not NTFS on: " & $cmdline[2] & @CRLF)
			Exit
		EndIf
		If StringIsDigit($cmdline[3]) <> 1 And $cmdline[3] <> "-" Then
			ConsoleWrite("Error: StartRef was not valid: " & $cmdline[3] & @CRLF)
			Exit
		EndIf
		If StringIsDigit($cmdline[4]) <> 1 And $cmdline[4] <> "-" Then
			ConsoleWrite("Error: EndRef was not valid: " & $cmdline[4] & @CRLF)
			Exit
		EndIf
		If StringIsDigit($cmdline[3]) And StringIsDigit($cmdline[4]) And Int($cmdline[4]) < Int($cmdline[3]) Then
			ConsoleWrite("Error: EndRef must be higher than StartRef" & @CRLF)
			Exit
		EndIf
		If StringIsDigit($cmdline[5]) <> 1 Then
			ConsoleWrite("Error: StartByte must be integer" & @CRLF)
			Exit
		EndIf
		$TargetDrive = $cmdline[2]
		$StartRef = $cmdline[3]
		$EndRef = $cmdline[4]
		$StartByte = Int($cmdline[5])
		If $cmdline[1] = '-clean' Then $DoClean=1
		If $cmdline[1] = '-check' Then $DoCheck=1
	EndIf
	If $cmdline[0] = 6 Then
		If $cmdline[1] <> '-hide' And $cmdline[1] <> '-extract' Then
			ConsoleWrite("Error: Incorrect parameters supplied" & @CRLF & @CRLF)
			_PrintHelp()
			Exit
		EndIf
		If Not StringIsXDigit($cmdline[5]) Or StringLen($cmdline[5]) <> 8 Then
			ConsoleWrite("Error: Signature not 4 bytes in hex" & @CRLF & @CRLF)
			_PrintHelp()
			Exit
		EndIf
		If Not StringIsDigit($cmdline[4]) Then
			ConsoleWrite("Error: StartRef not a digit" & @CRLF & @CRLF)
			_PrintHelp()
			Exit
		EndIf
		If DriveGetFileSystem($cmdline[3]&"\") <> 'NTFS' Then
			ConsoleWrite("Error: Filesystem not NTFS on: " & $cmdline[3] & @CRLF)
			Exit
		EndIf
		If $cmdline[1] = '-hide' Then
			If FileExists($cmdline[2]) <> 1 Then
				ConsoleWrite("Error: File not found: " & $cmdline[2] & @CRLF & @CRLF)
				_PrintHelp()
				Exit
			EndIf
			$FileAttrib = FileGetAttrib($cmdline[2])
			If @error Or $FileAttrib="" Then
				ConsoleWrite("Error: Could not retrieve file attributes" & @CRLF & @CRLF)
				_PrintHelp()
				Exit
			EndIf
			If $FileAttrib = "D" Then
				ConsoleWrite("Error: Hiding a directory makes no sense" & @CRLF & @CRLF)
				_PrintHelp()
				Exit
			EndIf
		EndIf
		If StringIsDigit($cmdline[6]) <> 1 Then
			ConsoleWrite("Error: StartByte must be integer" & @CRLF)
			Exit
		EndIf
		If Int($cmdline[6]) > 1024 Or Int($cmdline[6]) < 0 Then
			ConsoleWrite("Error: StartByte not in valid range" & @CRLF)
			Exit
		EndIf
		$TargetDrive = $cmdline[3]
		$StartByte = $cmdline[6]
		If $cmdline[1] = '-hide' Then $DoHide=1
		If $cmdline[1] = '-extract' Then $DoExtract=1
	EndIf
EndFunc

Func _SwapEndian($iHex)
	Return StringMid(Binary(Dec($iHex,2)),3, StringLen($iHex))
EndFunc

Func _PrintHelp()
	ConsoleWrite("Syntax:" & @CRLF)
	ConsoleWrite('StegoMft.exe -hide InputFile TargetVolume StartRef Signature StartByte' & @CRLF)
	ConsoleWrite('StegoMft.exe -extract OutputFile TargetVolume StartRef Signature StartByte' & @CRLF)
	ConsoleWrite('StegoMft.exe -check TargetVolume StartRef EndRef StartByte' & @CRLF)
	ConsoleWrite('StegoMft.exe -clean TargetVolume StartRef EndRef StartByte' & @CRLF)
	ConsoleWrite('StegoMft.exe -dump TargetVolume Ref' & @CRLF)
	ConsoleWrite("" & @CRLF)
	ConsoleWrite("Examples:" & @CRLF)
	ConsoleWrite("" & @CRLF)
	ConsoleWrite("Hiding inputfile.ext in $MFT from record number 666 at volume D: with signature 11223344 starting at slack byte 0" & @CRLF)
	ConsoleWrite('StegoMft.exe -hide c:\inputfile.ext D: 666 11223344 0' & @CRLF)
	ConsoleWrite("" & @CRLF)
	ConsoleWrite("Extracting hidden data from volume D: starting from record number 777 and signature 88888888 starting at slack byte 10 to outputfile.ext:" & @CRLF)
	ConsoleWrite('StegoMft.exe -extract c:\outputfile D: 777 88888888 10' & @CRLF)
	ConsoleWrite("" & @CRLF)
	ConsoleWrite("Check number of record slack bytes in $MFT starting at slack byte 20 on volume D:" & @CRLF)
	ConsoleWrite('StegoMft.exe -check D: - - 20' & @CRLF)
	ConsoleWrite("" & @CRLF)
	ConsoleWrite("Check number of record slack bytes in $MFT records 345-350 starting at slack byte 10 on volume D:" & @CRLF)
	ConsoleWrite('StegoMft.exe -check D: 345 350 10' & @CRLF)
	ConsoleWrite("" & @CRLF)
	ConsoleWrite("Overwrite all record slack in $MFT at volume D:" & @CRLF)
	ConsoleWrite('StegoMft.exe -clean D: - - 0' & @CRLF)
	ConsoleWrite("" & @CRLF)
	ConsoleWrite("Overwrite record slack from byte 4 in $MFT records 200-300 at volume D:" & @CRLF)
	ConsoleWrite('StegoMft.exe -clean D: 200 300 4' & @CRLF)
	ConsoleWrite("" & @CRLF)
	ConsoleWrite("Dump to console the record slack in record 50 at volume D:" & @CRLF)
	ConsoleWrite('StegoMft.exe -dump D: 50' & @CRLF)
	ConsoleWrite("" & @CRLF)
EndFunc
