StegoMft
========

This is a PoC showing how it is possible to hide data within $MFT. The tool utilizes the record slack, which is the leftover in record after the header and the attributes are defined. Usually a record is 1024 bytes, but in the later nt6.2 (Windows 8/2012) you have an option to define it as higher. The end marker of a given record is always FFFFFFFF and can easily be spotted. The data beyond that are ignored, with the exception of the fixup values (the last 2 bytes of every sector within a record). So this unused space can be used to store data.

The amount of data that can be stored within $MFT is very limited. A very rough estimate is around 40% of its total size, and this obviously varies from volume to volume. The type or content of a record does not matter at all. Record slack is still unused and ignored by the system. However, if a file gets deleted, and a new file takes over a given record, then depending on its size, the record slack may be higher or lower, depending on the number of attributes and the content of the attributes. So data hidden in record slack, may become overwritten if the new file takes up more space in the record than the previous file did.

The tool supports 5 modes:
-hide (writes the data)
-extract (extract the data)
-check (estimates record slack)
-clean (wipes record slack)
-dump (dump raw data to console)

See explanation at the bottom for syntax and example usage.

You can run the tool with the -check switch to retrieve the exact MB value for how much record slack there is in the $MFT of a volume.

For now it is required that the volume is mounted.

Since it is very limited how much data can be hidden in 1 record, the tool supports spreading data across records. To aid in the re-assembly of the data, there is a special header prepended to the hidden data fragments. It is 14 bytes like this:

- 4 byte signature of choice
- 4 byte value indicating the fragment number
- 2 byte value indicating the current fragment size
- 4 byte value indicating the total size of the hidden data with this signature

This is a minimum header in order to distinguish fragments of different files, and in order to detect if all fragments are found. No fancy integrity check is performed.

In order to be able to hide any data in a record, there must be a minimum of 15 bytes of record slack, since the header takes 14 bytes. There is implemented a lower limit of 24 (24-14=10) bytes required in order to write, in order to save a little bit time. The -check switch accounts for the header size, so the value you get is the true number of what can be hidden with this tool. On one of my test machines, Windows 7 x64 and a volume with 592640 records, the tool identified 280 MB of record slack in 176 seconds.

The hiding of the data is currently very slow, for many reasons. A 1 MB file took me 30 seconds to hide, whereas extraction took 2 seconds! Hiding a 10 MB file may take more than 10 minutes (it becomes slower with larger inputfile sizes), so preferrably don't test a large sized files unless you have plenty of time. When hiding data with the -hide switch you need to specify inputfile, target volume, start ref, signature and startbyte. The start ref is the first record number that will hold the hidden data. The lowest is 0 which is $MFT itself. The signature is 4 bytes of hex values. If a record without any record slack is hit, it will be ignored and just print an innocent error message, although it is really just a verbose message.

Likewise the -extract switch will need as parameters an outputfile, target volume, start ref, signature and startbyte. The start ref, is just to speed up extraction by skipping the parsing of certain records. If you forgot the start ref, just specify 0 and scanning will start from record 0. The signature is needed to identify the correct data.

The -clean switch is for wiping out record slack in any record. You can choose individual records or range of records, as well as the startbyte to wipe from. For instance you can wipe the slack in records 3000-3500 from startbyte 32. Or you can wipe all record slack in an individual record. On a test VM with Windows 7 x64 and a 60 GB volume with an $MFT comprising 360960 records, wiping all record slack in the entire $MFT took exactly 7 minutes.

The -dump switch is quickly displaying how a record looks like. The first chunk is the original record. The second chunk is the record slack after fixups have been applied. This switch only works on individual records.

Testing has so far only been performed on Windows 7 x64.


Warning
Because of the way the tool works it should be regarded as highly experimental and provided for educational purposes. The tool writes a modifed record back to disk, and will internally resolve the layout of $MFT, and how a record should be modified. It thus bypasses security imposed by the filesystem, and does very risky write operations on the disk. With the introduction of Vista/nt6.x new security measures where implemented to restrict such direct disk writes to the filesystem, and it became needed to lock/dismount the volume before any such writes could occur. For that reason it obviously is not possible to perform direct writes the system volume on nt6.x when the system is live. Other attached disks don't have this restriction. Writing to such a system volume could in theory be performed if system was booted to WinPE. Other than that you would need a special driver to achieve it. Dismounting a volume will effectively close all open handles on the volume!

Note
In certain of the NTFS system files, the record slack is actually evaluated when NTFS checks consistency. For instance mismatch in $MFT vs $MFTMirr will produce a warning. Letting chkdsk fix will only update $MFTMirr's $DATA attribute with the content of the new record slack in $MFT.. No big deal, it just works like that. This issue, if you can call it that, seems to only be present in the first 6 records. Injecting from record 6 thus will not produce any warning by chkdsk.

Syntax:
StegoMft.exe -hide InputFile TargetVolume StartRef Signature StartByte
StegoMft.exe -extract OutputFile TargetVolume StartRef Signature StartByte
StegoMft.exe -check TargetVolume StartRef EndRef StartByte
StegoMft.exe -clean TargetVolume StartRef EndRef StartByte
StegoMft.exe -dump TargetVolume Ref

Explanation:
StartRef is the first MFT record to start from. 0 is always the lowest.
EndRef is the last MFT record to process. The absolute last record number varies from volume to volume. Putting "-" will tell the program to process until the end. 
StartByte is the byte offset within the record slack. A value of 0 means at the very beginning of record slack. A value of 10 means the first 10 bytes of the original record slack will not be touched.


Sample commands:

Hiding inputfile.ext in $MFT from record number 666 at volume D: with signature 11223344 starting at slack byte 0:
StegoMft.exe -hide c:\inputfile.ext D: 666 11223344 0

Extracting hidden data from volume D: starting from record number 777 and signature 88888888 starting at slack byte 10 to outputfile.ext:
StegoMft.exe -extract c:\outputfile D: 777 88888888 10

Check number of record slack bytes in $MFT starting at slack byte 20 on volume D:
StegoMft.exe -check D: - - 20

Check number of record slack bytes in $MFT records 345-350 starting at slack byte 10 on volume D:
StegoMft.exe -check D: 345 350 10

Overwrite all record slack in $MFT at volume D:
StegoMft.exe -clean D: - - 0

Overwrite record slack from byte 4 in $MFT records 200-300 at volume D:
StegoMft.exe -clean D: 200 300 4

Dump to console the slack data in record 50 at volume D:
StegoMft.exe -dump D: 50

