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
#define xs_warn(string) warn("%s",string) 
#else
#define xs_warn(string)
#endif

/*
 * @node: Reference to the node the structure proxies
 * @owner: libxml defines only the document, but not the node owner
 *         (in case of document fragments, they are not the same!)
 * @count: this is the internal reference count!
 * @encoding: this value is missing in libxml2's doc structure
 *
 * Since XML::LibXML will not know, is a certain node is already
 * defined in the perl layer, it can't shurely tell when a node can be
 * safely be removed from the memory. This structure helps to keep
 * track how intense the nodes of a document are used and will not
 * delete the nodes unless they are not refered from somewhere else.
 */
struct _ProxyNode {
    xmlNodePtr node;
    xmlNodePtr owner;
    int count;
    int encoding;
};

/* helper type for the proxy structure */
typedef struct _ProxyNode ProxyNode;

/* pointer to the proxy structure */
typedef ProxyNode* ProxyNodePtr;

/* this my go only into the header used by the xs */
#define SvPROXYNODE(x) (INT2PTR(ProxyNodePtr,SvIV(SvRV(x))))
#define PmmPROXYNODE(x) (INT2PTR(ProxyNodePtr,x->_private))
#define SvNAMESPACE(x) (INT2PTR(xmlNsPtr,SvIV(SvRV(x))))

#define PmmREFCNT(node)      node->count
#define PmmREFCNT_inc(node)  node->count++
#define PmmNODE(xnode)       xnode->node
#define PmmOWNER(node)       node->owner
#define PmmOWNERPO(node)     ((node && PmmOWNER(node)) ? (ProxyNodePtr)PmmOWNER(node)->_private : node)
#define PmmENCODING(node)    node->encoding
#define PmmNodeEncoding(node) ((ProxyNodePtr)(node->_private))->encoding
#define PmmDocEncoding(node) (node->charset)

#ifndef NO_XML_LIBXML_THREADS
#ifdef USE_ITHREADS
#define XML_LIBXML_THREADS
#endif
#endif

#ifdef XML_LIBXML_THREADS

/* structure for storing thread-local refcount */
struct _LocalProxyNode {
	ProxyNodePtr proxy;
	int count;
};
typedef struct _LocalProxyNode LocalProxyNode;
typedef LocalProxyNode* LocalProxyNodePtr;

#define PmmUSEREGISTRY		(PROXY_NODE_REGISTRY_MUTEX != NULL)
#define PmmREGISTRY		(INT2PTR(xmlHashTablePtr,SvIV(SvRV(get_sv("XML::LibXML::__PROXY_NODE_REGISTRY",0)))))
// #define PmmREGISTRY			(INT2PTR(xmlHashTablePtr,SvIV(SvRV(PROXY_NODE_REGISTRY))))

void
PmmCloneProxyNodes();
int
PmmProxyNodeRegistrySize();
void
PmmDumpRegistry(xmlHashTablePtr r);
void
PmmRegistryREFCNT_dec(ProxyNodePtr proxy);

#endif

void
PmmFreeHashTable(xmlHashTablePtr table);

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

/* PmmFixProxyEncoding
 * TYPE
 *    Method
 * PARAMETER
 *    @dfProxy: The proxystructure to fix.
 *
 * DESCRIPTION
 *
 * This little helper allows to fix the proxied encoding information
 * after a not standard operation was done. This is required for
 * XML::LibXSLT
 */
void
PmmFixProxyEncoding( ProxyNodePtr dfProxy );

/* PmmSvNodeExt
 * TYPE 
 *    Function
 * PARAMETER
 *    @perlnode: the perl reference that holds the scalar.
 *    @copy : copy flag
 *
 * DESCRIPTION
 *
 * The function recognizes XML::LibXML and XML::GDOME 
 * nodes as valid input data. The second parameter 'copy'
 * indicates if in case of GDOME nodes the libxml2 node
 * should be copied. In some cases, where the node is 
 * cloned anyways, this flag has to be set to '0', while
 * the default value should be allways '1'. 
 */
xmlNodePtr
PmmSvNodeExt( SV * perlnode, int copy );

/* PmmSvNode
 * TYPE
 *    Macro
 * PARAMETER
 *    @perlnode: a perl reference that holds a libxml node
 *
 * DESCRIPTION
 *
 * PmmSvNode fetches the libxml node such as PmmSvNodeExt does. It is
 * a wrapper, that sets the copy always to 1, which is good for all
 * cases XML::LibXML uses.
 */
#define PmmSvNode(n) PmmSvNodeExt(n,1)


xmlNodePtr
PmmSvOwner( SV * perlnode );

SV*
PmmSetSvOwner(SV * perlnode, SV * owner );

int
PmmFixOwner(ProxyNodePtr node, ProxyNodePtr newOwner );

void
PmmFixOwnerNode(xmlNodePtr node, ProxyNodePtr newOwner );

int
PmmContextREFCNT_dec( ProxyNodePtr node );

SV*
PmmContextSv( xmlParserCtxtPtr ctxt );

xmlParserCtxtPtr
PmmSvContext( SV * perlctxt );

/**
 * NAME PmmCopyNode
 * TYPE function
 *
 * returns libxml2 node
 *
 * DESCRIPTION
 * This function implements a nodetype independant node cloning.
 * 
 * Note that this function has to stay in this module, since
 * XML::LibXSLT reuses it.
 */
xmlNodePtr
PmmCloneNode( xmlNodePtr node , int deep );

/**
 * NAME PmmNodeToGdomeSv
 * TYPE function
 *
 * returns XML::GDOME node
 *
 * DESCRIPTION
 * creates an Gdome node from our XML::LibXML node.
 * this function is very usefull for the parser.
 *
 * the function will only work, if XML::LibXML is compiled with
 * XML::GDOME support.
 *    
 */
SV *
PmmNodeToGdomeSv( xmlNodePtr node );

/**
 * NAME PmmNodeTypeName
 * TYPE function
 * 
 * returns the perl class name for the given node
 *
 * SYNOPSIS
 * CLASS = PmmNodeTypeName( node );
 */
const char*
PmmNodeTypeName( xmlNodePtr elem );

xmlChar*
PmmEncodeString( const char *encoding, const xmlChar *string, STRLEN len );

char*
PmmDecodeString( const char *encoding, const xmlChar *string, STRLEN* len);

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
