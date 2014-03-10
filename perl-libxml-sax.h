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


/*
 * auxiliary macro to serve as an croak(NULL)
 * unlike croak(NULL), this version does not produce
 * a warning (see the perlapi for the meaning of croak(NULL))
 *
 */

#define croak_obj Perl_croak(aTHX_ NULL)


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
