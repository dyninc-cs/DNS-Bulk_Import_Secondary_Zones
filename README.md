Dyn Inc, Integration Team Deliverable
"Copyright © 2013, Dyn Inc.
All rights reserved.
 
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:
 
* Redistribution of source code must retain the above copyright notice,
  this list of conditions and the following disclaimer.
 
* Redistribution in binary form must reproduce the above copyright
  notice, this list of conditions and the following disclaimer in the
  documentation and/or other materials provided with the distribution.
 
* Neither the name of Dynamic Network Services, Inc. nor the names of
  its contributors may be used to endorse or promote products derived
  from this software without specific prior written permission.
 
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
ADVISED OF THE POSSIBILITY OF SUCH DAMAGE."

___________________________________________________________________________________


    This script does a bulk import of secondary zones.
    
    The zone name of each new secondary zone needs to be specified
    in a text file containing one zone per line.

    A configuration file called config.cfg containing DynECT
    login credentials, one or more masters, and optionally a
    TSIG key should exist in the same directory.
    The file config.cfg takes the format:

    [Dynect]
    cn: [customer name]
    un: [username]
    pw: [password]
    ip: [one or more comma separated A or AAAA records]
    tsig: [TSIG key]

    Usage: %perl ibsz.pl -F FILE [options]

    Options
        -f, --file FILE         Specify the text file containing a list of zone names
        -t, --tsig              Indicate whether TSIG key is included in config.cfg
        -h, --help              Show this help message and exit
