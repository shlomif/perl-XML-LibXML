/**
 * perl-libxml-sax.h
 * $Id$
 */

#ifndef __PERL_LIBXML_SAX_H__
#define __PERL_LIBXML_SAX_H__

#ifdef __cplusplus
extern "C" {
#endif

#include <libxml/tree.h>

#ifdef __cplusplus
}
#endif

/* has to be called in BOOT sequence */
void
PmmSAXInitialize(pTHX);

void
PmmSAXInitContext( xmlParserCtxtPtr ctxt, SV * parser, SV * saved_error );

void 
PmmSAXCloseContext( xmlParserCtxtPtr ctxt );

xmlSAXHandlerPtr
PSaxGetHandler();

#endif
