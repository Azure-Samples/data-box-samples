---
title: Checksum for individual files
description: Calculate checksum for individual files locally using java based test program
services: databox
author: ramgana 

ms.service: databox
ms.subservice: databox/databox disk/databox heavy
ms.topic: sample
ms.date: 03/12/2024
ms.author: ramgana

# Customer intent: Customer would want to verify the data integrity of the file uploaded to Azure with the source file on-premise from where the data was originally copied to DataBox.
---

Background:
Data Box currently calculates a checksum for every file that is copied onto the device, 
and then generates a checksum again as the file is uploaded to Azure. 
The upload service matches the two to validate that the file on the device is what was uploaded to the cloud, and in case there are any checksum mismatches/errors, 
the upload service will raise a flag and customers can retry uploading those files directly.

What's new: Based on the requests from customers to extend this to also validate against the source 
– i.e. the data repository on-premise from where the data was originally copied to the Data Box, 
thereby making it actual E2E validation. 
This solution allows customer to independently calculate checksum for every file by passing it as an argument to the test function. 
This solution is a java based reference implementation of the core library with a sample test/driver program
With this solution, the customer can now calculate checksum of any file and compare it with what was uploaded to Azure.

CRC64.java is the source file which has the functionality to compute the checksum.
The Main function in test.java can be used to exercise it.

The Main function in test code takes a set of files as inputs, for computing CRC
The files should be accessible, in terms of access and permissions.
The files should be absolute path values.
The test function gives the crc64 of each of the files in the same format as that of the BOM of databox.