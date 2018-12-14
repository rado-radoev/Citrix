# Citrix vDisk Patching Automation, PVS Automation, Citrix Windows Patching

This script is an attempt to automatically patch vDisk. It will automatically connect to PVS,
open maintenance on all the vDisks, connect to vShpere, boot the servers, run the Windows patching .... and that's it.
It stops there. It turned out it is difficult to track the progress of Windows updates prior server 2012. I thought about
using sockets or REST API calls to track the status, but Server 2008 and powershell v3 are missing some functionality 
that made it very difficult to maintaint the update status past a reboot. ... And I kind of left it there, but the rest is working

it took a lot of time and digging through the PVS api to do all those things, so I hope it is useful to anybody
