/* parser.c
 * $Id$
 * Author: Christian Glahn (2001) 
 *
 * This modules keeps the the c-implementation of the multiple parser
 * implementation. I think this module is required, so we keep the
 * perl implementation clear of adding c-features to
 *
 * TODO:
 * add all parser flags to the parser object
 */
#ifdef __cplusplus
extern "C" {
#endif

#include <stdio.h> /* for the globals we don't have in libxml */
#include <libxml/parser.h>
#include <libxml/parserInternals.h>
#include <libxml/tree.h>
#include <libxml/xmlIO.h>
#include <libxml/xmlmemory.h>
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

    void * error_fh; /* e.g. standard out */

    /* library parser flags */
    int substitute_entities; 
    int keep_blanks;
    int get_warnings;
    int load_ext_entities;
    int do_validation;
    int be_pedantic;
};

/* we have to redefine the header stuff to avoid the include */
typedef struct _perlxmlParserObject perlxmlParserObject;
typedef perlxmlParserObject *perlxmlParserObjectPtr;

/**
 * perlxmlInitParserObject
 * 
 * perlxmlParserObjectPtr * objectPtr: is a pointer to the object reference.
 *
 * Description:
 *
 * This function creates a new ParserObject in memory. The objectPtr
 * parameter should be a reference to NULL (but not NULL itself!), the
 * reference to the new perlxmlParserObject will be left in this
 * reference. 
 *
 **/
void
perlxmlInitParserObject( perlxmlParserObjectPtr * objectPtr )
{
    if ( objectPtr != NULL  ) {
        /* we create only a new parser object if the parameter is not
         * already a parseobject 
         */
        (*objectPtr) = (perlxmlParserObjectPtr)xmlMalloc( sizeof( perlxmlParserObject ) );
        if ( (*objectPtr) != NULL ) {
            (*objectPtr)->match_cb         = NULL;
            (*objectPtr)->read_cb          = NULL;
            (*objectPtr)->open_cb          = NULL;
            (*objectPtr)->close_cb         = NULL;
            (*objectPtr)->error_cb         = NULL;
            (*objectPtr)->entity_loader_cb = NULL;

            (*objectPtr)->SAX_handler      = NULL;
            (*objectPtr)->error_fh         = NULL;

            (*objectPtr)->substitute_entities = 1;
            (*objectPtr)->keep_blanks         = 1;
            (*objectPtr)->get_warnings        = 0;
            (*objectPtr)->load_ext_entities   = 5;
            (*objectPtr)->do_validation       = 0;
            (*objectPtr)->be_pedantic         = 0;
        }
    }
}

/**
 * perlxmlDestroyParserObject
 *
 * perlxmlParserObjectPtr * objectPtr: is a pointer to the object reference.
 * 
 * Description:
 *
 * this function will remove the parser object from memory. the
 * reference to the parser object will be NULL. The function will not
 * touch any of the callback references (just reset them to NULL)
 * before destroying the parser object.
 *
 **/
void
perlxmlDestroyParserObject( perlxmlParserObjectPtr * objectPtr )
{
    if ( objectPtr != NULL ) {
        (*objectPtr)->match_cb         = NULL;
        (*objectPtr)->read_cb          = NULL;
        (*objectPtr)->open_cb          = NULL;
        (*objectPtr)->close_cb         = NULL;
        (*objectPtr)->error_cb         = NULL;
        (*objectPtr)->entity_loader_cb = NULL;

        (*objectPtr)->SAX_handler      = NULL;
            
        (*objectPtr)->substitute_entities = 0;
        (*objectPtr)->keep_blanks         = 0;
        (*objectPtr)->get_warnings        = 0;
        (*objectPtr)->load_ext_entities   = 0;
        (*objectPtr)->do_validation       = 0;
        (*objectPtr)->be_pedantic         = 0;

        xmlFree( *objectPtr );
        *objectPtr = NULL;
    }
}

/* the following functions are simply wrappers for the libxml2 functions */

void
perlxmlInitLibParser ( perlxmlParserObjectPtr parser ) 
{
    if ( parser != NULL ) {
        int regtest = -1;
/*         xmlInitParser(); */
        if ( parser->match_cb != NULL 
             || parser->open_cb != NULL
             || parser->read_cb != NULL
             || parser->close_cb != NULL ) {

            regtest = xmlRegisterInputCallbacks(
                                                parser->match_cb,
                                                parser->open_cb,
                                                parser->read_cb,
                                                parser->close_cb
                                                );
        }

        if ( regtest != -1 ) {
            printf( "%d \n",regtest );
        }

        xmlSetExternalEntityLoader( parser->entity_loader_cb );
        xmlSetGenericErrorFunc(parser->error_fh, parser->error_cb );

        xmlSubstituteEntitiesDefaultValue = parser->substitute_entities;
        xmlKeepBlanksDefaultValue = parser->keep_blanks;
        xmlGetWarningsDefaultValue = parser->get_warnings;
        xmlLoadExtDtdDefaultValue = parser->load_ext_entities;
        xmlPedanticParserDefaultValue = parser->be_pedantic;
        xmlDoValidityCheckingDefaultValue = parser->do_validation;
    }
}

void
perlxmlCleanupLibParser ( perlxmlParserObjectPtr parser ) 
{
    if ( parser != NULL ) {
        xmlSubstituteEntitiesDefaultValue = 1;
        xmlKeepBlanksDefaultValue = 1;
        xmlSetExternalEntityLoader( NULL );
        xmlSetGenericErrorFunc( NULL, NULL );
        xmlGetWarningsDefaultValue = 0;
        xmlLoadExtDtdDefaultValue = 5;

        xmlPedanticParserDefaultValue = 0;
        xmlDoValidityCheckingDefaultValue = 0;

        /* here we should be able to unregister our callbacks.
         * since we know the id, this function should expect this id
         * to remove this handler set.
         * another opinion would be a callback pop, that pops the last
         * callback function off the callback stack
         */

/*         xmlCleanupParser(); */
    }
}

xmlDocPtr
perlxmlParseFile( perlxmlParserObjectPtr parserObject,
                  xmlChar * filename ) 
{
    xmlDocPtr retval = NULL;
    if ( parserObject != NULL && filename != NULL ) {
        perlxmlInitLibParser( parserObject );
        retval = xmlParseFile( filename );
        perlxmlCleanupLibParser(parserObject);
    }
    return retval;
}

xmlDocPtr
perlxmlParseMemory( perlxmlParserObjectPtr parserObject, 
                    const char *buffer,
                    int size )
{
    xmlDocPtr retval = NULL;
    if ( parserObject != NULL && buffer != NULL && size != 0 ) {
        perlxmlInitLibParser( parserObject );
        retval = xmlParseMemory( buffer, size );
        perlxmlCleanupLibParser(parserObject);
    }
    return retval;
}

xmlDocPtr
perlxmlParseDoc( perlxmlParserObjectPtr parserObject,
                 xmlChar * cur )
{
    xmlDocPtr retval = NULL;
    if ( parserObject != NULL && cur != NULL ) {
        perlxmlInitLibParser( parserObject );
        retval = xmlParseDoc( cur );
        perlxmlCleanupLibParser(parserObject);
    }
    return retval;
}

/**
 * Name: perlxmlParseBalancedChunkMemory
 * Synopsis: xmlNodePtr perlxmlParseBalancedChunkMemory( perlxmlParserObjectPtr parser,xmlDocPtr doc, xmlChar *string )
 * @parser: the parserobject
 * @doc: the document, the string should belong to
 * @string: the string to parse
 *
 * this function is pretty neat, since you can read in well balanced 
 * strings and get a list of nodes, which can be added to any other node.
 * (shure - this should return a doucment_fragment, but still it doesn't)
 *
 * the code is pretty heavy i think, but deep in my heard i believe it's 
 * worth it :) (e.g. if you like to read a chunk of well-balanced code 
 * from a databasefield)
 *
 * in 99% the cases i believe it is faster than to create the dom by hand,
 * and skip the parsing job which has to be done here.
 **/
xmlNodePtr
perlxmlParseBalancedChunkMemory( perlxmlParserObjectPtr parserObject, 
                                 xmlDocPtr document,
                                 const xmlChar * string ){
    int parserreturn = -1;
    xmlNodePtr helper = NULL;
    xmlNodePtr retval = NULL;

    if ( parserObject != NULL && document != NULL && string != NULL ) {
        perlxmlInitLibParser( parserObject );

        parserreturn = xmlParseBalancedChunkMemory( document,
                                                    parserObject->SAX_handler,
                                                    NULL,
                                                    0,
                                                    string,
                                                    &retval );

        /* error handling */
        if ( parserreturn != 0 ) {
            /* if the code was not well balanced, we will not return 
             * a bad node list, but we have to free the nodes */
            while( retval != NULL ) {
                helper = retval->next;
                xmlFreeNode( retval );
                retval = helper;
            }
        }

        perlxmlCleanupLibParser( parserObject );
    }
    return retval;
}

void 
perlxmlSetErrorCallback( perlxmlParserObjectPtr parserObject, 
                         xmlGenericErrorFunc error_callback )
{
    if ( parserObject != NULL ) {
        parserObject->error_cb = error_callback;
    }
}

void
perlxmlSetExtEntityLoader( perlxmlParserObjectPtr parserObject,
                           xmlExternalEntityLoader entity_loader )
{
    if ( parserObject != NULL ) {
        parserObject->entity_loader_cb = entity_loader;
    }
}

void
perlxmlSetOpenCallback( perlxmlParserObjectPtr parserObject,
                        xmlInputOpenCallback open_callback)
{
    if ( parserObject != NULL ) {
        parserObject->open_cb = open_callback;
    }
}

void
perlxmlSetCloseCallback( perlxmlParserObjectPtr parserObject,
                         xmlInputCloseCallback close_callback)
{
    if ( parserObject != NULL ) {
        parserObject->close_cb = close_callback;
    }
}

void
perlxmlSetMatchCallback( perlxmlParserObjectPtr parserObject,
                         xmlInputMatchCallback match_callback )
{
    if ( parserObject != NULL ) {
        parserObject->match_cb = match_callback;
    }
}

void
perlxmlSetReadCallback( perlxmlParserObjectPtr parserObject,
                        xmlInputReadCallback read_callback )
{
    if ( parserObject != NULL ) {
        parserObject->read_cb = read_callback;
    }
}

void
perlxmlSetErrorOutHandler( perlxmlParserObjectPtr parserObject,
                           void * error_fh )
{
    if ( parserObject != NULL ) {
        parserObject->error_fh = error_fh;
    }
}

/* need the html functions too */
