/**
 * perl-libxml-mm.h
 * $Id$
 *
 * Basic concept:
 * perl varies in the implementation of UTF8 handling. this header (together
 * with the c source) implements a few functions, that can be used from within
 * the core module in order to avoid cascades of c pragmas
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
 * defined in the perl layer, it can't surely tell when a node can be
 * safely be removed from the memory. This structure helps to keep
 * track how intense the nodes of a document are used and will not
 * delete the nodes unless they are not referred from somewhere else.
 */
struct _ProxyNode {
    xmlNodePtr node;
    xmlNodePtr owner;
    int count;
};

struct _DocProxyNode {
    xmlNodePtr node;
    xmlNodePtr owner;
    int count;
    int encoding; /* only used for proxies of xmlDocPtr */
    int psvi_status; /* see below ... */
};

/* the psvi_status flag requires some explanation:

   each time libxml2 validates a document (using DTD, Schema or
   RelaxNG) it stores a pointer to a last successfully applied grammar
   rule in node->psvi. Upon next validation, if libxml2 wants to check
   that node matches some grammar rule, it first compares the rule
   pointer and node->psvi. If these are equal, the validation of the
   node's subtree is skipped and the node is assumed to match the
   rule.

   This causes problems when the tree is modified and then
   re-validated or when the schema is freed and the document is
   revalidated using a different schema and by bad chance a rule
   tested against some node got allocated to the exact same location
   as the rule from the schema used for the prior validation, already
   freed, but still pointed to by node->psvi).

   Thus, the node->psvi values can't be trusted at all and we want to
   make sure all psvi slots are NULL before each validation. To aviod
   traversing the tree in the most common case, when each document is
   validated just once, we maintain the psvi_status flag.

   Validating a document triggers this flag (sets it to 1).  The
   document with psvi_status==1 is traversed and psvi slots are nulled
   prior to any validation.  When the flag is triggered, it remains
   triggered for the rest of the document's life, there is no way to
   null it (even nulling up the psvi's does not null the flag, because
   there may be unlinked parts of the document floating around which
   we don't know about and thus cannot null their psvi pointers; these
   unlinked document parts would cause inconsistency when re-attached
   to the document tree).

   Also, importing a node from a document with psvi_status==1 to a
   document with psvi_status==0 automatically triggers psvi_status on
   the target document.

   NOTE: We could alternatively just null psvis from any imported
   subtrees, but that would add an O(n) cleanup operation (n the size
   of the imported subtree) on every importNode (possibly needlessly
   since the target document may not ever be revalidated) whereas
   triggering the flag is O(1) and possibly adds one O(N) cleanup
   operation (N the size of the document) to the first validation of
   the target document (any subsequent re-validation of the document
   would have to perform the operation anyway). The sum of all n's may
   be less then N, but OTH, there is a great chance that the O(N)
   cleanup will never be performed.  (BTW, validation is at least
   O(N), probably O(Nlog N) anyway, so the cleanup has little impact;
   similarly, importNode does xmlSetTreeDoc which is also O(n). So in
   fact, neither solution should have significant performance impact
   overall....).

*/

#define Pmm_NO_PSVI 0
#define Pmm_PSVI_TAINTED 1

/* helper type for the proxy structure */
typedef struct _DocProxyNode DocProxyNode;
typedef struct _ProxyNode ProxyNode;

/* pointer to the proxy structure */
typedef ProxyNode* ProxyNodePtr;
typedef DocProxyNode* DocProxyNodePtr;

/* this my go only into the header used by the xs */
#define SvPROXYNODE(x) (INT2PTR(ProxyNodePtr,SvIV(SvRV(x))))
#define PmmPROXYNODE(x) (INT2PTR(ProxyNodePtr,x->_private))
#define SvNAMESPACE(x) (INT2PTR(xmlNsPtr,SvIV(SvRV(x))))

#define PmmREFCNT(node)      node->count
#define PmmREFCNT_inc(node)  node->count++
#define PmmNODE(xnode)       xnode->node
#define PmmOWNER(node)       node->owner
#define PmmOWNERPO(node)     ((node && PmmOWNER(node)) ? (ProxyNodePtr)PmmOWNER(node)->_private : node)

#define PmmENCODING(node)    ((DocProxyNodePtr)(node))->encoding
#define PmmNodeEncoding(node) ((DocProxyNodePtr)(node->_private))->encoding

#define SetPmmENCODING(node,code) PmmENCODING(node)=(code)
#define SetPmmNodeEncoding(node,code) PmmNodeEncoding(node)=(code)

#define PmmInvalidatePSVI(doc) if (doc && doc->_private) ((DocProxyNodePtr)(doc->_private))->psvi_status = Pmm_PSVI_TAINTED;
#define PmmIsPSVITainted(doc) (doc && doc->_private && (((DocProxyNodePtr)(doc->_private))->psvi_status == Pmm_PSVI_TAINTED))

#define PmmClearPSVI(node) if (node && node->doc && node->doc->_private && \
                               ((DocProxyNodePtr)(node->doc->_private))->psvi_status == Pmm_PSVI_TAINTED) \
   domClearPSVI((xmlNodePtr) node)

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
/* #define PmmREGISTRY			(INT2PTR(xmlHashTablePtr,SvIV(SvRV(PROXY_NODE_REGISTRY)))) */

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
 * This function implements a nodetype independent node cloning.
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
 * this function is very useful for the parser.
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
