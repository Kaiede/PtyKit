#ifndef _cstdlib_shim_h
#define _cstdlib_shim_h

#ifdef linux
#define _GNU_SOURCE
#define _PTYKIT_HACK
#endif // linux

#include <stdlib.h>
#include <fcntl.h>
#include <stdio.h>

#ifdef _PTYKIT_HACK
// This is a terrible workaround, but has to be done,
// because for whatever reason, while this header
// worked for test.c, it doesn't work when used
// in Swift. It simply never sees these APIs. 
//
// Define them manually until a proper fix can be found.
extern int posix_openpt (int __oflag) __wur;
extern int grantpt (int __fd) __THROW;
extern int unlockpt (int __fd) __THROW;
extern char *ptsname (int __fd) __THROW __wur;
#endif // _PTYKIT_HACK

#endif // _cstdlib_shim_h
