/* parser.h
 * $Id$
 * Author: Christian Glahn (2001) 
 *
 * This header keeps the the c-part of the multiple parser
 * implementation. I think this module is required, so we keep the
 * perl implementation clear of adding c-features to 
 *
 * TODO:
 * add all parser flags
 */

#ifndef __LIBXML_PARSER_H__
#define __LIBXML_PARSER_H__

#ifdef __cplusplus
extern "C" {
#endif

#include <libxml/parser.h>
#include <libxml/xmlIO.h>
#include <libxml/xpath.h>
#include <libxml/xmlerror.h>

#ifdef __cplusplus
}
#endif

struct _perlxmlParserObject 
{
    /* general callbacks */
    xmlInputMatchCallback match_cb;
    xmlInputReadCallback read_cb;
    xmlInputOpenCallback open_cb;
    xmlInputCloseCallback close_cb;

    xmlGenericErrorFunc error_cb;
    xmlExternalEntityLoader entity_loader_cb;

    /* then the pseudo sax handler */
    xmlSAXHandlerPtr SAX_handler; /* this is for the time when daniel 
                                   * implemented real SAX funcitonality 
                                   */

    void * error_fh;

    /* library parser flags */
    int substitute_entities; 
    int keep_blanks;
    int get_warnings;
    int load_ext_entities;
    int do_validation;
    int be_pedantic;
};

typedef struct _perlxmlParserObject perlxmlParserObject;
typedef perlxmlParserObject *perlxmlParserObjectPtr;

void
perlxmlInitParserObject( perlxmlParserObjectPtr * objectPtr );

void
perlxmlDestroyParserObject( perlxmlParserObjectPtr * objectPtr );

/* the following 2 functions are used to init the library parser with a parserobject */
void
perlxmlInitLibParser ( perlxmlParserObjectPtr parser );

void
perlxmlCleanupLibParser ( perlxmlParserObjectPtr parser );

/* the following functions are simply wrappers for the libxml2 functions */

xmlDocPtr
perlxmlParseFile( perlxmlParserObjectPtr object,
                  xmlChar * filename );

xmlDocPtr
perlxmlParseMemory( perlxmlParserObjectPtr object, 
                    const char * buffer,
                    int size );

xmlDocPtr
perlxmlParseDoc( perlxmlParserObjectPtr object,
                 xmlChar * cur );

xmlNodeSetPtr
perlxmlParseBalancedChunkMemory( perlxmlParserObjectPtr object, 
                                 xmlDocPtr document,
                                 const xmlChar * string );
                                 
                               

void 
perlxmlSetErrorCallback( perlxmlParserObjectPtr parser, 
                         xmlGenericErrorFunc error_callback );

void
perlxmlSetExtEntityLoader( perlxmlParserObjectPtr parser,
                           xmlExternalEntityLoader entity_loader );

void
perlxmlSetOpenCallback( perlxmlParserObjectPtr parser,
                        xmlInputOpenCallback open_callback);

void
perlxmlSetCloseCallback( perlxmlParserObjectPtr parser,
                         xmlInputCloseCallback close_callback);

void
perlxmlSetMatchCallback( perlxmlParserObjectPtr parser,
                         xmlInputMatchCallback match_callback );

void
perlxmlSetReadCallback( perlxmlParserObjectPtr parser,
                        xmlInputReadCallback match_callback );

void
perlxmlSetErrorOutHandler( perlxmlParserObjectPtr parserObject,
                           void * error_fh );

#endif
