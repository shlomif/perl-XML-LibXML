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

struct _ProxyObject {
    void * object;
    SV * extra;
};

typedef struct _ProxyObject ProxyObject;

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
C2Sv( xmlChar *string, const xmlChar *encoding );

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

ProxyObject *
make_proxy_node (xmlNodePtr node);
void 
free_proxy_node ( SV * nodesv );

/*
 * NAME node_to_sv
 * TYPE function
 * SYNOPSIS
 * SV *my_sv = node_to_sv(node)
 *
 * node_to_sv creates an proxy object and wraps it into a SV.
 * the node will not be copied.
 */
SV*
nodeToSv( xmlNodePtr node );

/*
 * NAME sv_get_node
 * TYPE function
 * SYNOPSIS
 * xmlNodePtr = sv_get_node(my_sv)
 *
 * simply reads the node value from the SV. it is not implemened as a 
 * MACRO to be analogue to node_to_sv.
 */
xmlNodePtr
getSvNode( SV* perlnode );

SV*
getSvNodeExtra( SV* perlnode );

SV*
setSvNodeExtra( SV* perlnode, SV* extra );

/*
 * NAME fix_dom
 * TYPE method
 * SYNOPSIS
 * fix_dom( node_to_fix, parent );
 *
 * fix_dom is ment to be used after each operation a node may change
 * the document it belongs to. this function will update the related
 * SV values.
 *
 * this function is required, so we can update the refcounts, so perl
 * won't delete a node/document/document_fragment if any childnode is
 * still refered by the perl layer.
 *
 * parent is a SV* pointing to the actual main node. this may is a
 * document or a document_frag at the moment.
 */
void
fix_proxy_extra( SV* nodetofix, SV* parent ); 

#endif
