/* $Id: Devel.xs 20 2011-10-11 02:05:01Z jo $
 *
 * This is free software, you may use it and distribute it under the same terms as
 * Perl itself.
 *
 * Copyright 2011 Joachim Zobel
 *
 * This module gives external access to the functions needed to create
 * and use XML::LibXML::Nodes from C functions. These functions are made
 * accessible from Perl to have cleaner dependencies.
 * The idea is to pass xmlNode * pointers (as typemapped void *) to and
 * from Perl and call the functions that turns them to and from
 * XML::LibXML::Nodes there.
 *
 * Be aware that using this module gives you the ability to easily create
 * segfaults and memory leaks.
 */

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#include <stdlib.h>

/* XML::LibXML stuff */
#include <libxml/xmlmemory.h>
#include "perl-libxml-mm.h"

#undef NDEBUG
#include <assert.h>

static void *	xmlMemMallocAtomic(size_t size)
{
    return xmlMallocAtomicLoc(size, "none", 0);
}

static int debug_memory()
{
    return xmlGcMemSetup( xmlMemFree,
                          xmlMemMalloc,
                          xmlMemMallocAtomic,
                          xmlMemRealloc,
                          xmlMemStrdup);
}

MODULE = XML::LibXML::Devel		PACKAGE = XML::LibXML::Devel

PROTOTYPES: DISABLE

BOOT:
    if (getenv("DEBUG_MEMORY")) {
        debug_memory();
    }



SV*
node_to_perl( n, o = NULL )
        void * n
        void * o
    PREINIT:
        xmlNode *node = n;
        xmlNode *owner = o;
    CODE:
        RETVAL = PmmNodeToSv(node , owner?owner->_private:NULL );
    OUTPUT:
        RETVAL

void *
node_from_perl( sv )
        SV *sv
    PREINIT:
        xmlNode *n = PmmSvNodeExt(sv, 0);
    CODE:
        RETVAL = n;
    OUTPUT:
        RETVAL

void
refcnt_inc( n )
        void *n
    PREINIT:
        xmlNode *node = n;
    CODE:
        PmmREFCNT_inc(((ProxyNode *)(node->_private)));

int
refcnt_dec( n )
        void *n
    PREINIT:
        xmlNode *node = n;
    CODE:
        RETVAL = PmmREFCNT_dec(((ProxyNode *)(node->_private)));
    OUTPUT:
        RETVAL

int
refcnt( n )
        void *n
    PREINIT:
        xmlNode *node = n;
    CODE:
        RETVAL = PmmREFCNT(((ProxyNode *)(node->_private)));
    OUTPUT:
        RETVAL

int
fix_owner( n, p )
        void * n
        void * p
    PREINIT:
        xmlNode *node = n;
        xmlNode *parent = p;
    CODE:
        RETVAL = PmmFixOwner(node->_private , parent->_private);
    OUTPUT:
        RETVAL

int
mem_used()
    CODE:
        RETVAL = xmlMemUsed();
    OUTPUT:
        RETVAL


