/**
 * perl-libxml-mm.h
 * $Id$
 *
 * Basic concept:
 * perl varies in the implementation of UTF8 handling. this header (together
 * with the c source) implements a few functions, that can be used from within
 * the core module inorder to avoid cascades of c pragmas
 */

#ifndef __PERL_LIBXML_MM_H__
#define __PERL_LIBXML_MM_H__

#ifdef __cplusplus
extern "C" {
#endif
#include "EXTERN.h"
#include "perl.h"

#include <libxml/parser.h>

#ifdef __cplusplus
}
#endif

/*
 * NAME xs_warn 
 * TYPE MACRO
 * 
 * this makro is for XML::LibXML development and debugging. 
 *
 * SYNOPSIS
 * xs_warn("my warning")
 *
 * this makro takes only a single string(!) and passes it to perls
 * warn function if the XS_WARNRINGS pragma is used at compile time
 * otherwise any xs_warn call is ignored.
 * 
 * pay attention, that xs_warn does not implement a complete wrapper
 * for warn!!
 */
#ifdef XS_WARNINGS
#define xs_warn(string) warn(string) 
#else
#define xs_warn(string)
#endif

struct _ProxyNode {
    xmlNodePtr node;
    xmlNodePtr owner;
    int count;
};

/* helper type for the proxy structure */
typedef struct _ProxyNode ProxyNode;

/* pointer to the proxy structure */
typedef ProxyNode* ProxyNodePtr;

/* this my go only into the header used by the xs */
#define SvPROXYNODE(x) ((ProxyNodePtr)SvIV(SvRV(x)))

#define PmmREFCNT(node)      node->count
#define PmmREFCNT_inc(node)  node->count++
#define PmmNODE(xnode)       xnode->node
#define PmmOWNER(node)       node->owner
#define PmmOWNERPO(node)     ((node && PmmOWNER(node)) ? (ProxyNodePtr)PmmOWNER(node)->_private : node)

ProxyNodePtr
PmmNewNode(xmlNodePtr node);

ProxyNodePtr
PmmNewFragment(xmlDocPtr document);

SV*
PmmCreateDocNode( unsigned int type, ProxyNodePtr pdoc, ...);

int
PmmREFCNT_dec( ProxyNodePtr node );

SV*
PmmNodeToSv( xmlNodePtr node, ProxyNodePtr owner );

xmlNodePtr
PmmSvNode( SV * perlnode );

xmlNodePtr
PmmSvOwner( SV * perlnode );

SV*
PmmSetSvOwner(SV * perlnode, SV * owner );

void
PmmFixOwner(ProxyNodePtr node, ProxyNodePtr newOwner );

int
PmmContextREFCNT_dec( ProxyNodePtr node );

SV*
PmmContextSv( xmlParserCtxtPtr ctxt );

xmlParserCtxtPtr
PmmSvContext( SV * perlctxt );

/**
 * NAME domNodeTypeName
 * TYPE function
 * 
 * returns the perl class name for the given node
 *
 * SYNOPSIS
 * CLASS = domNodeTypeName( node );
 */
const char*
PmmNodeTypeName( xmlNodePtr elem );

xmlChar*
PmmEncodeString( const char *encoding, const char *string );

char*
PmmDecodeString( const char *encoding, const xmlChar *string);

/* string manipulation will go elsewhere! */

/*
 * NAME c_string_to_sv
 * TYPE function
 * SYNOPSIS
 * SV *my_sv = c_string_to_sv( "my string", encoding );
 * 
 * this function converts a libxml2 string to a SV*. although the
 * string is copied, the func does not free the c-string for you!
 *
 * encoding is either NULL or a encoding string such as provided by
 * the documents encoding. if encoding is NULL UTF8 is assumed.
 *
 */
SV*
C2Sv( const xmlChar *string, const xmlChar *encoding );

/*
 * NAME sv_to_c_string
 * TYPE function
 * SYNOPSIS
 * SV *my_sv = sv_to_c_string( my_sv, encoding );
 * 
 * this function converts a SV* to a libxml string. the SV-value will
 * be copied into a *newly* allocated string. (don't forget to free it!)
 *
 * encoding is either NULL or a encoding string such as provided by
 * the documents encoding. if encoding is NULL UTF8 is assumed.
 *
 */
xmlChar *
Sv2C( SV* scalar, const xmlChar *encoding );

SV*
nodeC2Sv( const xmlChar * string,  xmlNodePtr refnode );

xmlChar *
nodeSv2C( SV * scalar, xmlNodePtr refnode );

#endif
