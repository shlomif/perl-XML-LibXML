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

xmlSAXHandlerPtr
PSaxGetHandler();

#endif
